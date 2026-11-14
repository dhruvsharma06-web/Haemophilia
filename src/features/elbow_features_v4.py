"""Exact 22-feature contract from ai-elbow-model-v1, commit 0c37549.

The model was trained on normalized 2D right-arm coordinates. Do not substitute
pixel/world coordinates, reorder channels, or normalize before zero padding.
"""
import numpy as np

SEQUENCE_LENGTH = 30
INPUT_SIZE = 22


def calculate_angle(a, b, c):
    ba, bc = a - b, c - b
    cosine = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6)
    return np.degrees(np.arccos(np.clip(cosine, -1.0, 1.0)))


def extract_angles(row):
    shoulder, elbow, wrist = row['shoulder'], row['elbow'], row['wrist']
    return {
        'elbow_angle': calculate_angle(shoulder, elbow, wrist),
        'shoulder_angle': calculate_angle(elbow, shoulder, shoulder + np.array([0, -.1])),
        'wrist_angle': calculate_angle(elbow, wrist, wrist + np.array([.1, 0])),
        'elbow': elbow, 'wrist': wrist, 'shoulder': shoulder,
        'arm_length': np.linalg.norm(shoulder - wrist),
    }


def build_features(seq):
    seq = np.array(seq, dtype=np.float32)
    if len(seq) < 5:
        return None
    if seq.ndim != 2 or seq.shape[1] != 10 or not np.isfinite(seq).all():
        raise ValueError('Expected finite right-arm frames with 10 channels')
    elbow, shoulder, wrist, coords = seq[:, 0], seq[:, 1], seq[:, 2], seq[:, 3:]
    velocity = np.gradient(elbow)
    acceleration = np.gradient(velocity)
    velocity = velocity / (np.max(np.abs(velocity)) + 1e-6)
    acceleration = acceleration / (np.max(np.abs(acceleration)) + 1e-6)
    rom = np.ptp(elbow) + 1e-6
    smoothness, speed_std, peak = np.std(np.diff(elbow)), np.std(velocity), np.max(elbow)
    minimum = np.min(elbow)
    features = np.array([
        [elbow[i] / 180., velocity[i], acceleration[i], (elbow[i] - minimum) / rom,
         1. if velocity[i] > 0 else -1., 1. if abs(velocity[i]) < .05 else 0.,
         rom, smoothness, speed_std, peak, i / len(seq), (180 - peak) / 180.,
         minimum / 180., shoulder[i] / 180., wrist[i] / 180., *coords[i]]
        for i in range(len(seq))], dtype=np.float32)
    if len(features) < SEQUENCE_LENGTH:
        features = np.vstack([features, np.zeros((SEQUENCE_LENGTH - len(features), INPUT_SIZE), dtype=np.float32)])
    else:
        features = features[-SEQUENCE_LENGTH:]
    return features


def normalized_features(seq, mean, std):
    features = build_features(seq)
    if features is None:
        return None
    if np.shape(mean) != (1, 1, INPUT_SIZE) or np.shape(std) != (1, 1, INPUT_SIZE):
        raise ValueError('V4 normalization must have shape (1, 1, 22)')
    if not np.isfinite(mean).all() or not np.isfinite(std).all() or (std <= 0).any():
        raise ValueError('Invalid V4 normalization arrays')
    result = (features - mean) / std
    if not np.isfinite(result).all():
        raise ValueError('Non-finite normalized model input')
    return result.astype(np.float32)
