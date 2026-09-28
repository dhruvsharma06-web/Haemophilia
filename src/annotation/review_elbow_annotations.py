"""Human Repetition-Level Annotation Review Tool for Assisted Elbow Flexion.

Allows reviewers to inspect each segmented repetition, view kinematic metrics,
play back the exact repetition video segment, and assign verified repetition-level ground truth:
  1 = Correct
  2 = Incorrect (with specific error tags)
  3 = Ambiguous / Exclude (with mandatory written reason)
  s = Skip
  q = Save and Quit

Manual human review is based strictly on the project's documented Assisted Elbow Flexion movement criteria.
Reviewers are not designated as clinicians unless an actual clinical professional performs the review.
Preserves original folder_label to audit label discordance without overwriting.
"""

import argparse
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np
import pandas as pd

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.append(str(BASE_DIR))

DEFAULT_ANNOTATION_FILE = (
    BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "repetition_annotations.csv"
)
DEFAULT_DATASET_ROOT = Path(r"C:\Users\DEVESH SHUKLA\Downloads\hemo\Assisted elbow flexion")
CLIPS_DIR = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "clips"
SEQUENCE_DIR = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "sequences"
MANUAL_QUEUE_FILE = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "manual_review_queue.csv"
MANUAL_AUDIT_FILE = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "manual_annotation_audit.csv"

VALID_ERROR_TAGS = [
    "insufficient_flexion",
    "incomplete_extension",
    "excessive_elbow_flare",
    "poor_control",
    "excessive_torso_compensation",
    "other",
]


def find_video_file(video_name: str, search_root: Path = DEFAULT_DATASET_ROOT) -> Optional[Path]:
    """Search for raw video file across dataset subfolders."""
    if not search_root.exists():
        return None
    for root, _, files in os.walk(search_root):
        if video_name in files:
            return Path(root) / video_name
    return None


def generate_repetition_clip(
    source_video_path: Path,
    start_frame: int,
    end_frame: int,
    output_clip_path: Path,
    target_width: int = 720,
    fps: float = 30.0,
) -> bool:
    """Extract and encode a downscaled video clip corresponding to the repetition window."""
    if output_clip_path.exists() and output_clip_path.stat().st_size > 1024:
        return True

    os.makedirs(output_clip_path.parent, exist_ok=True)
    cap = cv2.VideoCapture(str(source_video_path))
    if not cap.isOpened():
        return False

    cap.set(cv2.CAP_PROP_POS_FRAMES, max(0, start_frame))
    src_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    if w <= 0 or h <= 0:
        cap.release()
        return False

    target_height = int(h * (target_width / w))
    # Ensure even dimensions for video codecs
    target_height = target_height if target_height % 2 == 0 else target_height + 1
    target_width = target_width if target_width % 2 == 0 else target_width + 1

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(str(output_clip_path), fourcc, fps, (target_width, target_height))

    # Calculate step if source video is 60fps and target is 30fps
    step = 2 if src_fps >= 50.0 else 1

    curr = max(0, start_frame)
    while curr <= end_frame:
        ret, frame = cap.read()
        if not ret:
            break
        if (curr - start_frame) % step == 0:
            small_frame = cv2.resize(frame, (target_width, target_height))
            out.write(small_frame)
        curr += 1

    cap.release()
    out.release()
    return output_clip_path.exists() and output_clip_path.stat().st_size > 1024


def play_clip_in_player(clip_path: Path):
    """Open the clip in the system default video player (non-blocking)."""
    if not clip_path.exists():
        print(f"[Warning] Clip file not found: {clip_path}")
        return
    try:
        if os.name == "nt":
            os.startfile(str(clip_path))
        elif sys.platform == "darwin":
            subprocess.Popen(["open", str(clip_path)])
        else:
            subprocess.Popen(["xdg-open", str(clip_path)])
        print(f"-> Playing clip in system media player: {clip_path.name}")
    except Exception as e:
        print(f"[Error opening media player]: {e}")


def play_clip_opencv(clip_path: Path):
    """Play the clip in a looping OpenCV window with pause/resume support."""
    if not clip_path.exists():
        print(f"[Warning] Clip file not found: {clip_path}")
        return

    print("-> Playing clip in OpenCV window (SPACE to pause/resume, 'r' to replay, 'q'/ESC to close)...")
    cap = cv2.VideoCapture(str(clip_path))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    delay = int(1000 / max(fps, 1.0))

    paused = False
    window_name = f"Repetition Playback: {clip_path.stem}"
    cv2.namedWindow(window_name, cv2.WINDOW_AUTOSIZE)

    while True:
        if not paused:
            ret, frame = cap.read()
            if not ret:
                # Loop back to beginning
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                continue
            cv2.imshow(window_name, frame)

        key = cv2.waitKey(delay if not paused else 50) & 0xFF
        if key in (27, ord("q")):  # ESC or q
            break
        elif key == ord(" "):  # SPACE
            paused = not paused
        elif key == ord("r"):  # Replay
            cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            paused = False

    cap.release()
    cv2.destroyWindow(window_name)


def print_stats(df: pd.DataFrame):
    """Print complete annotation progress, breakdown, agreement, and error tag distribution."""
    total = len(df)
    gt_series = df["ground_truth_label"].fillna("").astype(str).str.strip().str.lower()
    reviewed_mask = gt_series != ""

    reviewed = df[reviewed_mask]
    unreviewed = df[~reviewed_mask]

    n_correct = (gt_series == "correct").sum()
    n_incorrect = (gt_series == "incorrect").sum()
    n_ambiguous = (gt_series == "ambiguous").sum()

    print("\n" + "=" * 70)
    print("ASSISTED ELBOW FLEXION: REPETITION ANNOTATION AUDIT")
    print("=" * 70)
    print(f"Total accepted repetitions     : {total}")
    print(f"Human-annotated repetitions    : {len(reviewed)} ({len(reviewed)/total*100:.1f}%)" if total else 0)
    print(f"Unannotated repetitions        : {len(unreviewed)} ({len(unreviewed)/total*100:.1f}%)" if total else 0)
    print("-" * 70)
    print(f"  [1] Correct                  : {n_correct:3d} ({n_correct/total*100:.1f}%)" if total else 0)
    print(f"  [2] Incorrect                : {n_incorrect:3d} ({n_incorrect/total*100:.1f}%)" if total else 0)
    print(f"  [3] Ambiguous / Exclude      : {n_ambiguous:3d} ({n_ambiguous/total*100:.1f}%)" if total else 0)
    print("-" * 70)

    # Provisional Auto Labels Summary
    if "auto_label" in df.columns and df["auto_label"].notna().any():
        a_series = df["auto_label"].fillna("").astype(str).str.strip()
        print("Provisional First-Pass Automatic Evaluation:")
        print(f"  Auto Correct                 : {(a_series == 'Correct').sum():3d} ({(a_series == 'Correct').sum()/total*100:.1f}%)")
        print(f"  Auto Incorrect               : {(a_series == 'Incorrect').sum():3d} ({(a_series == 'Incorrect').sum()/total*100:.1f}%)")
        print(f"  Auto Ambiguous               : {(a_series == 'Ambiguous').sum():3d} ({(a_series == 'Ambiguous').sum()/total*100:.1f}%)")
        print("-" * 70)

    # Agreement with original folder label (evaluated on non-ambiguous human annotations)
    valid_eval = df[gt_series.isin(["correct", "incorrect"])].copy()
    if len(valid_eval) > 0:
        f_series = valid_eval["folder_label"].fillna("").astype(str).str.strip().str.lower()
        standard_mask = f_series.isin(["correct", "incorrect"])
        eval_std = valid_eval[standard_mask]
        if len(eval_std) > 0:
            std_f = eval_std["folder_label"].str.lower().str.strip()
            std_g = eval_std["ground_truth_label"].str.lower().str.strip()
            agreed = (std_f == std_g).sum()
            disagreed = len(eval_std) - agreed
            print("Folder Label vs. Human Ground Truth Agreement:")
            print(f"  Evaluated repetitions       : {len(eval_std)}")
            print(f"  Agreed with folder label    : {agreed} ({agreed/len(eval_std)*100:.1f}%)")
            print(f"  Disagreed with folder label : {disagreed} ({disagreed/len(eval_std)*100:.1f}%)")
            print("-" * 70)

    # Error tags distribution (Human)
    print("Error Tag Frequency (Human Verified Incorrect):")
    all_tags = []
    for tags_val in reviewed["error_tags"].dropna():
        for t in str(tags_val).split(";"):
            t_clean = t.strip()
            if t_clean:
                all_tags.append(t_clean)
    if all_tags:
        tag_counts = pd.Series(all_tags).value_counts()
        for t_name, count in tag_counts.items():
            print(f"  - {t_name:30s}: {count:3d} ({count/len(reviewed)*100:.1f}%)")
    else:
        print("  (No human error tags recorded yet)")

    # Error tags distribution (Auto Provisional)
    if "auto_error_tags" in df.columns:
        auto_tags_list = []
        for tags_val in df[df["auto_label"] == "Incorrect"]["auto_error_tags"].dropna():
            for t in str(tags_val).split(";"):
                t_clean = t.strip()
                if t_clean:
                    auto_tags_list.append(t_clean)
        if auto_tags_list:
            print("\nError Tag Frequency (Provisional Auto Incorrect):")
            for t_name, count in pd.Series(auto_tags_list).value_counts().items():
                print(f"  - {t_name:30s}: {count:3d}")
    print("=" * 70 + "\n")


def export_clean_dataset(df: pd.DataFrame, output_path: Path):
    """Export only verified Correct and Incorrect repetitions for supervised ML training.
    
    Excludes blank labels and Ambiguous/Exclude.
    """
    gt_series = df["ground_truth_label"].fillna("").astype(str).str.strip().str.lower()
    clean_mask = gt_series.isin(["correct", "incorrect"])
    clean_df = df[clean_mask].copy()

    if len(clean_df) == 0:
        print("\n[ERROR] Cannot export clean dataset: 0 verified 'correct' or 'incorrect' annotations found.")
        print("Please annotate repetitions before exporting.\n")
        return

    # Add numeric target: 0 = correct, 1 = incorrect
    clean_df["numeric_label"] = (clean_df["ground_truth_label"].str.lower() == "incorrect").astype(int)

    os.makedirs(output_path.parent, exist_ok=True)
    clean_df.to_csv(output_path, index=False)

    print("\n" + "=" * 65)
    print("CLEAN SUPERVISED DATASET EXPORTED SUCCESSFULLY")
    print("=" * 65)
    print(f"Export target path        : {output_path}")
    print(f"Total exported repetitions: {len(clean_df)}")
    print(f"  Correct repetitions     : {(clean_df['numeric_label'] == 0).sum()}")
    print(f"  Incorrect repetitions   : {(clean_df['numeric_label'] == 1).sum()}")
    print(f"Excluded unannotated      : {(gt_series == '').sum()}")
    print(f"Excluded ambiguous        : {(gt_series == 'ambiguous').sum()}")
    print("=" * 65 + "\n")


def add_mix_videos_infrastructure(annotation_path: Path):
    """Segment and append the 4 excluded 'Both hand assisted mix' videos to the annotation file.
    
    These videos enter with folder_label='mix' and blank ground_truth_label.
    They will only enter clean training data after human review.
    """
    from src.features.assisted_elbow_features import (
        FEATURE_NAMES,
        build_normalized_sequence,
        extract_frame_kinematics,
        map_canonical_features,
    )
    from src.feedback.assisted_elbow_rep_counter import AssistedElbowRepCounter
    import mediapipe as mp

    df = pd.read_csv(annotation_path)
    existing_videos = set(df["video_name"].unique())

    mix_folder = DEFAULT_DATASET_ROOT / "Both hand assisted mix"
    if not mix_folder.exists():
        print(f"[Warning] Mix videos folder not found: {mix_folder}")
        return

    mix_files = sorted([f for f in os.listdir(mix_folder) if f.endswith(".mp4")])
    to_process = [f for f in mix_files if f not in existing_videos]

    if not to_process:
        print("[Info] All mix videos are already present in the annotation queue.")
        return

    print(f"\nAdding {len(to_process)} mix videos to annotation queue: {to_process}")
    mp_pose = mp.solutions.pose
    pose = mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )

    new_rows = []
    for vid_name in to_process:
        vid_path = mix_folder / vid_name
        stem = vid_path.stem
        # Determine subject
        if stem.startswith("20260825_12"):
            sub_id = "person1"
        elif stem.startswith("20260825_13") or stem.startswith("20260825_14"):
            sub_id = "person2"
        elif stem.startswith("VID"):
            sub_id = "person3"
        else:
            sub_id = "unknown"

        cap = cv2.VideoCapture(str(vid_path))
        src_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        step = 2 if src_fps >= 50.0 else 1
        eff_fps = src_fps / step

        raw_landmarks = []
        frame_indices = []
        f_idx = 0
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            if f_idx % step == 0:
                h, w = frame.shape[:2]
                small = cv2.resize(frame, (960, int(h * (960 / w))))
                rgb = cv2.cvtColor(small, cv2.COLOR_BGR2RGB)
                res = pose.process(rgb)
                raw_landmarks.append(res.pose_landmarks if res.pose_landmarks else None)
                frame_indices.append(f_idx)
            f_idx += 1
        cap.release()

        # Shoulder width
        valid_sws = []
        for lm_obj in raw_landmarks:
            if lm_obj:
                ls, rs = lm_obj.landmark[11], lm_obj.landmark[12]
                if min(ls.visibility, rs.visibility) > 0.5:
                    sw = float(np.sqrt((rs.x - ls.x) ** 2 + (rs.y - ls.y) ** 2))
                    if sw > 0.05:
                        valid_sws.append(sw)
        ref_sw = float(np.median(valid_sws)) if valid_sws else 0.12

        # Kinematics
        frame_k = []
        for lm_obj in raw_landmarks:
            if lm_obj:
                raw_k = extract_frame_kinematics(lm_obj, ref_shoulder_width=ref_sw)
            else:
                raw_k = {"left_angle": np.nan, "right_angle": np.nan, "left_vis": 0.0, "right_vis": 0.0, "torso_tilt": 0.0, "torso_rotation": 0.0, "left_flare": 0.0, "right_flare": 0.0, "instantaneous_sw": 0.0, "fallback_used": 1.0}
            frame_k.append(map_canonical_features(raw_k, "both_hand_assisted"))

        angles = np.array([k["active_elbow_angle"] for k in frame_k], dtype=np.float32)
        vis = np.array([k["active_arm_visibility"] for k in frame_k], dtype=np.float32)
        clean_angles = pd.Series(angles).interpolate().bfill().ffill().values

        counter = AssistedElbowRepCounter(fps=eff_fps)
        acc, _ = counter.segment_series(clean_angles, vis)
        print(f"  {vid_name} ({sub_id}): Segmented {len(acc)} accepted repetitions")

        for rep_idx, rep in enumerate(acc):
            start_f = rep["start_frame"]
            end_f = rep["end_frame"]
            rep_records = frame_k[start_f : end_f + 1]

            seq_mat = build_normalized_sequence(rep_records, target_length=128)
            seq_fn = f"{stem}_rep_{rep_idx + 1:02d}_mix_{sub_id}.npy"
            np.save(SEQUENCE_DIR / seq_fn, seq_mat)

            rep_angles = np.array([k["active_elbow_angle"] for k in rep_records])
            first_d = np.diff(rep_angles)
            sec_d = np.diff(first_d)
            smoothness = float(1.0 / (1.0 + np.mean(np.abs(sec_d)))) if len(rep_angles) >= 3 else 0.0

            new_rows.append({
                "subject_id": sub_id,
                "video_name": vid_name,
                "repetition_index": rep_idx + 1,
                "assistance_type": "both_hand_assisted",
                "folder_label": "mix",
                "ground_truth_label": None,
                "error_tags": None,
                "annotator": None,
                "timestamp": None,
                "notes": None,
                "start_frame": frame_indices[start_f],
                "end_frame": frame_indices[end_f],
                "duration_sec": round(float(rep["duration"]), 2),
                "rom": round(float(rep["rom"]), 1),
                "min_elbow_angle": round(float(rep["peak_angle"]), 1),
                "max_elbow_angle": round(float(max(rep["start_angle"], rep["end_angle"])), 1),
                "elbow_flare": round(float(np.max([k["active_elbow_flare"] for k in rep_records])), 3),
                "torso_tilt": round(float(np.max([k["torso_tilt"] for k in rep_records])), 1),
                "torso_rotation": round(float(np.max([abs(k["torso_rotation"]) for k in rep_records])), 1),
                "smoothness": round(smoothness, 3),
                "sequence_file": seq_fn,
            })

    pose.close()
    if new_rows:
        combined = pd.concat([df, pd.DataFrame(new_rows)], ignore_index=True)
        combined.to_csv(annotation_path, index=False)
        print(f"Successfully added {len(new_rows)} repetitions from mix videos to {annotation_path}")
        print(f"New total repetitions in annotation file: {len(combined)}")


def generate_manual_annotation_audit(
    df: pd.DataFrame,
    audit_path: Path = MANUAL_AUDIT_FILE,
):
    """Generate second-pass audit comparing automatic labels and folder labels against human ground truth."""
    gt = df["ground_truth_label"].fillna("").astype(str).str.strip()
    reviewed_df = df[gt != ""].copy()
    if len(reviewed_df) == 0:
        print("[Info] No human annotations recorded yet. Manual annotation audit will be generated once repetitions are reviewed.")
        return

    audit_rows = []
    for _, r in reviewed_df.iterrows():
        a = str(r.get("auto_label", "")).strip().lower()
        h = str(r["ground_truth_label"]).strip().lower()
        f = str(r["folder_label"]).strip().lower()

        audit_rows.append({
            "automatic_label": r.get("auto_label", ""),
            "final_human_label": r["ground_truth_label"],
            "folder_label": r["folder_label"],
            "whether_auto_was_correct": (a == h),
            "whether_folder_was_correct": (f == h),
            "auto_confidence": r.get("auto_confidence", ""),
            "error_tags": r.get("error_tags", ""),
            "reviewer": r.get("annotator", ""),
            "timestamp": r.get("timestamp", ""),
            "notes": r.get("notes", ""),
        })

    audit_df = pd.DataFrame(audit_rows)
    audit_df.to_csv(audit_path, index=False)
    print(f"Generated manual annotation audit report: {audit_path} ({len(audit_df)} records)")


def print_session_summary(df: pd.DataFrame):
    """Print the exact required review summary after an annotation session."""
    total = len(df)
    gt = df["ground_truth_label"].fillna("").astype(str).str.strip()
    reviewed_mask = gt != ""
    reviewed_count = int(reviewed_mask.sum())
    remaining_count = int(total - reviewed_count)

    n_corr = int((gt.str.lower() == "correct").sum())
    n_inc = int((gt.str.lower() == "incorrect").sum())
    n_amb = int((gt.str.lower() == "ambiguous").sum())

    print("\n" + "=" * 65)
    print("REVIEW SUMMARY")
    print("=" * 65)
    print(f"Reviewed: {reviewed_count}")
    print(f"Remaining: {remaining_count}")
    print(f"Final Correct: {n_corr}")
    print(f"Final Incorrect: {n_inc}")
    print(f"Final Ambiguous: {n_amb}")
    print()

    if reviewed_count > 0:
        rev_df = df[reviewed_mask]
        auto_lbls = rev_df["auto_label"].fillna("").astype(str).str.strip().str.lower()
        human_lbls = rev_df["ground_truth_label"].fillna("").astype(str).str.strip().str.lower()
        auto_agreed = int((auto_lbls == human_lbls).sum())
        auto_changed = int(reviewed_count - auto_agreed)
        print(f"Auto agreed with human: {auto_agreed} ({auto_agreed/reviewed_count*100:.1f}%)")
        print(f"Auto changed by human: {auto_changed} ({auto_changed/reviewed_count*100:.1f}%)")

        folder_lbls = rev_df["folder_label"].fillna("").astype(str).str.strip().str.lower()
        std_mask = folder_lbls.isin(["correct", "incorrect"])
        if std_mask.sum() > 0:
            std_f = folder_lbls[std_mask]
            std_h = human_lbls[std_mask]
            f_agreed = int((std_f == std_h).sum())
            f_changed = int(len(std_f) - f_agreed)
            print(f"Folder label agreed with human: {f_agreed} ({f_agreed/len(std_f)*100:.1f}%)")
            print(f"Folder label changed by human: {f_changed} ({f_changed/len(std_f)*100:.1f}%)")
        else:
            print("Folder label agreed with human: 0")
            print("Folder label changed by human: 0")
    else:
        print("Auto agreed with human: 0")
        print("Auto changed by human: 0")
        print("Folder label agreed with human: 0")
        print("Folder label changed by human: 0")
    print("=" * 65 + "\n")


def run_interactive_review(
    df: pd.DataFrame,
    annotation_path: Path,
    annotator_name: str,
    subject_filter: Optional[str] = None,
    video_filter: Optional[str] = None,
    auto_play: bool = False,
    review_auto: bool = False,
):
    """Run interactive CLI review session with video playback and exact required options."""
    if review_auto:
        # Load or generate prioritized queue order
        from src.annotation.create_review_queue import build_review_queue
        if not MANUAL_QUEUE_FILE.exists():
            build_review_queue(annotations_path=annotation_path, queue_path=MANUAL_QUEUE_FILE)

        queue_df = pd.read_csv(MANUAL_QUEUE_FILE)
        # Create ordered list of (video_name, repetition_index)
        ordered_keys = list(zip(queue_df["video_name"], queue_df["repetition_index"]))

        # Build index mapping from df
        df_key_to_idx = {
            (row["video_name"], row["repetition_index"]): idx
            for idx, row in df.iterrows()
        }

        # Filter indices by key order
        indices = [df_key_to_idx[k] for k in ordered_keys if k in df_key_to_idx]
        if subject_filter:
            indices = [i for i in indices if df.loc[i, "subject_id"] == subject_filter]
        if video_filter:
            indices = [i for i in indices if video_filter in str(df.loc[i, "video_name"])]
    else:
        mask = pd.Series([True] * len(df))
        if subject_filter:
            mask &= df["subject_id"] == subject_filter
        if video_filter:
            mask &= df["video_name"].str.contains(video_filter)
        indices = df[mask].index.tolist()

    print("\n" + "=" * 70)
    print("ASSISTED ELBOW FLEXION REPETITION ANNOTATION SESSION")
    if review_auto:
        print("Mode: Reviewing & Verifying Prioritized Queue (Priority 1 -> 4)")
    print("=" * 70)
    print("Manual human review based on documented movement quality criteria.")
    print(f"Reviewer / Annotator: {annotator_name}")
    print(f"Matching repetitions: {len(indices)}")
    print("Controls:")
    print("  1 = Correct")
    print("  2 = Incorrect")
    print("  3 = Ambiguous / Exclude")
    print("  v = View Clip")
    print("  s = Skip")
    print("  q = Save & Quit")
    print("=" * 70 + "\n")

    dirty = False

    for count, idx in enumerate(indices):
        row = df.loc[idx]
        current_decision = row.get("ground_truth_label", None)
        has_decision = pd.notna(current_decision) and str(current_decision).strip() != ""

        status_tag = f" [HUMAN VERIFIED: {current_decision}]" if has_decision else ""

        # Locate source video
        vid_file = find_video_file(row["video_name"])
        clip_name = f"{Path(row['video_name']).stem}_rep_{int(row['repetition_index']):02d}.mp4"
        clip_path = CLIPS_DIR / clip_name

        auto_lbl = row.get("auto_label", "N/A")
        auto_conf = row.get("auto_confidence", "N/A")
        auto_rsn = row.get("auto_reason", "N/A")
        auto_tags_val = row.get("auto_error_tags", None)
        auto_tags_str = str(auto_tags_val) if pd.notna(auto_tags_val) and auto_tags_val else "None"

        print("-" * 70)
        print(f"Subject: {row['subject_id']}")
        print(f"Video: {row['video_name']}")
        print(f"Repetition: #{int(row['repetition_index'])} ({count + 1} of {len(indices)}){status_tag}")
        print(f"Assistance: {row['assistance_type']}")
        print()
        print(f"Folder label: {row['folder_label']}")
        print(f"Automatic label: {auto_lbl}")
        print(f"Automatic confidence: {auto_conf}")
        print(f"Automatic reason: {auto_rsn}")
        print()
        print(f"ROM: {row['rom']}°")
        print(f"Minimum elbow angle: {row['min_elbow_angle']}°")
        print(f"Maximum elbow angle: {row['max_elbow_angle']}°")
        print(f"Elbow flare: {row['elbow_flare']}")
        print(f"Duration: {row['duration_sec']}s")
        print(f"Torso tilt: {row['torso_tilt']}°")
        print(f"Torso rotation: {row['torso_rotation']}°")
        print(f"Smoothness: {row['smoothness']}")

        if has_decision:
            print()
            print(f"Existing Human Decision: {current_decision} (Tags: {row['error_tags']}, By: {row['annotator']}, At: {row['timestamp']})")
            if pd.notna(row['notes']) and row['notes']:
                print(f"Existing Notes: {row['notes']}")

        # Ensure video clip is available or generated
        clip_ready = False
        if vid_file and vid_file.exists():
            if not clip_path.exists():
                print("  [Extracting repetition video clip...]", end="", flush=True)
                ok = generate_repetition_clip(vid_file, int(row["start_frame"]), int(row["end_frame"]), clip_path)
                print(" Ready." if ok else " Failed.")
                clip_ready = ok
            else:
                clip_ready = True

        if clip_ready and auto_play:
            play_clip_in_player(clip_path)

        while True:
            prompt = "\nDecision [1 = Correct, 2 = Incorrect, 3 = Ambiguous / Exclude, v = View Clip, s = Skip, q = Save & Quit]: "
            choice = input(prompt).strip().lower()

            if choice in ("q", "quit", "save & quit"):
                if dirty:
                    df.to_csv(annotation_path, index=False)
                    print(f"\n[Saved progress to {annotation_path}]")
                    generate_manual_annotation_audit(df)
                print_session_summary(df)
                print("Exiting review session.")
                return

            elif choice in ("s", "skip"):
                print("-> Skipped.")
                break

            elif choice in ("v", "view", "clip", "play"):
                if clip_ready:
                    play_clip_in_player(clip_path)
                elif vid_file and vid_file.exists():
                    print("Extracting repetition clip...")
                    ok = generate_repetition_clip(vid_file, int(row["start_frame"]), int(row["end_frame"]), clip_path)
                    if ok:
                        play_clip_in_player(clip_path)
                else:
                    print("Cannot play: video file not found.")

            elif choice in ("1", "correct"):
                notes = input("Notes (optional): ").strip()
                df.at[idx, "ground_truth_label"] = "Correct"
                df.at[idx, "error_tags"] = ""
                df.at[idx, "annotator"] = annotator_name
                df.at[idx, "timestamp"] = datetime.now().isoformat()
                df.at[idx, "notes"] = notes if notes else None
                dirty = True
                print("-> Recorded as: Correct")
                break

            elif choice in ("2", "incorrect"):
                print("\nSelect error tags (enter one or more numbers separated by commas):")
                for t_i, tag in enumerate(VALID_ERROR_TAGS):
                    print(f"  [{t_i+1}] {tag}")
                if auto_tags_str != "None":
                    print(f"  (Auto suggested: {auto_tags_str})")
                tag_in = input("Select tags [e.g. 1,3]: ").strip()
                selected = []
                for part in tag_in.split(","):
                    p = part.strip()
                    if p.isdigit() and 1 <= int(p) <= len(VALID_ERROR_TAGS):
                        selected.append(VALID_ERROR_TAGS[int(p) - 1])
                    elif p in VALID_ERROR_TAGS:
                        selected.append(p)
                    elif p:
                        selected.append(p)

                if not selected:
                    print("[Error] Incorrect repetitions require at least one error tag.")
                    continue

                notes = input("Notes (optional): ").strip()
                df.at[idx, "ground_truth_label"] = "Incorrect"
                df.at[idx, "error_tags"] = ";".join(selected)
                df.at[idx, "annotator"] = annotator_name
                df.at[idx, "timestamp"] = datetime.now().isoformat()
                df.at[idx, "notes"] = notes if notes else None
                dirty = True
                print(f"-> Recorded as: Incorrect (Tags: {'; '.join(selected)})")
                break

            elif choice in ("3", "ambiguous", "exclude"):
                reason = input("Notes explaining why the movement cannot be confidently classified (required): ").strip()
                if not reason:
                    print("[Error] Ambiguous / Exclude requires written notes explaining why movement cannot be classified.")
                    continue
                df.at[idx, "ground_truth_label"] = "Ambiguous"
                df.at[idx, "error_tags"] = "ambiguous_quality"
                df.at[idx, "annotator"] = annotator_name
                df.at[idx, "timestamp"] = datetime.now().isoformat()
                df.at[idx, "notes"] = reason
                dirty = True
                print(f"-> Recorded as: Ambiguous / Exclude (Reason: {reason})")
                break

            else:
                print("Invalid input. Options: 1 (Correct), 2 (Incorrect), 3 (Ambiguous), v (View Clip), s (Skip), q (Save & Quit).")

    if dirty:
        df.to_csv(annotation_path, index=False)
        print(f"\nAll annotations successfully saved to: {annotation_path}")
        generate_manual_annotation_audit(df)

    print_session_summary(df)


def main():
    parser = argparse.ArgumentParser(
        description="Assisted Elbow Flexion Repetition Annotation Review Tool"
    )
    parser.add_argument(
        "--annotations",
        type=Path,
        default=DEFAULT_ANNOTATION_FILE,
        help="Path to annotations CSV",
    )
    parser.add_argument(
        "--annotator",
        type=str,
        default="human_reviewer",
        help="Annotator identifier (e.g. name or reviewer ID)",
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Print annotation statistics, agreement, and error distribution",
    )
    parser.add_argument(
        "--export-clean",
        type=Path,
        default=None,
        help="Export verified clean dataset (Correct/Incorrect only) to target CSV",
    )
    parser.add_argument(
        "--add-mix-videos",
        action="store_true",
        help="Segment and queue the 4 excluded 'Both hand assisted mix' videos for human annotation",
    )
    parser.add_argument(
        "--subject",
        type=str,
        default=None,
        help="Filter review by subject_id (e.g. person1)",
    )
    parser.add_argument(
        "--video",
        type=str,
        default=None,
        help="Filter review by video name substring",
    )
    parser.add_argument(
        "--auto-play",
        action="store_true",
        help="Automatically launch clip in media player when presenting repetition",
    )
    parser.add_argument(
        "--review-auto",
        action="store_true",
        help="Review mode focusing on inspecting provisional auto-labels and assigning verified human ground truth in priority order",
    )
    parser.add_argument(
        "--audit-manual",
        action="store_true",
        help="Generate or update the second-pass manual annotation audit report",
    )

    args = parser.parse_args()

    if args.add_mix_videos:
        add_mix_videos_infrastructure(args.annotations)
        return

    if not args.annotations.exists():
        print(f"[Error] Annotations file not found: {args.annotations}")
        sys.exit(1)

    df = pd.read_csv(args.annotations)

    if args.audit_manual:
        generate_manual_annotation_audit(df)
        return

    if args.stats:
        print_stats(df)
        return

    if args.export_clean:
        export_clean_dataset(df, args.export_clean)
        return

    run_interactive_review(
        df=df,
        annotation_path=args.annotations,
        annotator_name=args.annotator,
        subject_filter=args.subject,
        video_filter=args.video,
        auto_play=args.auto_play,
        review_auto=args.review_auto,
    )


if __name__ == "__main__":
    main()
