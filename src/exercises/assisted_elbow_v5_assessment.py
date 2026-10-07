"""Experimental V5 form classifier + V6 acceptance-based arm controller.

The expected side is a protocol instruction, not independent observed-arm proof.
Image angles/proximity and binary form suggestions are not clinical validation.
The previous V2 model is retained on disk; the app uses this model.
"""
import base64
from collections import deque
import json
from pathlib import Path
from uuid import uuid4

import cv2
import numpy as np

from src.features import elbow_research_v5 as form
from src.features import elbow_research_v7 as quality
from src.feedback.elbow_research_cycle import AlternatingCycleController, CycleConfig
from src.inference.elbow_research_observation import observation_guard
from src.feedback.elbow_telemetry import movement_metrics, annotate_review


class AssistedElbowV5Assessment:
    uses_world_landmarks = True

    def __init__(self, model, device=None, fps=20., data_dir='data',
                 save_artifacts=True, starting_hand='Left'):
        self.model = model
        self.fps = float(fps)
        self.save_artifacts = save_artifacts
        self.data_dir = Path(data_dir)
        config = json.loads((Path(__file__).resolve().parents[2] / 'models' /
                             'assisted_elbow_v5_controller.json').read_text())
        self.controller = AlternatingCycleController(starting_hand, True, CycleConfig(**config))
        self.smoothers = {h: form.CausalSmoother() for h in ('Left', 'Right')}
        self.quality_smoothers = {h: quality.CausalSmoother() for h in ('Left', 'Right')}
        self.samples = deque()
        self.last_time = None
        self.size = None
        self.rep_count = 0
        self.last_result = {}
        self.telemetry = self.controller.live_state()
        self.feedback = ('Start with your ' + starting_hand.lower() + ' arm, supported by your ' +
                         ('right' if starting_hand == 'Left' else 'left') + ' hand. Keep both arms visible.')
        self.review_frame = None
        self.review_landmarks = None
        self.review_angle = np.inf
        self.live_metrics = {}

    @staticmethod
    def _array(landmarks):
        if landmarks is None:
            return np.full((33, 4), np.nan)
        values = np.asarray([[lm.x, lm.y, lm.z, getattr(lm, 'visibility', 0.)]
                             for lm in landmarks.landmark], float)
        return values if values.shape == (33, 4) else np.full((33, 4), np.nan)

    def _reset_tracking(self):
        self.controller.reset_tracking()
        self.controller.pending = None
        self.controller.buffer.clear()
        self.controller.last_t = None
        self.controller.last_end = -np.inf
        self.controller.rearm_at = -np.inf
        self.samples.clear()
        for smoother in [*self.smoothers.values(), *self.quality_smoothers.values()]:
            smoother.reset()
        self.review_frame = None
        self.review_landmarks = None
        self.review_angle = np.inf
        self.live_metrics = {}

    def _review_image(self, hand, metrics):
        if self.review_frame is None:
            return None
        image = annotate_review(self.review_frame, self.review_landmarks, hand, metrics, 'Movement flagged')
        if self.save_artifacts:
            target = self.data_dir / 'error_frames'
            target.mkdir(parents=True, exist_ok=True)
            filename = 'elbow-v5-' + uuid4().hex + '.jpg'
            if cv2.imwrite(str(target / filename), image):
                return filename
            return None
        ok, encoded = cv2.imencode('.jpg', image, [cv2.IMWRITE_JPEG_QUALITY, 75])
        return 'data:image/jpeg;base64,' + base64.b64encode(encoded).decode('ascii') if ok else None

    def process_frame(self, frame, pose_landmarks, frame_number=0,
                      world_landmarks=None, timestamp_sec=None):
        t = float(timestamp_sec if timestamp_sec is not None else frame_number / self.fps)
        height, width = frame.shape[:2]
        if self.last_time is not None and (t <= self.last_time or t - self.last_time > .5):
            self._reset_tracking()
        if self.size is not None and self.size != (width, height):
            self._reset_tracking()
        self.last_time = t
        self.size = (width, height)
        image, world = self._array(pose_landmarks), self._array(world_landmarks)
        measurements, quality_rows, raw_quality = {}, {}, {}
        for hand in ('Left', 'Right'):
            raw = form.channels(world[None], image[None], width, height, hand)[0]
            raw_quality[hand] = quality.channels(world[None], image[None], width, height, hand)[0]
            visible = np.isfinite(raw_quality[hand][quality.REQUIRED_IMAGE_CHANNELS]).all()
            if not visible:
                raw[:] = np.nan
            measurements[hand] = self.smoothers[hand].update(raw, t)
            quality_rows[hand] = self.quality_smoothers[hand].update(raw_quality[hand], t)
        self.samples.append((t, world, image, measurements, quality_rows, raw_quality))
        while self.samples and t - self.samples[0][0] > self.controller.config.maximum_duration + 1.:
            self.samples.popleft()
        event, self.telemetry = self.controller.update(t, measurements)
        current = measurements[self.controller.hand][0]
        if self.telemetry['stage'] == 'READY':
            self.review_angle = np.inf
        if np.isfinite(current) and current < self.review_angle:
            self.review_angle = current
            self.review_frame = frame.copy()
            self.review_landmarks = image.copy()
        if self.controller.start is not None:
            live = [r for r in self.samples if r[0] >= self.controller.start]
            self.live_metrics = movement_metrics([r[3][self.controller.hand][0] for r in live],
                                                 [r[0] for r in live], self.controller.high)
        if self.telemetry.get('tracking') == 'UNASSESSED':
            self.feedback = 'Keep both shoulders, elbows and supporting hand visible. Retry the same arm.'
        elif event is None and self.telemetry['stage'] in ('FLEXING', 'RETURNING'):
            self.feedback = ('Bend smoothly with support.' if self.telemetry['stage'] == 'FLEXING'
                             else 'Return smoothly to your starting position.')
        if event is None:
            return None
        hand = event['hand']
        samples = [r for r in self.samples if event['start_sec'] <= r[0] <= event['end_sec'] + 1e-9]
        times = np.asarray([r[0] for r in samples])
        trace = np.asarray([r[3][hand] for r in samples])
        qtrace = np.asarray([r[4][hand] for r in samples])
        qraw = np.asarray([r[5][hand] for r in samples])
        images = np.asarray([r[2] for r in samples])
        if len(times) < 8:
            self.controller.confirm_rep(False)
            self.feedback = 'Not enough visible movement to assess. Retry the same arm.'
            return None
        feature, qc = form.rep_features(trace, times)
        observation, observation_qc = quality.rep_features(qtrace, times)
        guard = observation_guard(qraw, images, width, height, times, hand,
                                  np.ones(len(times), bool))
        if feature is None or observation is None or guard['reason']:
            self.controller.confirm_rep(False)
            self.feedback = 'Movement could not be assessed. Keep both arms visible and retry the same arm.'
            self.telemetry = {**self.controller.live_state(), 'tracking': 'UNASSESSED'}
            return None
        margin = float(self.model.decision_function(feature[None])[0])
        if not np.isfinite(margin):
            self.controller.confirm_rep(False)
            self.feedback = 'Movement could not be assessed. Retry the same arm.'
            return None
        good = margin <= 0.
        self.rep_count += 1
        self.controller.confirm_rep(good)
        self.feedback = ('Model accepted this movement. Change to your ' +
                         self.controller.hand.lower() + ' arm with opposite-hand support.' if good else
                         'Model flagged this movement. Review the demonstration and retry the same arm.')
        metrics = movement_metrics(qtrace[:, 0], times, event['baseline'])
        # A low model margin is not calibrated confidence. Detailed feedback
        # describes measured motion and does not invent a diagnosed fault.
        details = [self.feedback,
                   f"Measured elbow movement: {metrics.get('range_of_motion', 0):.0f} degrees in {event['duration']:.1f} seconds."]
        if metrics.get('return_completion', 100.) < 85.:
            details.append('Return closer to your own starting position while keeping support.')
        if metrics.get('smoothness', 100.) < 60.:
            details.append('Try a steadier movement without rushing.')
        self.feedback = ' '.join(details)
        review = None if good else self._review_image(hand, metrics)
        self.last_result = {
            'rep_number': self.rep_count, 'form': 'Correct' if good else 'Incorrect',
            'predicted_label': 'correct' if good else 'incorrect',
            **metrics, 'confidence': None, 'decision_score': margin,
            'model_identity': 'Assisted_Elbow_Flexion_V5_SVM_V6_Controller',
            'model_version': 'SVM_V5_Controller_V6_Telemetry2', 'experimental': True,
            'clinically_validated': False, 'observed_arm_verified': False,
            'camera_reference_verified': False, 'support_contact_verified': False,
            'range_of_motion': float(observation[quality.NAMES.index('active_angle_excursion')]),
            'duration': event['duration'], 'feedback': self.feedback,
            'error_type': '' if good else 'MODEL_FORM_REVIEW',
            'hand': hand, 'expected_hand': self.controller.hand,
            'rep_status': 'COMPLETED', 'status': 'COMPLETED',
            'speed': f"{metrics.get('angular_speed', 0):.0f}°/s",
            'angle_trace': [{'seconds': round(float(tm-times[0]), 3), 'angle': round(float(a), 1)}
                            for tm, a in zip(times[::max(1, len(times)//60)], qtrace[::max(1, len(times)//60), 0]) if np.isfinite(a)],
            'tracking_coverage': float(np.isfinite(qtrace[:, 0]).mean()),
            'stage_tracking_coverage': guard.get('critical_stage_both_arm_coverage'),
            'feedback_details': details,
            'review_frame_kind': 'movement_review_not_localized_clinical_fault',
        }
        if review:
            self.last_result['error_frame_path'] = review
        self.telemetry = self.controller.live_state()
        self.live_metrics = {}
        return self.last_result

    def get_live_state(self, pose_landmarks=None):
        landmarks = [] if pose_landmarks is None else [
            {'x': float(lm.x), 'y': float(lm.y), 'z': float(lm.z),
             'visibility': float(getattr(lm, 'visibility', 0.))} for lm in pose_landmarks.landmark]
        angle = self.telemetry.get('angle')
        metrics = self.live_metrics if self.telemetry.get('stage') in ('FLEXING', 'RETURNING') else self.last_result
        state = {'exercise': 'Assisted Elbow Flexion',
                 'rep_count': self.rep_count, 'correct_reps': self.controller.correct_reps,
                 'state': self.telemetry.get('stage', 'READY'),
                 'angle': float(angle) if angle is not None and np.isfinite(angle) else 0.,
                 'form': self.last_result.get('form', 'Waiting'),
                 'score': metrics.get('score'), 'confidence': None, 'feedback': self.feedback,
                 'range_of_motion': metrics.get('range_of_motion', 0.),
                 'error_type': self.last_result.get('error_type', ''),
                 'expected_hand': self.controller.hand, 'detected_mode': 'Expected ' + self.controller.hand,
                 'speed': f"{metrics['angular_speed']:.0f}°/s" if metrics.get('angular_speed') is not None else 'Waiting',
                 'smoothness': metrics.get('smoothness'), 'duration': metrics.get('duration'),
                 'minimum_angle': metrics.get('minimum_angle'), 'maximum_angle': metrics.get('maximum_angle'),
                 'return_completion': metrics.get('return_completion'),
                 'score_kind': 'descriptive_movement_control',
                 'detection_tolerances': self.controller.config.__dict__,
                 'landmarks': landmarks,
                 'model_version': 'SVM_V5_Controller_V6_Telemetry2', 'experimental': True,
                 'clinically_validated': False, 'camera_reference_verified': False}
        if self.last_result.get('error_frame_path'):
            state['error_frame_path'] = self.last_result['error_frame_path']
        return state
