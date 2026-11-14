"""Live V3 feature contract from haemophilia-final a252160 realtime_test.py."""
import numpy as np

SEQUENCE_LENGTH = 25
INPUT_SIZE = 14

def build_live_features(angle_series):

    angles = np.array(angle_series, dtype=np.float32)

    velocity = np.gradient(angles)
    acceleration = np.gradient(velocity)

    velocity = velocity / (np.max(np.abs(velocity)) + 1e-6)
    acceleration = acceleration / (np.max(np.abs(acceleration)) + 1e-6)

    rom = np.max(angles) - np.min(angles) + 1e-6

    angle_norm = angles / 180.0
    completion = (angles - np.min(angles)) / rom

    smoothness = np.std(np.diff(angles)) if len(angles) > 1 else 0.0
    speed_std = np.std(velocity)
    peak = np.max(angles)

    pause = (np.abs(velocity) < 0.05).astype(float)

    extension_deficit = (180 - np.max(angles)) / 180.0
    flexion_deficit = (np.min(angles)) / 180.0

    features = []

    for i in range(len(angles)):
        t = i / len(angles)
        direction = 1.0 if velocity[i] > 0 else -1.0

        features.append([
            angle_norm[i],
            velocity[i],
            acceleration[i],
            completion[i],
            direction,
            pause[i],
            rom,
            smoothness,
            speed_std,
            peak,
            t,
            extension_deficit,
            flexion_deficit,
            0.0
        ])

    features = np.array(features, dtype=np.float32)

    if len(features) < SEQUENCE_LENGTH:
        pad = np.zeros((SEQUENCE_LENGTH - len(features), INPUT_SIZE), dtype=np.float32)
        features = np.vstack([features, pad])
    else:
        features = features[-SEQUENCE_LENGTH:]

    return features
