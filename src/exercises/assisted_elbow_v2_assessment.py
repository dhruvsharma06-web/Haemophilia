"""App adapter for the frozen assisted elbow V2 SVM and causal segmenter."""
import json
from pathlib import Path

import numpy as np

from src.feedback.elbow_v2_augmented import AugmentedCausalSegmenter
from src.models.assisted_elbow_v2 import extract_base_kinematic_channels


class AssistedElbowV2Assessment:
    uses_world_landmarks = True

    def __init__(self, model, device=None, fps=20.0, data_dir='data', save_artifacts=True):
        self.model = model
        self.fps = fps
        self.save_artifacts = save_artifacts
        config = json.loads((Path(__file__).resolve().parents[2] / 'models' /
                             'assisted_elbow_v2_segmentation.json').read_text())
        p = config['parameters']
        self.segmenters = {hand: AugmentedCausalSegmenter(
            hand=hand, pre_roll=p['pre_roll_frames'], post_roll=p['post_roll_frames'],
            min_rom=p['min_rom_deg'], onset_delta=p['onset_delta_deg'],
            reversal_delta=p['reversal_delta_deg'], min_frames=p['min_frames'],
            min_duration_sec=p['min_duration_sec']) for hand in ('Left', 'Right')}
        self.rep_count = 0
        self.last_result = {}
        self.telemetry = {}
        self.last_window = None
        self.last_time = None

    def process_frame(self, frame, pose_landmarks, frame_number=0,
                      world_landmarks=None, timestamp_sec=None):
        if world_landmarks is None:
            for segmenter in self.segmenters.values():
                segmenter.reset()
            self.telemetry = {'state': 'WAITING', 'active_angle': 0.0}
            return None
        t = timestamp_sec if timestamp_sec is not None else frame_number / self.fps
        if self.last_time is not None and (t <= self.last_time or t - self.last_time > 0.5):
            for segmenter in self.segmenters.values():
                segmenter.reset()
        self.last_time = t
        arr = np.asarray([[lm.x, lm.y, lm.z, getattr(lm, 'visibility', 1.0)]
                          for lm in world_landmarks.landmark], dtype=np.float64)
        if arr.shape != (33, 4) or not np.isfinite(arr).all():
            return None
        if np.min(arr[[11, 12, 13, 14, 15, 16, 23, 24], 3]) < 0.5:
            for segmenter in self.segmenters.values():
                segmenter.reset()
            self.telemetry = {'state': 'WAITING', 'active_angle': 0.0}
            return None
        candidates = []
        telemetry = []
        for hand, segmenter in self.segmenters.items():
            if len(segmenter.buffer) > max(60, int(self.fps * 30)):
                segmenter.reset()
            bundle, state = segmenter.process_frame(frame_number, t, arr)
            telemetry.append(state)
            if bundle is not None:
                landmarks, times, duration, count, start, end = bundle
                channels = extract_base_kinematic_channels(landmarks, hand)
                rom = float(np.nanmax(channels[:, 0]) - np.nanmin(channels[:, 0]))
                if duration < 1.5 and rom < 26.0:
                    continue
                candidates.append((rom, hand, bundle))
        self.telemetry = max(telemetry, key=lambda item: abs(item['velocity']))
        for _, hand, bundle in sorted(candidates, reverse=True, key=lambda x: x[0]):
            landmarks, times, duration, count, start, end = bundle
            # A bilateral movement is one repetition, even when both arm
            # segmenters finish on neighbouring frames.
            if self.last_window is not None:
                overlap = max(0, min(end, self.last_window[1]) - max(start, self.last_window[0]))
                if overlap > 0.5 * min(end - start, self.last_window[1] - self.last_window[0]):
                    continue
            result = self.model.predict(landmarks, times, hand, duration=duration)
            if result.qc_flags.get('errors') or not np.isfinite(result.raw_features).all():
                continue
            self.rep_count += 1
            self.last_window = (start, end)
            good = not result.is_incorrect
            feature = result.feature_dict
            feedback = ('Movement met the model form criteria.' if good else
                        'Review the demonstration and your prescribed technique before the next repetition.')
            self.last_result = {
                'rep_number': self.rep_count, 'form': result.predicted_label,
                'predicted_label': result.predicted_label.lower(),
                'score': None, 'confidence': None, 'decision_score': result.decision_score,
                'model_identity': 'Assisted_Elbow_Flexion_V2_BalancedSVM',
                'range_of_motion': feature['active_rom'], 'rom': feature['active_rom'],
                'duration': duration, 'feedback': feedback,
                'error_type': '' if good else 'MODEL_FORM_REVIEW',
                'speed': 'Recorded', 'smoothness': None, 'hand': hand,
                'rep_status': 'COMPLETED', 'status': 'COMPLETED',
            }
            return self.last_result
        return None

    def get_live_state(self, pose_landmarks=None):
        landmarks = [] if pose_landmarks is None else [
            dict(x=float(lm.x), y=float(lm.y), z=float(lm.z),
                 visibility=float(getattr(lm, 'visibility', 1.0)))
            for lm in pose_landmarks.landmark]
        return {
            'exercise': 'Assisted Elbow Flexion', 'rep_count': self.rep_count,
            'state': self.telemetry.get('state', 'WAITING'),
            'angle': self.telemetry.get('active_angle', 0.0),
            'form': self.last_result.get('form', 'Waiting'),
            'score': None, 'confidence': None,
            'range_of_motion': self.last_result.get('range_of_motion', 0.0),
            'feedback': self.last_result.get('feedback', 'Keep both arms and your torso visible.'),
            'error_type': self.last_result.get('error_type', ''),
            'speed': self.last_result.get('speed', 'Waiting'), 'smoothness': None,
            'detected_mode': self.telemetry.get('hand', 'Waiting'), 'landmarks': landmarks,
        }
