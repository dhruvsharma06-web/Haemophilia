"""Create prioritized review queue for Assisted Elbow Flexion.

Prioritization Scheme:
- Priority 1: auto_label != folder_label OR auto_label == 'Ambiguous'
- Priority 2: auto_confidence == 'low' (and not in P1)
- Priority 3: auto_confidence == 'medium' (and not in P1, P2)
- Priority 4: auto_confidence == 'high' (and not in P1, P2, P3)

Within each priority, maintains stable subject/video/repetition ordering.
Outputs:
- processed_data/assisted_elbow_flexion/manual_review_queue.csv
"""

import sys
from pathlib import Path
import pandas as pd

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.append(str(BASE_DIR))

ANNOTATIONS_FILE = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "repetition_annotations.csv"
QUEUE_FILE = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "manual_review_queue.csv"


def build_review_queue(annotations_path: Path = ANNOTATIONS_FILE, queue_path: Path = QUEUE_FILE):
    if not annotations_path.exists():
        raise FileNotFoundError(f"Annotations file not found: {annotations_path}")

    df = pd.read_csv(annotations_path)

    def assign_priority(row):
        f_lbl = str(row["folder_label"]).strip().lower()
        a_lbl = str(row["auto_label"]).strip().lower()
        conf = str(row["auto_confidence"]).strip().lower()

        # Priority 1: Disagreement or Ambiguity
        if a_lbl != f_lbl or a_lbl == "ambiguous":
            return 1
        # Priority 2: Low confidence
        elif conf == "low":
            return 2
        # Priority 3: Medium confidence
        elif conf == "medium":
            return 3
        # Priority 4: High confidence agreement
        else:
            return 4

    df["review_priority"] = df.apply(assign_priority, axis=1)

    # Sort stably by priority, then subject, video, rep index
    sorted_df = df.sort_values(
        by=["review_priority", "subject_id", "video_name", "repetition_index"],
        ascending=[True, True, True, True],
    ).reset_index(drop=True)

    columns = [
        "review_priority",
        "subject_id",
        "video_name",
        "repetition_index",
        "assistance_type",
        "folder_label",
        "auto_label",
        "auto_confidence",
        "auto_error_tags",
        "auto_reason",
        "start_frame",
        "end_frame",
        "duration_sec",
        "rom",
        "min_elbow_angle",
        "max_elbow_angle",
        "elbow_flare",
        "torso_tilt",
        "torso_rotation",
        "smoothness",
        "sequence_file",
    ]

    queue_df = sorted_df[columns]
    queue_df.to_csv(queue_path, index=False)

    p_counts = queue_df["review_priority"].value_counts().to_dict()
    print("=" * 60)
    print("MANUAL REVIEW QUEUE CREATED")
    print("=" * 60)
    print(f"Destination: {queue_path}")
    print(f"Total Repetitions in Queue: {len(queue_df)}")
    print(f"Priority 1 (Disagreements & Ambiguous) : {p_counts.get(1, 0)}")
    print(f"Priority 2 (Low Confidence)           : {p_counts.get(2, 0)}")
    print(f"Priority 3 (Medium Confidence)        : {p_counts.get(3, 0)}")
    print(f"Priority 4 (High Confidence Agreement): {p_counts.get(4, 0)}")
    print("=" * 60)

    return queue_df


if __name__ == "__main__":
    build_review_queue()
