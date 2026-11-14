"""V4 right-arm model adapter with complete-cycle and visibility guards.

Feature construction and form decisions retain the author's contract. Timestamp
handling and calibration prevent network cadence/lost tracking from inventing
repetitions. Model output is an uncalibrated score, not clinical confidence.
"""
import base64
from collections import deque
from pathlib import Path
from uuid import uuid4

import cv2
import numpy as np
import torch

from src.features.elbow_features_v4 import extract_angles, normalized_features
from src.feedback.elbow_telemetry import annotate_review, movement_metrics

MODEL_VERSION = 'Elbow_LSTM_V4_22F'


class FullRepDetector:
    """Author's direction/return policy, with time measured in seconds."""
    def __init__(self):
        self.last_rep_time = -np.inf
        self.rep_direction = None
        self.reset()

    def reset(self, baseline=None):
        self.state = 'READY'
        self.baseline = baseline
        self.start = None
        self.extreme = None
        self.max_rom = 0.
        self.velocity = deque(maxlen=5)

    def update(self, angle, velocity, t):
        self.velocity.append(velocity)
        speed = float(np.mean(self.velocity))
        movement = 'UP' if speed > .18 else 'DOWN' if speed < -.18 else 'HOLD'
        if t - self.last_rep_time < .1:
            return None
        if self.baseline is None:
            self.baseline = angle
        if self.state == 'READY':
            if self.rep_direction is None:
                if movement in ('UP', 'DOWN') and abs(angle - self.baseline) >= 18.:
                    self.rep_direction = movement
                else:
                    return None
            if movement == self.rep_direction:
                self.state, self.start, self.extreme = 'MOVING', t, angle
            return None
        self.extreme = max(self.extreme, angle) if self.rep_direction == 'UP' else min(self.extreme, angle)
        self.max_rom = max(self.max_rom, abs(self.extreme - self.baseline))
        duration = t - self.start
        if duration > 15.:
            self.reset(angle)
            return None
        if self.state == 'MOVING':
            opposite = 'DOWN' if self.rep_direction == 'UP' else 'UP'
            if self.max_rom >= 30. and movement == opposite:
                self.state = 'RETURNING'
            return None
        if abs(angle - self.baseline) <= 18. and self.max_rom >= 30. and .35 <= duration <= 15.:
            result = (self.start, t, self.baseline)
            self.last_rep_time = t
            self.reset(angle)
            return result
        return None


def classify_movement(seq, probability, duration):
    """Preserve V4 thresholds and weights; feedback respects prescribed range."""
    seq = np.asarray(seq, dtype=np.float32)
    rom = float(np.ptp(seq[:, 0]))
    shoulder = float(np.max(np.linalg.norm(seq[:, 7:9] - seq[0, 7:9], axis=1)))
    jerk = float(np.std(np.diff(np.gradient(seq[:, 0]))))
    rom_score = 100 if rom >= 120 else 95 if rom >= 90 else 80 if rom >= 60 else 55 if rom >= 30 else 20
    shoulder_score = 100 if shoulder <= .03 else 75 if shoulder <= .06 else 50 if shoulder <= .09 else 25
    smooth_score = 100 if jerk <= 12 else 85 if jerk <= 20 else 65 if jerk <= 30 else 40
    score = int(np.clip(round(.35 * rom_score + .20 * shoulder_score + .15 * smooth_score + .30 * probability * 100), 0, 100))
    correct = probability >= .25 and rom >= 30 and shoulder <= .09 and (
        (probability >= .60 and score >= 68) or
        (probability >= .50 and score >= 78 and rom >= 60 and shoulder <= .06))
    problems = []
    if rom < 90:
        problems.append('Follow the elbow range prescribed by your doctor; do not force the movement.')
    if shoulder > .06:
        problems.append('Keep your shoulder more stable.')
    if jerk > 20:
        problems.append('Try a steadier movement without rushing.')
    if duration < .45:
        problems.append('Slow down and keep the movement controlled.')
    if duration > 7:
        problems.append('Maintain a comfortable, steady pace.')
    if correct:
        feedback = ['Model accepted this movement.', 'Return smoothly to your starting position.']
    else:
        feedback = ['Model flagged this movement. Review the demonstration.'] + problems[:2]
    return {'form': 'Correct' if correct else 'Incorrect', 'score': score,
            'feedback_details': feedback, 'shoulder_movement': shoulder,
            'model_smoothness': jerk, 'range_of_motion': rom}


class ElbowV4Assessment:
    uses_timestamps = True

    def __init__(self, model, device, fps=20., data_dir='data', save_artifacts=True):
        self.model, self.device, self.fps = model, device, max(float(fps), 1.)
        root = Path(__file__).resolve().parents[2] / 'models'
        self.mean, self.std = np.load(root / 'elbow_v4_mean.npy'), np.load(root / 'elbow_v4_std.npy')
        self.data_dir, self.save_artifacts = Path(data_dir), save_artifacts
        self.rep_count = self.correct_reps = 0
        self.last_result = {}
        self.last_time = None
        self.size = None
        self._reset_tracking()

    def _reset_tracking(self):
        self.detector = FullRepDetector()
        self.samples = deque()
        self.calibration = deque()
        self.calibrated = False
        self.angle = None
        self.feedback = 'Keep your right shoulder, elbow and wrist visible. Hold your starting position for two seconds.'
        self.review_frame = self.review_landmarks = None
        self.review_excursion = -1.

    @staticmethod
    def _landmarks(pose):
        if pose is None:
            return None
        values = np.array([[lm.x, lm.y, lm.z, getattr(lm, 'visibility', 0.)] for lm in pose.landmark], dtype=np.float32)
        return values if values.shape == (33, 4) else None

    def _review_image(self, metrics):
        if self.review_frame is None:
            return None
        frame = annotate_review(self.review_frame, self.review_landmarks, 'Right', metrics, 'Movement flagged')
        if self.save_artifacts:
            target = self.data_dir / 'error_frames'
            target.mkdir(parents=True, exist_ok=True)
            name = 'elbow-v4-' + uuid4().hex + '.jpg'
            return name if cv2.imwrite(str(target / name), frame) else None
        ok, jpg = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 75])
        return 'data:image/jpeg;base64,' + base64.b64encode(jpg).decode('ascii') if ok else None

    def process_frame(self, frame, pose_landmarks, frame_number=0, timestamp_sec=None):
        t = float(timestamp_sec if timestamp_sec is not None else frame_number / self.fps)
        if not np.isfinite(t):
            self._reset_tracking()
            return None
        size = frame.shape[:2]
        gap = self.last_time is not None and (t <= self.last_time or t - self.last_time > .5)
        if gap or (self.size is not None and self.size != size):
            self._reset_tracking()
        dt = t - self.last_time if self.last_time is not None and t > self.last_time else 1. / self.fps
        self.last_time, self.size = t, size
        landmarks = self._landmarks(pose_landmarks)
        arm = landmarks[[12, 14, 16]] if landmarks is not None else None
        if arm is None or not np.isfinite(arm).all() or (arm[:, 3] < .55).any() or (arm[:, :2] < 0).any() or (arm[:, :2] > 1).any():
            self._reset_tracking()
            return None
        data = extract_angles(dict(zip(('shoulder', 'elbow', 'wrist'), arm[:, :2])))
        if min(np.linalg.norm(arm[0, :2] - arm[1, :2]), np.linalg.norm(arm[1, :2] - arm[2, :2])) < .01:
            self._reset_tracking()
            return None
        raw = data['elbow_angle']
        previous = self.angle
        # Time-aware equivalent of the author's EMA at 20 frames/second.
        alpha = 1. - (1. - .35) ** (dt * 20.)
        self.angle = float(raw if previous is None else alpha * raw + (1. - alpha) * previous)
        velocity = 0. if previous is None else (self.angle - previous) / (dt * 20.)
        row = [raw, data['shoulder_angle'], data['wrist_angle'], *data['elbow'],
               *data['wrist'], *data['shoulder'], data['arm_length']]
        self.samples.append((t, row))
        while self.samples and t - self.samples[0][0] > 17.:
            self.samples.popleft()
        if not self.calibrated:
            self.calibration.append((t, self.angle))
            while self.calibration and t - self.calibration[0][0] > 2.2:
                self.calibration.popleft()
            if np.ptp([a for _, a in self.calibration]) > 8.:
                self.calibration.clear()
                self.calibration.append((t, self.angle))
            if t - self.calibration[0][0] >= 2.:
                self.calibrated = True
                self.detector.reset(self.angle)
                self.samples.clear()
                self.feedback = 'Bend your right elbow, then return to your starting position.'
            return None
        before = self.detector.state
        event = self.detector.update(self.angle, velocity, t)
        if before == 'READY' and self.detector.state == 'MOVING':
            self.review_excursion = -1.
            self.review_frame = self.review_landmarks = None
        excursion = abs(self.angle - self.detector.baseline)
        if self.detector.state != 'READY' and excursion > self.review_excursion:
            self.review_excursion = excursion
            self.review_frame, self.review_landmarks = frame.copy(), landmarks.copy()
        self.feedback = ('Return smoothly to your starting position.' if self.detector.state == 'RETURNING'
                         else 'Bend smoothly, keeping your shoulder stable.')
        if event is None:
            return None
        start, end, baseline = event
        observed = [(tm, r) for tm, r in self.samples if start <= tm <= end]
        times = np.array([tm for tm, _ in observed])
        seq = np.array([r for _, r in observed], dtype=np.float32)
        if len(seq) < 5:
            self.feedback = 'Not enough visible movement to assess. Repeat the movement.'
            return None
        features = normalized_features(seq, self.mean, self.std)
        with torch.inference_mode():
            probability = float(torch.sigmoid(self.model(torch.from_numpy(features).to(self.device))).item())
        if not np.isfinite(probability):
            self.feedback = 'Movement could not be assessed. Repeat the movement.'
            return None
        decision = classify_movement(seq, probability, end - start)
        metrics = movement_metrics(seq[:, 0], times, baseline)
        self.rep_count += 1
        self.correct_reps += int(decision['form'] == 'Correct')
        self.feedback = ' '.join(decision['feedback_details'])
        result = {**metrics, **decision, 'rep_number': self.rep_count, 'duration': end - start,
                  'feedback': self.feedback, 'model_version': MODEL_VERSION,
                  'model_probability': probability, 'confidence': None,
                  'score_kind': 'model_and_geometry', 'hand': 'Right',
                  'rep_status': 'COMPLETED', 'status': 'COMPLETED',
                  'speed': f"{metrics.get('angular_speed', 0):.0f}°/s",
                  'error_type': '' if decision['form'] == 'Correct' else 'MODEL_FORM_REVIEW',
                  'clinically_validated': False,
                  'angle_trace': [{'seconds': round(float(tm-start), 3), 'angle': round(float(r[0]), 1)}
                                  for tm, r in observed[::max(1, len(observed)//60)]]}
        if decision['form'] != 'Correct':
            image = self._review_image(metrics)
            if image:
                result['error_frame_path'] = image
        self.last_result = result
        return result

    def get_live_state(self, pose_landmarks=None):
        landmarks = self._landmarks(pose_landmarks)
        stage = self.detector.state if self.calibrated else 'CALIBRATING'
        return {**self.last_result, 'exercise': 'Elbow Flexion and Extension',
                'rep_count': self.rep_count, 'correct_reps': self.correct_reps,
                'state': stage, 'angle': self.angle or 0., 'expected_hand': 'Right',
                'detected_mode': 'Right', 'feedback': self.feedback,
                'form': self.last_result.get('form', 'Waiting'),
                'range_of_motion': self.detector.max_rom if stage != 'READY' else self.last_result.get('range_of_motion', 0.),
                'model_version': MODEL_VERSION,
                'landmarks': [] if landmarks is None else [dict(zip(('x', 'y', 'z', 'visibility'), map(float, lm))) for lm in landmarks]}
