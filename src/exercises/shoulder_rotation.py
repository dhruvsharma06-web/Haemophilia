"""Shoulder internal/external rotation configuration.

Prototype movement: bilateral shoulder internal/external rotation with elbows flexed
approximately 90 degrees and upper arms kept near the torso. Thresholds below are
engineering/tunable thresholds, not clinical cut-offs.
"""
from pathlib import Path

EXERCISE_NAME = "shoulder_rotation"
SEQUENCE_LENGTH = 128
INPUT_SIZE = 10

# Feature order MUST remain identical in training and inference.
FEATURE_NAMES = [
    "right_rotation_angle",
    "left_rotation_angle",
    "right_angular_velocity",
    "left_angular_velocity",
    "right_elbow_angle",
    "left_elbow_angle",
    "right_visibility",
    "left_visibility",
    "torso_tilt",
    "torso_rotation",
]

# Normalization constants.
ANGLE_SCALE = 180.0
ANGULAR_VELOCITY_SCALE = 360.0  # deg/s engineering scale; not a clinical threshold
TORSO_TILT_SCALE = 90.0

# Rep detector settings. These are signal-processing defaults, not clinical ROM rules.
SMOOTHING_WINDOW = 9
MIN_REP_DURATION = 0.50
MIN_REP_FRAMES = 15
MIN_ROTATION_EXCURSION_DEG = 15.0
RETURN_FRACTION = 0.35

# Prototype form-error thresholds. Keep tunable until validated by a physiotherapist.
MAX_TORSO_TILT_DEG = 12.0
MAX_TORSO_ROTATION_RATIO = 0.30
MAX_ELBOW_DRIFT_TORSO = 0.22
MAX_LEFT_RIGHT_ROM_DIFF_DEG = 25.0

BASE_DIR = Path(__file__).resolve().parents[2]
DATASET_DIR = BASE_DIR / "dataset" / EXERCISE_NAME
PROCESSED_DIR = BASE_DIR / "processed_data" / EXERCISE_NAME
KEYPOINT_DIR = PROCESSED_DIR / "keypoints"
FEATURE_DIR = PROCESSED_DIR / "features"
REP_DIR = PROCESSED_DIR / "reps"
SEQUENCE_DIR = PROCESSED_DIR / "sequences"
MODEL_PATH = BASE_DIR / "models" / "shoulder_rotation_lstm.pth"
MANIFEST_PATH = DATASET_DIR / "subjects.csv"
