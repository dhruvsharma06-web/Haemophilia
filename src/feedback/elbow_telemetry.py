"""Descriptive image-plane movement metrics, independent of form classification.

The control index combines observed return completion and temporal smoothness.
It is an engineering display metric, not model confidence or a clinical score.
"""
import numpy as np


def movement_metrics(angles, times, baseline=None):
    angles, times = np.asarray(angles, float), np.asarray(times, float)
    valid = np.isfinite(angles) & np.isfinite(times)
    angles, times = angles[valid], times[valid]
    if len(times) < 3 or np.any(np.diff(times) <= 0):
        return {}
    duration = float(times[-1] - times[0])
    if duration <= 0:
        return {}
    # Uniform 20 Hz measurements make the index independent of socket frame rate.
    grid = np.arange(times[0], times[-1] + 1e-9, .05)
    sampled = np.interp(grid, times, angles)
    acceleration = np.diff(sampled, n=2)
    smoothness = float(100. / (1. + np.mean(np.abs(acceleration)))) if len(acceleration) else None
    start = float(angles[0] if baseline is None else baseline)
    peak = int(np.argmax(np.abs(angles - start)))
    excursion = abs(float(angles[peak]) - start)
    completion = float(np.clip(1. - abs(angles[-1] - start) / excursion, 0., 1.) * 100.) if excursion > 1e-6 else 0.
    control = float((completion + smoothness) / 2.) if smoothness is not None else None
    return {
        'angle': float(angles[-1]), 'minimum_angle': float(np.min(angles)),
        'maximum_angle': float(np.max(angles)), 'range_of_motion': float(np.ptp(angles)),
        'duration': duration, 'flexion_duration': float(times[peak] - times[0]),
        'return_duration': float(times[-1] - times[peak]),
        'angular_speed': float(np.sum(np.abs(np.diff(sampled))) / duration),
        'smoothness': smoothness, 'return_completion': completion,
        'score': control, 'movement_control_score': control,
        'score_kind': 'descriptive_movement_control',
        'score_components': ['temporal_smoothness_20hz', 'return_to_own_start'],
    }


def annotate_review(frame, image_landmarks, hand, metrics, verdict):
    import cv2
    result = frame.copy()
    height, width = result.shape[:2]
    joints = (11, 13, 15) if hand == 'Left' else (12, 14, 16)
    support = (12, 14, 16) if hand == 'Left' else (11, 13, 15)
    for side, color in ((joints, (0, 180, 255)), (support, (210, 200, 0))):
        points = []
        for idx in side:
            lm = image_landmarks[idx]
            if not np.isfinite(lm).all() or lm[3] < .5 or not (0 <= lm[0] <= 1 and 0 <= lm[1] <= 1):
                points.append(None)
                continue
            p = (round(lm[0] * width), round(lm[1] * height))
            points.append(p)
            cv2.circle(result, p, 5, color, -1)
        for a, b in zip(points, points[1:]):
            if a is not None and b is not None: cv2.line(result, a, b, color, 3)
    lines = [f'{hand} arm - {verdict}', 'Review frame; model suggestion',
             f"ROM {metrics.get('range_of_motion', 0):.0f} deg | {metrics.get('duration', 0):.1f} s"]
    cv2.rectangle(result, (0, 0), (min(width, 470), 92), (30, 30, 30), -1)
    for index, line in enumerate(lines):
        cv2.putText(result, line, (10, 23 + index * 27), cv2.FONT_HERSHEY_SIMPLEX, .5, (255,255,255), 1)
    return result
