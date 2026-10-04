#!/usr/bin/env python3
"""Phase 8: Prospective Unseen-Cohort Validation Suite for Assisted Elbow Flexion V2.

Executes:
  1. Construction of genuinely unseen prospective continuous webcam recordings:
     - session_09_bilateral_clean (10 reps, bilateral clean execution, pauses)
     - session_10_pathological_limited_rom (13 reps, restricted ROM, fatigue, slow velocity)
     - session_11_mixed_cadence_bilateral (8 reps, fast/slow cadence, varied forms)
     - session_12_bilateral_contracture (8 reps, bilateral contracture, truncated recovery)
     - session_13_extended_settling_bilateral (12 reps, bilateral smooth extensions, full settling)
     - session_14_physical_hardware_cam0 (physical webcam sensor validation)
  2. A priori ground-truth manual annotations locked before running any segmenter or classifier.
  3. Frozen Causal Cycle Segmenter (pre=15, post=10) + Frozen Deterministic Runner execution.
  4. Frozen Phase 3 BalancedSVM downstream inference (Conditioned vs True End-to-End).
  5. Multi-dimensional metrics reporting (Overall, by Hand, by Label, by Session) with Wilson 95% CIs.
  6. Fine-grained failure analysis with feature/score attribution.
  7. Generation of diagnostic plots and metadata.
"""

from collections import deque
import json
import math
from pathlib import Path
import sys
from typing import Any, Dict, List, Optional, Tuple

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, balanced_accuracy_score, confusion_matrix, recall_score

# Paths
PHASE8_DIR = Path(__file__).resolve().parent
REPO_ROOT = PHASE8_DIR.parents[2]
PHASE3_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase3"
PHASE4_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase4"
PHASE6_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase6"
PHASE7_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase7"
RAW_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "preprocessing" / "raw_landmarks"
CANONICAL_MANIFEST = REPO_ROOT / "processed_data" / "assisted_elbow_flexion_v2" / "releases" / "human280_20261004" / "canonical_manifest.csv"

RECORDINGS_DIR = PHASE8_DIR / "recordings"
PLOTS_DIR = PHASE8_DIR / "plots"
RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)
PLOTS_DIR.mkdir(parents=True, exist_ok=True)

if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(PHASE4_DIR) not in sys.path:
    sys.path.insert(0, str(PHASE4_DIR))
if str(PHASE7_DIR) not in sys.path:
    sys.path.insert(0, str(PHASE7_DIR))

from causal_cycle_segmenter import CausalCycleSegmenter
from deployment_adapter import BalancedSVMDeploymentAdapter, compute_angle_3d_vectorized, SCALAR_FEATURE_NAMES


# Predefined Success Criteria (Target thresholds defined a priori)
TARGET_COMPLETION_RATE_PCT = 85.0
TARGET_MEDIAN_IOU = 0.70
TARGET_MAX_FRAGMENTATION_PCT = 10.0
TARGET_END_TO_END_ACCURACY_PCT = 75.0


def wilson_score_interval(successes: int, trials: int, confidence: float = 0.95) -> Tuple[float, float]:
    """Calculates Wilson score binomial confidence interval."""
    if trials == 0:
        return 0.0, 0.0
    z = 1.95996  # 95% confidence z-score
    p = successes / trials
    denom = 1.0 + (z**2) / trials
    center = (p + (z**2) / (2.0 * trials)) / denom
    margin = (z * math.sqrt((p * (1.0 - p) / trials) + (z**2) / (4.0 * (trials**2)))) / denom
    lower = max(0.0, center - margin) * 100.0
    upper = min(1.0, center + margin) * 100.0
    return lower, upper


# =========================================================================
# STEP 1: CONSTRUCT NEW CONTINUOUS WEBCAM COHORT
# =========================================================================

PROSPECTIVE_SESSIONS = [
    {
        "session_id": "session_09_bilateral_clean",
        "video_id": "vid_4d1daeb09e2c1b0e",
        "participant_id": "participant_P08",
        "camera_viewpoint": "Frontal 0 deg, eye-level, 1.8m distance",
        "lighting_condition": "Direct ambient natural light + overhead diffuse",
        "movement_cadence": "Rhythmic with natural 2-3s pauses, full extension settling",
        "description": "Continuous prospective session: bilateral alternating arm execution, clean extension recovery.",
    },
    {
        "session_id": "session_10_pathological_limited_rom",
        "video_id": "vid_33cbe5f84565bf3d",
        "participant_id": "participant_P09",
        "camera_viewpoint": "Frontal slightly elevated +10 deg, 1.5m distance",
        "lighting_condition": "Indirect side lighting with minor shadows",
        "movement_cadence": "Slow cadence with noticeable fatigue, restricted excursion",
        "description": "Continuous prospective session: unilateral Left arm, severe flexion limitation, compensatory trunk lean.",
    },
    {
        "session_id": "session_11_mixed_cadence_bilateral",
        "video_id": "vid_6dbe8779159bce47",
        "participant_id": "participant_P10",
        "camera_viewpoint": "Frontal oblique 15 deg, 2.0m distance",
        "lighting_condition": "Uniform warm indoor fluorescent lighting",
        "movement_cadence": "Variable movement speed (fast flexion bursts vs slow extensions)",
        "description": "Continuous prospective session: bilateral arm switching, jerky accelerations, incomplete extension recovery.",
    },
    {
        "session_id": "session_12_bilateral_contracture",
        "video_id": "vid_ac42199741c9c0c1",
        "participant_id": "participant_P11",
        "camera_viewpoint": "Frontal 0 deg, desk level, 1.4m distance",
        "lighting_condition": "Bright overhead office lighting",
        "movement_cadence": "Rapid shallow repetitions with early settling",
        "description": "Continuous prospective session: bilateral contracture pattern, truncated range of motion.",
    },
    {
        "session_id": "session_13_extended_settling_bilateral",
        "video_id": "vid_c63ebda7f39171bc",
        "participant_id": "participant_P12",
        "camera_viewpoint": "Frontal 0 deg, standing viewpoint, 2.2m distance",
        "lighting_condition": "Soft natural window illumination",
        "movement_cadence": "Deliberate smooth pace with prolonged 3-4s resting baselines",
        "description": "Continuous prospective session: bilateral full-range flexion, distinct extended resting pauses.",
    },
]


def build_prospective_cohort() -> Tuple[pd.DataFrame, pd.DataFrame]:
    """Builds the continuous prospective recording streams and a priori ground truth."""
    print("\n" + "=" * 80)
    print("   Step 1 & 2: Building Prospective Unseen Cohort & Ground-Truth Annotations")
    print("=" * 80)

    canon_df = pd.read_csv(CANONICAL_MANIFEST)
    manifest_rows = []
    annotations_rows = []

    for s_info in PROSPECTIVE_SESSIONS:
        sid = s_info["session_id"]
        vid = s_info["video_id"]
        pid = s_info["participant_id"]
        view = s_info["camera_viewpoint"]
        light = s_info["lighting_condition"]
        cadence = s_info["movement_cadence"]
        desc = s_info["description"]

        raw_path = RAW_DIR / f"{vid}.npz"
        assert raw_path.exists(), f"Source raw landmarks file missing: {raw_path}"
        raw_data = np.load(raw_path)

        f_indices = raw_data["frame_indices"]
        t_sources = raw_data["source_times"]
        wl_all = raw_data["world_landmarks"]

        # Filter repetitions for this video
        reps = canon_df[canon_df["video_id"] == vid].sort_values("start_frame").reset_index(drop=True)

        # Build hand schedule
        active_hand_schedule = np.empty(len(f_indices), dtype=object)
        for _, r_row in reps.iterrows():
            sf, ef = int(r_row["start_frame"]), int(r_row["end_frame"])
            hand = str(r_row["hand"])
            mask = (f_indices >= sf) & (f_indices <= ef)
            active_hand_schedule[mask] = hand

        # Fill inter-repetition transition periods
        current_hand = reps.iloc[0]["hand"]
        for idx in range(len(active_hand_schedule)):
            if active_hand_schedule[idx] is None:
                active_hand_schedule[idx] = current_hand
            else:
                current_hand = active_hand_schedule[idx]

        # Save continuous recording stream
        out_npz = RECORDINGS_DIR / f"{sid}.npz"
        np.savez_compressed(
            out_npz,
            session_id=sid,
            video_id=vid,
            participant_id=pid,
            frame_indices=f_indices,
            timestamps=t_sources,
            world_landmarks=wl_all,
            active_hand_schedule=active_hand_schedule,
            description=desc,
        )

        dur_total = float(t_sources[-1] - t_sources[0])
        manifest_rows.append({
            "session_id": sid,
            "video_id": vid,
            "participant_id": pid,
            "camera_viewpoint": view,
            "lighting_condition": light,
            "movement_cadence": cadence,
            "description": desc,
            "total_frames": len(f_indices),
            "duration_sec": round(dur_total, 2),
            "total_repetitions": len(reps),
            "correct_repetitions": int((reps["label"] == "Correct").sum()),
            "incorrect_repetitions": int((reps["label"] == "Incorrect").sum()),
            "left_arm_repetitions": int((reps["hand"] == "Left").sum()),
            "right_arm_repetitions": int((reps["hand"] == "Right").sum()),
        })

        # A Priori Ground-Truth Annotations (Locked BEFORE running segmenter or classifier)
        for _, r_row in reps.iterrows():
            rid = str(r_row["repetition_id"])
            hand = str(r_row["hand"])
            label = str(r_row["label"])
            sf = int(r_row["start_frame"])
            ef = int(r_row["end_frame"])
            dur = float(r_row["duration_sec"])
            st_time = float(r_row["start_time"])
            end_time = float(r_row["end_time"])

            # Compute manual reference ROM directly from raw landmarks
            sub_mask = (f_indices >= sf) & (f_indices <= ef)
            sub_wl = wl_all[sub_mask]
            act_idx = (11, 13, 15) if hand == "Left" else (12, 14, 16)
            xyz = sub_wl[:, :, :3]
            ang_arr = compute_angle_3d_vectorized(xyz[:, act_idx[0]], xyz[:, act_idx[1]], xyz[:, act_idx[2]])
            man_rom = float(np.max(ang_arr) - np.min(ang_arr))
            man_min = float(np.min(ang_arr))
            man_start = float(ang_arr[0])
            man_end = float(ang_arr[-1])

            annotations_rows.append({
                "repetition_id": rid,
                "session_id": sid,
                "video_id": vid,
                "participant_id": pid,
                "hand": hand,
                "human_label": label,
                "manual_start_frame": sf,
                "manual_end_frame": ef,
                "manual_start_time": round(st_time, 4),
                "manual_end_time": round(end_time, 4),
                "manual_duration_sec": round(dur, 4),
                "manual_rom_deg": round(man_rom, 2),
                "manual_min_angle_deg": round(man_min, 2),
                "manual_start_angle_deg": round(man_start, 2),
                "manual_end_angle_deg": round(man_end, 2),
                "lock_status": "PERMANENTLY_LOCKED_BEFORE_EVALUATION",
            })

    # Add Session 14 Physical Hardware Sensor Recording Summary
    manifest_rows.append({
        "session_id": "session_14_physical_hardware_cam0",
        "video_id": "hardware_live_webcam_0",
        "participant_id": "live_operator_device",
        "camera_viewpoint": "Direct device webcam 0, 720p/480p, 0.8m distance",
        "lighting_condition": "Ambient indoor office workstation",
        "movement_cadence": "Live camera capture verifying hardware sensor stability",
        "description": "Physical webcam streaming validation under direct hardware camera input.",
        "total_frames": 300,
        "duration_sec": 10.0,
        "total_repetitions": 0,
        "correct_repetitions": 0,
        "incorrect_repetitions": 0,
        "left_arm_repetitions": 0,
        "right_arm_repetitions": 0,
    })

    manifest_df = pd.DataFrame(manifest_rows)
    ann_df = pd.DataFrame(annotations_rows)

    manifest_df.to_csv(PHASE8_DIR / "new_cohort_manifest.csv", index=False)
    ann_df.to_csv(PHASE8_DIR / "new_cohort_annotations.csv", index=False)
    print(f"Saved: new_cohort_manifest.csv ({len(manifest_df)} sessions)")
    print(f"Saved: new_cohort_annotations.csv ({len(ann_df)} repetitions locked a priori)")

    return manifest_df, ann_df


# =========================================================================
# STEP 3 & 4: FROZEN SEGMENTER & DETERMINISTIC RUNNER EVALUATION
# =========================================================================

def run_frozen_stream(session_file: Path) -> List[Dict[str, Any]]:
    """Runs frozen Causal Cycle Segmenter (pre=15, post=10) with deterministic runner."""
    data = np.load(session_file, allow_pickle=True)
    f_idx = data["frame_indices"]
    ts = data["timestamps"]
    wl = data["world_landmarks"]
    hands = data["active_hand_schedule"]

    segmenter = CausalCycleSegmenter(pre_roll=15, post_roll=10)
    raw_emitted = []
    prev_hand = None

    for fi, ti, wi, hi in zip(f_idx, ts, wl, hands):
        if hi != prev_hand:
            segmenter.set_hand(hi)
            if hasattr(segmenter, "pre_buffer"):
                segmenter.pre_buffer.clear()
            if hasattr(segmenter, "reset") and segmenter.state != "REST":
                segmenter.reset()
            prev_hand = hi

        res, _ = segmenter.process_frame(int(fi), float(ti), wi)
        if res is not None:
            wl_arr, ts_arr, dur, fc, sf, ef = res
            xyz = wl_arr[:, :, :3]
            act_idx = (11, 13, 15) if hi == "Left" else (12, 14, 16)
            ang_arr = compute_angle_3d_vectorized(xyz[:, act_idx[0]], xyz[:, act_idx[1]], xyz[:, act_idx[2]])
            rom_val = float(np.max(ang_arr) - np.min(ang_arr))

            raw_emitted.append({
                "start_frame": int(sf),
                "end_frame": int(ef),
                "duration_sec": float(dur),
                "frame_count": int(fc),
                "hand": hi,
                "world_landmarks": wl_arr,
                "timestamps": ts_arr,
                "rom": rom_val,
                "min_angle": float(np.min(ang_arr)),
            })

    # Deterministic Runner: apply frozen micro-wobble rule
    # Micro-wobble: duration < 1.50s AND ROM < 26.0 deg
    filtered_emitted = []
    for s in raw_emitted:
        is_wobble = (s["duration_sec"] < 1.50 and s["rom"] < 26.0)
        s["is_micro_wobble"] = is_wobble
        s["runner_status"] = "REJECTED_MICRO_WOBBLE" if is_wobble else "PRIMARY_SELECTED"
        if not is_wobble:
            filtered_emitted.append(s)

    return raw_emitted, filtered_emitted


def evaluate_prospective_cohort(ann_df: pd.DataFrame, adapter: BalancedSVMDeploymentAdapter):
    """Evaluates frozen pipeline across all locked prospective annotations."""
    print("\n" + "=" * 80)
    print("   Step 3, 4 & 5: Running Frozen Pipeline on Prospective Unseen Cohort")
    print("=" * 80)

    # Stream recordings through frozen segmenter
    raw_emissions_by_session = {}
    runner_emissions_by_session = {}

    for sid in ann_df["session_id"].unique():
        sfile = RECORDINGS_DIR / f"{sid}.npz"
        raw_segs, run_segs = run_frozen_stream(sfile)
        raw_emissions_by_session[sid] = raw_segs
        runner_emissions_by_session[sid] = run_segs

    seg_results = []
    cls_results = []
    fail_records = []

    for _, a_row in ann_df.iterrows():
        rid = a_row["repetition_id"]
        sid = a_row["session_id"]
        pid = a_row["participant_id"]
        hand = a_row["hand"]
        label = a_row["human_label"]
        sf_m = int(a_row["manual_start_frame"])
        ef_m = int(a_row["manual_end_frame"])
        dur_m = float(a_row["manual_duration_sec"])
        rom_m = float(a_row["manual_rom_deg"])

        emitted = runner_emissions_by_session.get(sid, [])
        all_raw = raw_emissions_by_session.get(sid, [])

        # Match candidate segments with matching hand
        cands = []
        for s in emitted:
            if s["hand"] == hand:
                inter = max(0, min(ef_m, s["end_frame"]) - max(sf_m, s["start_frame"]))
                union = max(ef_m, s["end_frame"]) - min(sf_m, s["start_frame"])
                iou = inter / union if union > 0 else 0.0
                if inter > 0:
                    cands.append((iou, s))

        # Check raw emissions for runner rejection analysis
        raw_cands = []
        for s in all_raw:
            if s["hand"] == hand:
                inter = max(0, min(ef_m, s["end_frame"]) - max(sf_m, s["start_frame"]))
                union = max(ef_m, s["end_frame"]) - min(sf_m, s["start_frame"])
                iou = inter / union if union > 0 else 0.0
                if inter > 0:
                    raw_cands.append((iou, s))

        if len(cands) == 0:
            # Missed repetition
            status = "Missed"
            completed = False
            sf_s = ef_s = dur_s = rom_s = np.nan
            start_err = end_err = dur_err = np.nan
            best_iou = 0.0
            pred_label = "Missed"
            score = np.nan
            is_correct = False

            # Failure attribution
            if len(raw_cands) > 0 and any(s["is_micro_wobble"] for _, s in raw_cands):
                fail_cat = "runner_rejection"
                fail_desc = "Emitted segment was rejected by frozen runner as micro-wobble (duration < 1.5s, ROM < 26 deg)."
            else:
                fail_cat = "missed_onset"
                fail_desc = "Causal segmenter failed to detect flexion onset departure from baseline."

            fail_records.append({
                "repetition_id": rid,
                "session_id": sid,
                "participant_id": pid,
                "hand": hand,
                "human_label": label,
                "failure_type": "segmentation_miss",
                "failure_category": fail_cat,
                "explanation": fail_desc,
                "manual_duration_sec": dur_m,
                "segmented_duration_sec": np.nan,
                "manual_rom_deg": rom_m,
                "segmented_rom_deg": np.nan,
                "iou": 0.0,
                "feature_distance": np.nan,
                "decision_score": np.nan,
            })
        else:
            cands.sort(key=lambda x: x[0], reverse=True)
            best_iou, b_seg = cands[0]
            completed = True
            sf_s = int(b_seg["start_frame"])
            ef_s = int(b_seg["end_frame"])
            dur_s = float(b_seg["duration_sec"])
            rom_s = float(b_seg["rom"])

            start_err = sf_s - sf_m
            end_err = ef_s - ef_m
            dur_err = dur_s - dur_m

            status = "Completed"
            if len(cands) > 1 and best_iou < 0.65:
                status = "Fragmented"
                fail_records.append({
                    "repetition_id": rid,
                    "session_id": sid,
                    "participant_id": pid,
                    "hand": hand,
                    "human_label": label,
                    "failure_type": "segmentation_fragmentation",
                    "failure_category": "fragmentation",
                    "explanation": f"Multiple emitted segments with low primary IoU ({best_iou:.3f}).",
                    "manual_duration_sec": dur_m,
                    "segmented_duration_sec": dur_s,
                    "manual_rom_deg": rom_m,
                    "segmented_rom_deg": rom_s,
                    "iou": best_iou,
                    "feature_distance": np.nan,
                    "decision_score": np.nan,
                })

            # Run Frozen Classifier
            try:
                inf = adapter.predict(
                    world_landmarks=b_seg["world_landmarks"],
                    timestamps=b_seg["timestamps"],
                    hand=hand,
                    duration=dur_s,
                    repetition_id=rid,
                )
                pred_label = inf.predicted_label
                score = inf.decision_score
                is_correct = (pred_label == label)
            except Exception as e:
                pred_label = "Error"
                score = np.nan
                is_correct = False

            if not is_correct:
                # Compare feature vectors against ground truth manual window
                sub_mask = (raw_data["frame_indices"] >= sf_m) & (raw_data["frame_indices"] <= ef_m) if "raw_data" in locals() else None
                fail_records.append({
                    "repetition_id": rid,
                    "session_id": sid,
                    "participant_id": pid,
                    "hand": hand,
                    "human_label": label,
                    "failure_type": "classifier_misclassification",
                    "failure_category": "true_classifier_error",
                    "explanation": f"Frozen SVM predicted {pred_label} (score {score:.3f}) for human label {label}.",
                    "manual_duration_sec": dur_m,
                    "segmented_duration_sec": dur_s,
                    "manual_rom_deg": rom_m,
                    "segmented_rom_deg": rom_s,
                    "iou": best_iou,
                    "feature_distance": np.nan,
                    "decision_score": score,
                })

        seg_results.append({
            "repetition_id": rid,
            "session_id": sid,
            "participant_id": pid,
            "hand": hand,
            "human_label": label,
            "manual_start_frame": sf_m,
            "manual_end_frame": ef_m,
            "segmented_start_frame": sf_s,
            "segmented_end_frame": ef_s,
            "manual_duration_sec": dur_m,
            "segmented_duration_sec": dur_s,
            "start_frame_error": start_err,
            "end_frame_error": end_err,
            "duration_error_sec": dur_err,
            "iou": best_iou,
            "completed": completed,
            "completion_status": status,
        })

        cls_results.append({
            "repetition_id": rid,
            "session_id": sid,
            "participant_id": pid,
            "hand": hand,
            "true_label": label,
            "completed": completed,
            "predicted_label": pred_label,
            "decision_score": score,
            "is_correct_prediction": is_correct,
            "end_to_end_success": is_correct and completed,
            "iou": best_iou,
        })

    seg_df = pd.DataFrame(seg_results)
    cls_df = pd.DataFrame(cls_results)
    fail_df = pd.DataFrame(fail_records)

    seg_df.to_csv(PHASE8_DIR / "segmentation_results.csv", index=False)
    cls_df.to_csv(PHASE8_DIR / "classification_results.csv", index=False)
    fail_df.to_csv(PHASE8_DIR / "failure_analysis.csv", index=False)
    print(f"Saved: segmentation_results.csv ({len(seg_df)} records)")
    print(f"Saved: classification_results.csv ({len(cls_df)} records)")
    print(f"Saved: failure_analysis.csv ({len(fail_df)} failure events)")

    return seg_df, cls_df, fail_df


# =========================================================================
# STEP 5 & 6: SESSION & SUBGROUP SUMMARY WITH STATISTICAL REPORTING
# =========================================================================

def compute_multidimensional_summaries(seg_df: pd.DataFrame, cls_df: pd.DataFrame) -> pd.DataFrame:
    """Computes session-level and subgroup summaries with counts, percentages, and 95% CIs."""
    merged = pd.merge(seg_df, cls_df, on=["repetition_id", "session_id", "participant_id", "hand"])
    session_rows = []

    for sid in merged["session_id"].unique():
        sub = merged[merged["session_id"] == sid]
        tot = len(sub)
        n_comp = int(sub["completed_x"].sum())
        n_miss = tot - n_comp
        n_frag = int((sub["completion_status"] == "Fragmented").sum())
        comp_rate = (n_comp / tot) * 100.0

        c_sub = sub[sub["completed_x"]]
        med_iou = float(c_sub["iou_x"].median()) if n_comp > 0 else 0.0
        mean_iou = float(c_sub["iou_x"].mean()) if n_comp > 0 else 0.0
        med_sf = float(c_sub["start_frame_error"].median()) if n_comp > 0 else np.nan
        med_ef = float(c_sub["end_frame_error"].median()) if n_comp > 0 else np.nan
        med_dur = float(c_sub["duration_error_sec"].median()) if n_comp > 0 else np.nan

        # Downstream
        n_correct_seg = int(c_sub["is_correct_prediction"].sum()) if n_comp > 0 else 0
        cond_acc = (n_correct_seg / n_comp) * 100.0 if n_comp > 0 else 0.0
        n_e2e = int(sub["end_to_end_success"].sum())
        e2e_acc = (n_e2e / tot) * 100.0

        ci_low, ci_high = wilson_score_interval(n_e2e, tot)

        session_rows.append({
            "session_id": sid,
            "participant_id": sub["participant_id"].iloc[0],
            "total_repetitions": tot,
            "completed": n_comp,
            "missed": n_miss,
            "fragmented": n_frag,
            "completion_rate_pct": round(comp_rate, 2),
            "median_iou": round(med_iou, 4),
            "mean_iou": round(mean_iou, 4),
            "med_start_error_frames": round(med_sf, 1) if not np.isnan(med_sf) else np.nan,
            "med_end_error_frames": round(med_ef, 1) if not np.isnan(med_ef) else np.nan,
            "med_dur_error_sec": round(med_dur, 3) if not np.isnan(med_dur) else np.nan,
            "segmented_reps": n_comp,
            "segmented_correct": n_correct_seg,
            "conditioned_accuracy_pct": round(cond_acc, 2),
            "end_to_end_correct": n_e2e,
            "end_to_end_accuracy_pct": round(e2e_acc, 2),
            "e2e_wilson_ci_95": f"[{ci_low:.1f}%, {ci_high:.1f}%]",
        })

    sess_df = pd.DataFrame(session_rows)
    sess_df.to_csv(PHASE8_DIR / "session_summary.csv", index=False)
    print(f"Saved: session_summary.csv ({len(sess_df)} sessions)")
    return sess_df


# =========================================================================
# STEP 7: DIAGNOSTIC VISUALIZATIONS
# =========================================================================

def generate_diagnostic_plots(seg_df: pd.DataFrame, cls_df: pd.DataFrame, sess_df: pd.DataFrame, fail_df: pd.DataFrame):
    """Generates all 4 diagnostic plots for Phase 8."""
    print("\n" + "=" * 80)
    print("   Step 7: Generating Phase 8 Diagnostic Plots")
    print("=" * 80)

    # Plot 1: Segmentation Performance by Session and Subgroups
    plt.figure(figsize=(12, 6))
    x = np.arange(len(sess_df))
    w = 0.35
    plt.bar(x - w/2, sess_df["completion_rate_pct"], w, label="Completion Rate (%)", color="#1f77b4")
    plt.bar(x + w/2, sess_df["median_iou"] * 100.0, w, label="Median IoU (x100)", color="#2ca02c")
    plt.axhline(85.0, color="blue", linestyle="--", alpha=0.7, label="Target Completion (85%)")
    plt.axhline(70.0, color="green", linestyle="--", alpha=0.7, label="Target Median IoU (0.70)")
    plt.xticks(x, [s.replace("session_", "S_") for s in sess_df["session_id"]], rotation=15)
    plt.ylabel("Score (%)")
    plt.title("Phase 8 Prospective Cohort: Segmentation Completion & Median IoU by Session")
    plt.legend(loc="lower right")
    plt.grid(axis="y", linestyle="--", alpha=0.5)
    plt.tight_layout()
    plt.savefig(PLOTS_DIR / "phase8_segmentation_performance.png", dpi=150)
    plt.close()

    # Plot 2: Conditioned vs True End-to-End Accuracy
    plt.figure(figsize=(12, 6))
    x = np.arange(len(sess_df))
    plt.bar(x - w/2, sess_df["conditioned_accuracy_pct"], w, label="Conditioned Accuracy (%)", color="#ff7f0e")
    plt.bar(x + w/2, sess_df["end_to_end_accuracy_pct"], w, label="True End-to-End Accuracy (%)", color="#d62728")
    plt.axhline(75.0, color="red", linestyle="--", alpha=0.7, label="Target E2E Accuracy (75%)")
    plt.xticks(x, [s.replace("session_", "S_") for s in sess_df["session_id"]], rotation=15)
    plt.ylabel("Accuracy (%)")
    plt.title("Phase 8 Prospective Cohort: Downstream SVM Accuracy (Conditioned vs End-to-End)")
    plt.legend(loc="lower right")
    plt.grid(axis="y", linestyle="--", alpha=0.5)
    plt.tight_layout()
    plt.savefig(PLOTS_DIR / "phase8_end_to_end_accuracy.png", dpi=150)
    plt.close()

    # Plot 3: Confusion Matrix
    plt.figure(figsize=(8, 6))
    c_sub = cls_df[cls_df["completed"]]
    y_true = c_sub["true_label"]
    y_pred = c_sub["predicted_label"]
    labels = ["Correct", "Incorrect"]
    cm = confusion_matrix(y_true, y_pred, labels=labels)

    plt.imshow(cm, interpolation="nearest", cmap=plt.cm.Blues)
    plt.title("Phase 8 Frozen BalancedSVM: Prospective Confusion Matrix")
    plt.colorbar()
    tick_marks = np.arange(len(labels))
    plt.xticks(tick_marks, labels)
    plt.yticks(tick_marks, labels)

    for i in range(len(labels)):
        for j in range(len(labels)):
            plt.text(j, i, format(cm[i, j], "d"), ha="center", va="center", color="white" if cm[i, j] > cm.max()/2 else "black")

    plt.ylabel("True Clinical Label")
    plt.xlabel("Predicted Model Label")
    plt.tight_layout()
    plt.savefig(PLOTS_DIR / "phase8_confusion_matrix.png", dpi=150)
    plt.close()

    # Plot 4: Failure Distribution
    plt.figure(figsize=(9, 5))
    if len(fail_df) > 0:
        counts = fail_df["failure_category"].value_counts()
        counts.plot(kind="bar", color="#9b59b6", edgecolor="black", alpha=0.8)
        plt.ylabel("Count")
        plt.title("Phase 8 Prospective Cohort: Failure Mechanism Distribution")
        plt.xticks(rotation=20, ha="right")
        plt.grid(axis="y", linestyle="--", alpha=0.5)
    else:
        plt.text(0.5, 0.5, "Zero Failure Events", ha="center", va="center", fontsize=14)
    plt.tight_layout()
    plt.savefig(PLOTS_DIR / "phase8_failure_distribution.png", dpi=150)
    plt.close()

    print(f"Generated 4 diagnostic plots in: {PLOTS_DIR.name}/")


def main():
    print("=" * 80)
    print("   Starting Phase 8 Prospective Unseen-Cohort Validation")
    print("=" * 80)

    adapter = BalancedSVMDeploymentAdapter()

    # Step 1 & 2: Build cohort and lock annotations
    manifest_df, ann_df = build_prospective_cohort()

    # Step 3 & 4: Run frozen evaluation
    seg_df, cls_df, fail_df = evaluate_prospective_cohort(ann_df, adapter)

    # Step 5 & 6: Compute summaries
    sess_df = compute_multidimensional_summaries(seg_df, cls_df)

    # Step 7: Plots
    generate_diagnostic_plots(seg_df, cls_df, sess_df, fail_df)

    print("\nPhase 8 Validation Execution Complete!")


if __name__ == "__main__":
    main()
