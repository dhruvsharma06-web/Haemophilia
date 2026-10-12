"""CSV adapter for the same bilateral state machine used in live inference.

For LSTM training use scripts/shoulder_rotation_pipeline.py extract, which samples
video at 20 Hz and creates reviewable 128-by-10 sequences.
"""
import sys
from pathlib import Path
import numpy as np
import pandas as pd

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BASE_DIR))
from src.exercises.shoulder_rotation import FEATURE_NAMES, REP_DIR
from src.exercises.shoulder_rotation_assessment import ShoulderRotationAssessment


class Collector(ShoulderRotationAssessment):
    def _classify_rep(self, features):
        # Segmentation cannot supply a learned form judgment.
        return 0, .5, np.array([.5, .5])


def process_reps(feature_file: Path, label: str, subject_id: str):
    df = pd.read_csv(feature_file)
    columns = FEATURE_NAMES + ["right_hand_displacement", "left_hand_displacement",
                               "right_upper_arm_offset", "left_upper_arm_offset"]
    if not set(columns).issubset(df.columns):
        raise ValueError("Re-extract shoulder rotation features; old CSVs lack bilateral hand measurements.")
    engine = Collector(None, "cpu", fps=20, save_artifacts=False)
    reps = []
    for _, row in df.iterrows():
        feature = row[columns].to_numpy(dtype=np.float32)
        if not np.isfinite(feature).all():
            engine.reset_incomplete_rep()
            continue
        engine._extract_feature = lambda landmarks, feature=feature: feature.copy()
        result = engine.process_frame(None, object(), timestamp_ms=float(row["time_sec"]) * 1000)
        if result:
            reps.append({"rep": len(reps) + 1, "label": label, "subject_id": subject_id,
                         "start_frame": result["rep_start_frame"], "end_frame": result["rep_end_frame"],
                         "frame_basis": "resampled_20hz", "rep_definition": result["rep_definition"],
                         **{key: result[key] for key in ["right_rom", "left_rom", "range_of_motion",
                                                        "duration", "speed_deg_per_sec", "smoothness"]}})
    REP_DIR.mkdir(parents=True, exist_ok=True)
    output = REP_DIR / f"{Path(feature_file).stem.replace('_features', '')}_reps.csv"
    pd.DataFrame(reps, columns=["rep", "label", "subject_id", "start_frame", "end_frame", "frame_basis",
                               "rep_definition", "right_rom", "left_rom", "range_of_motion", "duration",
                               "speed_deg_per_sec", "smoothness"]).to_csv(output, index=False)
    return output


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("Usage: python src/feedback/shoulder_rotation_rep_counter.py <features.csv> <correct|incorrect> <subject_id>")
    process_reps(Path(sys.argv[1]), sys.argv[2], sys.argv[3])
