"""Assisted Elbow Flexion V2 - Phase 5 Segmentation Strategy Benchmark.

Compares 5 Candidate Segmentation Strategies across all 280 canonical repetitions:
1. Baseline (Phase 4 Fixed 135 deg Threshold)
2. Pre-Roll & Post-Roll Circular Buffers (Fixed 135 deg)
3. Adaptive Baseline with Hysteresis
4. Velocity-Aware & Smoothed Boundary State Machine
5. Composite Adaptive Kinematic Segmenter (AdaptiveKinematic)

Evaluates strictly on kinematic boundary ground truth:
- Start-frame error (median, IQR)
- End-frame error (median, IQR)
- Duration error (median, IQR)
- ROM error (median, IQR)
- Coverage / IoU (mean, median)
- Completion / Detection rate (%)
- Fragmentation rate (%)
- Merged rate (%)
- Missed rate (%)
- Secondary diagnostic: Frozen SVM Balanced Accuracy and Macro-F1

Outputs:
- research/assisted_elbow_flexion_v2/phase5/segmentation_strategy_comparison.csv
- research/assisted_elbow_flexion_v2/phase5/canonical_replay_results.csv
"""

from collections import deque
from dataclasses import dataclass
import json
from pathlib import Path
import sys
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
from sklearn.metrics import balanced_accuracy_score, f1_score

PHASE5_DIR = Path(__file__).resolve().parent
REPO_ROOT = PHASE5_DIR.parents[2]
PHASE4_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase4"
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(PHASE4_DIR) not in sys.path:
    sys.path.insert(0, str(PHASE4_DIR))

from deployment_adapter import (
    BalancedSVMDeploymentAdapter,
    SCALAR_FEATURE_NAMES,
    compute_angle_3d_vectorized,
)

MANIFEST_PATH = REPO_ROOT / "processed_data" / "assisted_elbow_flexion_v2" / "releases" / "human280_20261004" / "canonical_manifest.csv"
RAW_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "preprocessing" / "raw_landmarks"


@dataclass
class FrameItem:
    frame_idx: int
    timestamp_sec: float
    world_landmarks: np.ndarray
    active_angle: float
    opposing_angle: float


# =========================================================================
# Strategy 1: Baseline Fixed 135 deg (Phase 4)
# =========================================================================
class Strategy1_FixedBaseline:
    name = "Strategy 1: Fixed 135 deg Threshold (Phase 4 Baseline)"

    def __init__(self, hand: str = "Right"):
        self.hand = hand
        self.flexion_threshold = 135.0
        self.turnaround_reversal = 12.0
        self.extension_finish = 135.0
        self.min_rom = 25.0
        self.min_frames = 15
        self.min_dur = 0.8
        self.reset()

    def reset(self):
        self.state = "READY"
        self.buffer: List[FrameItem] = []
        self.start_frame_idx = None
        self.start_time = None
        self.min_angle = 180.0

    def process_frame(self, frame_idx: int, t_sec: float, wl: np.ndarray, ang: float, opp: float) -> Optional[Tuple]:
        item = FrameItem(frame_idx, t_sec, wl, ang, opp)
        completed = None

        if self.state == "READY":
            if ang < self.flexion_threshold:
                self.state = "FLEXING"
                self.start_frame_idx = frame_idx
                self.start_time = t_sec
                self.min_angle = ang
                self.buffer = [item]

        elif self.state == "FLEXING":
            self.buffer.append(item)
            self.min_angle = min(self.min_angle, ang)
            if ang > (self.min_angle + self.turnaround_reversal):
                self.state = "EXTENDING"

        elif self.state == "EXTENDING":
            self.buffer.append(item)
            if ang >= self.extension_finish:
                dur = t_sec - self.start_time
                angles = [f.active_angle for f in self.buffer]
                rom = max(angles) - min(angles)
                if dur >= self.min_dur and len(self.buffer) >= self.min_frames and rom >= self.min_rom:
                    wl_arr = np.stack([f.world_landmarks for f in self.buffer])
                    ts_arr = np.array([f.timestamp_sec for f in self.buffer], dtype=np.float64)
                    completed = (wl_arr, ts_arr, dur, len(self.buffer), self.buffer[0].frame_idx, self.buffer[-1].frame_idx)
                self.reset()

        return completed


# =========================================================================
# Strategy 2: Pre-Roll & Post-Roll Circular Buffers
# =========================================================================
class Strategy2_PrePostRoll:
    name = "Strategy 2: Fixed 135 deg with Circular Pre/Post-Roll Buffers"

    def __init__(self, hand: str = "Right", pre_roll: int = 20, post_roll: int = 15):
        self.hand = hand
        self.flexion_threshold = 135.0
        self.turnaround_reversal = 12.0
        self.extension_finish = 135.0
        self.min_rom = 25.0
        self.min_frames = 15
        self.min_dur = 0.8
        self.pre_roll_len = pre_roll
        self.post_roll_len = post_roll
        self.pre_buffer = deque(maxlen=pre_roll)
        self.post_count = 0
        self.reset()

    def reset(self):
        self.state = "READY"
        self.buffer: List[FrameItem] = []
        self.start_frame_idx = None
        self.start_time = None
        self.min_angle = 180.0
        self.post_count = 0

    def process_frame(self, frame_idx: int, t_sec: float, wl: np.ndarray, ang: float, opp: float) -> Optional[Tuple]:
        item = FrameItem(frame_idx, t_sec, wl, ang, opp)
        completed = None

        if self.state == "READY":
            self.pre_buffer.append(item)
            if ang < self.flexion_threshold:
                self.state = "FLEXING"
                self.buffer = list(self.pre_buffer)
                self.start_frame_idx = self.buffer[0].frame_idx
                self.start_time = self.buffer[0].timestamp_sec
                self.min_angle = ang

        elif self.state == "FLEXING":
            self.buffer.append(item)
            self.min_angle = min(self.min_angle, ang)
            if ang > (self.min_angle + self.turnaround_reversal):
                self.state = "EXTENDING"

        elif self.state == "EXTENDING":
            self.buffer.append(item)
            if ang >= self.extension_finish:
                self.state = "POST_ROLL"
                self.post_count = 0

        elif self.state == "POST_ROLL":
            self.buffer.append(item)
            self.post_count += 1
            if self.post_count >= self.post_roll_len:
                dur = self.buffer[-1].timestamp_sec - self.start_time
                angles = [f.active_angle for f in self.buffer]
                rom = max(angles) - min(angles)
                if dur >= self.min_dur and len(self.buffer) >= self.min_frames and rom >= self.min_rom:
                    wl_arr = np.stack([f.world_landmarks for f in self.buffer])
                    ts_arr = np.array([f.timestamp_sec for f in self.buffer], dtype=np.float64)
                    completed = (wl_arr, ts_arr, dur, len(self.buffer), self.buffer[0].frame_idx, self.buffer[-1].frame_idx)
                self.reset()

        return completed


# =========================================================================
# Strategy 3: Adaptive Baseline with Hysteresis
# =========================================================================
class Strategy3_AdaptiveHysteresis:
    name = "Strategy 3: Adaptive Extension Baseline with Hysteresis"

    def __init__(self, hand: str = "Right", baseline_window: int = 35):
        self.hand = hand
        self.baseline_window = baseline_window
        self.baseline_history = deque(maxlen=baseline_window)
        self.pre_buffer = deque(maxlen=15)
        self.turnaround_reversal = 12.0
        self.min_rom = 25.0
        self.min_frames = 15
        self.min_dur = 0.8
        self.post_roll_len = 12
        self.post_count = 0
        self.reset()

    def reset(self):
        self.state = "READY"
        self.buffer: List[FrameItem] = []
        self.start_frame_idx = None
        self.start_time = None
        self.min_angle = 180.0
        self.current_baseline = 148.0
        self.post_count = 0

    def process_frame(self, frame_idx: int, t_sec: float, wl: np.ndarray, ang: float, opp: float) -> Optional[Tuple]:
        item = FrameItem(frame_idx, t_sec, wl, ang, opp)
        completed = None

        if self.state == "READY":
            self.pre_buffer.append(item)
            self.baseline_history.append(ang)
            if len(self.baseline_history) >= 10:
                self.current_baseline = float(np.clip(np.percentile(self.baseline_history, 85), 136.0, 168.0))

            flexion_start_thresh = self.current_baseline - 10.0
            if ang < flexion_start_thresh:
                self.state = "FLEXING"
                self.buffer = list(self.pre_buffer)
                self.start_frame_idx = self.buffer[0].frame_idx
                self.start_time = self.buffer[0].timestamp_sec
                self.min_angle = ang

        elif self.state == "FLEXING":
            self.buffer.append(item)
            self.min_angle = min(self.min_angle, ang)
            if ang > (self.min_angle + self.turnaround_reversal):
                self.state = "EXTENDING"

        elif self.state == "EXTENDING":
            self.buffer.append(item)
            extension_thresh = max(self.current_baseline - 6.0, 138.0)
            if ang >= extension_thresh:
                self.state = "POST_ROLL"
                self.post_count = 0

        elif self.state == "POST_ROLL":
            self.buffer.append(item)
            self.post_count += 1
            if self.post_count >= self.post_roll_len:
                dur = self.buffer[-1].timestamp_sec - self.start_time
                angles = [f.active_angle for f in self.buffer]
                rom = max(angles) - min(angles)
                if dur >= self.min_dur and len(self.buffer) >= self.min_frames and rom >= self.min_rom:
                    wl_arr = np.stack([f.world_landmarks for f in self.buffer])
                    ts_arr = np.array([f.timestamp_sec for f in self.buffer], dtype=np.float64)
                    completed = (wl_arr, ts_arr, dur, len(self.buffer), self.buffer[0].frame_idx, self.buffer[-1].frame_idx)
                self.reset()

        return completed


# =========================================================================
# Strategy 4: Velocity-Aware & Smoothed Boundary State Machine
# =========================================================================
class Strategy4_VelocityAwareSmoothed:
    name = "Strategy 4: Velocity-Aware & Smoothed Boundary State Machine"

    def __init__(self, hand: str = "Right"):
        self.hand = hand
        self.pre_buffer = deque(maxlen=20)
        self.ang_history = deque(maxlen=5)
        self.time_history = deque(maxlen=5)
        self.min_rom = 25.0
        self.min_frames = 15
        self.min_dur = 0.8
        self.turnaround_reversal = 12.0
        self.post_count = 0
        self.reset()

    def reset(self):
        self.state = "READY"
        self.buffer: List[FrameItem] = []
        self.start_frame_idx = None
        self.start_time = None
        self.min_angle = 180.0
        self.post_count = 0

    def process_frame(self, frame_idx: int, t_sec: float, wl: np.ndarray, ang: float, opp: float) -> Optional[Tuple]:
        item = FrameItem(frame_idx, t_sec, wl, ang, opp)
        self.ang_history.append(ang)
        self.time_history.append(t_sec)

        s_ang = float(np.mean(self.ang_history))
        if len(self.time_history) >= 3:
            dt = self.time_history[-1] - self.time_history[0]
            vel = (self.ang_history[-1] - self.ang_history[0]) / max(dt, 1e-4)
        else:
            vel = 0.0

        completed = None

        if self.state == "READY":
            self.pre_buffer.append(item)
            if s_ang < 140.0 and vel < -8.0:
                self.state = "FLEXING"
                self.buffer = list(self.pre_buffer)
                self.start_frame_idx = self.buffer[0].frame_idx
                self.start_time = self.buffer[0].timestamp_sec
                self.min_angle = s_ang

        elif self.state == "FLEXING":
            self.buffer.append(item)
            self.min_angle = min(self.min_angle, s_ang)
            if s_ang > (self.min_angle + self.turnaround_reversal) and vel > 5.0:
                self.state = "EXTENDING"

        elif self.state == "EXTENDING":
            self.buffer.append(item)
            if s_ang >= 140.0 or (s_ang >= 135.0 and abs(vel) < 15.0):
                self.state = "POST_ROLL"
                self.post_count = 0

        elif self.state == "POST_ROLL":
            self.buffer.append(item)
            self.post_count += 1
            if self.post_count >= 12:
                dur = self.buffer[-1].timestamp_sec - self.start_time
                angles = [f.active_angle for f in self.buffer]
                rom = max(angles) - min(angles)
                if dur >= self.min_dur and len(self.buffer) >= self.min_frames and rom >= self.min_rom:
                    wl_arr = np.stack([f.world_landmarks for f in self.buffer])
                    ts_arr = np.array([f.timestamp_sec for f in self.buffer], dtype=np.float64)
                    completed = (wl_arr, ts_arr, dur, len(self.buffer), self.buffer[0].frame_idx, self.buffer[-1].frame_idx)
                self.reset()

        return completed


# =========================================================================
# Strategy 5: Composite Adaptive Kinematic Segmenter (AdaptiveKinematic)
# =========================================================================
class Strategy5_AdaptiveKinematic:
    name = "Strategy 5: Composite Adaptive Kinematic Segmenter (AdaptiveKinematic)"

    def __init__(self, hand: str = "Right", pre_roll: int = 20, post_roll: int = 15):
        self.hand = hand
        self.pre_roll = pre_roll
        self.post_roll = post_roll
        self.pre_buffer = deque(maxlen=pre_roll)
        self.baseline_history = deque(maxlen=45)
        self.filter_window = deque(maxlen=3)
        self.time_window = deque(maxlen=3)
        self.min_rom = 25.0
        self.min_frames = 15
        self.min_dur = 0.8
        self.turnaround_reversal = 12.0
        self.post_count = 0
        self.reset()

    def reset(self):
        self.state = "READY"
        self.buffer: List[FrameItem] = []
        self.start_frame_idx = None
        self.start_time = None
        self.min_angle = 180.0
        self.current_baseline = 148.0
        self.post_count = 0

    def process_frame(self, frame_idx: int, t_sec: float, wl: np.ndarray, ang: float, opp: float) -> Optional[Tuple]:
        item = FrameItem(frame_idx, t_sec, wl, ang, opp)
        self.filter_window.append(ang)
        self.time_window.append(t_sec)

        filt_ang = float(np.median(self.filter_window))
        if len(self.time_window) >= 3:
            dt = self.time_window[-1] - self.time_window[0]
            vel = (self.filter_window[-1] - self.filter_window[0]) / max(dt, 1e-4)
        else:
            vel = 0.0

        completed = None

        if self.state == "READY":
            self.pre_buffer.append(item)
            self.baseline_history.append(ang)
            if len(self.baseline_history) >= 15:
                self.current_baseline = float(np.clip(np.percentile(self.baseline_history, 85), 136.0, 168.0))

            flexion_start_thresh = self.current_baseline - 9.0
            if filt_ang < flexion_start_thresh and vel < -6.0:
                self.state = "FLEXING"
                self.buffer = list(self.pre_buffer)
                self.start_frame_idx = self.buffer[0].frame_idx
                self.start_time = self.buffer[0].timestamp_sec
                self.min_angle = filt_ang

        elif self.state == "FLEXING":
            self.buffer.append(item)
            self.min_angle = min(self.min_angle, filt_ang)
            if filt_ang > (self.min_angle + self.turnaround_reversal):
                self.state = "EXTENDING"

        elif self.state == "EXTENDING":
            self.buffer.append(item)
            extension_target = min(self.current_baseline - 5.0, 142.0)
            settled = (filt_ang >= 135.0 and abs(vel) < 12.0)
            if filt_ang >= extension_target or settled:
                self.state = "POST_ROLL"
                self.post_count = 0

        elif self.state == "POST_ROLL":
            self.buffer.append(item)
            self.post_count += 1
            if self.post_count >= self.post_roll:
                dur = self.buffer[-1].timestamp_sec - self.start_time
                angles = [f.active_angle for f in self.buffer]
                rom = max(angles) - min(angles)
                if dur >= self.min_dur and len(self.buffer) >= self.min_frames and rom >= self.min_rom:
                    wl_arr = np.stack([f.world_landmarks for f in self.buffer])
                    ts_arr = np.array([f.timestamp_sec for f in self.buffer], dtype=np.float64)
                    completed = (wl_arr, ts_arr, dur, len(self.buffer), self.buffer[0].frame_idx, self.buffer[-1].frame_idx)
                self.reset()

        return completed


def run_benchmark():
    print("=" * 75)
    print("   Running Phase 5 Canonical Replay Segmentation Benchmark")
    print("   Evaluating 5 Strategies across all 280 Canonical Repetitions")
    print("=" * 75)

    manifest = pd.read_csv(MANIFEST_PATH)
    adapter = BalancedSVMDeploymentAdapter()
    raw_cache = {}

    strategies = [
        Strategy1_FixedBaseline,
        Strategy2_PrePostRoll,
        Strategy3_AdaptiveHysteresis,
        Strategy4_VelocityAwareSmoothed,
        Strategy5_AdaptiveKinematic,
    ]

    all_replay_records = []
    strategy_summary_rows = []

    # Pre-load video data
    for vid in manifest["video_id"].unique():
        raw_cache[vid] = np.load(RAW_DIR / f"{vid}.npz")
    print(f"Loaded {len(raw_cache)} raw landmark archives into cache.")

    for strat_cls in strategies:
        strat_name = strat_cls.name
        print(f"\nEvaluating: {strat_name}...")

        start_errors = []
        end_errors = []
        dur_errors = []
        rom_errors = []
        ious = []
        completed_count = 0
        fragmented_count = 0
        svm_preds = []
        svm_true = []

        for idx, row in manifest.iterrows():
            vid = row["video_id"]
            rid = row["repetition_id"]
            hand = row["hand"]
            label = row["label"]
            y_true = 1 if label == "Incorrect" else 0

            a, b = int(row["start_frame"]), int(row["end_frame"])
            d = raw_cache[vid]
            f_all = d["frame_indices"]
            t_all = d["source_times"]
            wl_all = d["world_landmarks"]

            active_idx = (11, 13, 15) if hand == "Left" else (12, 14, 16)
            opposing_idx = (12, 14, 16) if hand == "Left" else (11, 13, 15)

            # Stream context around repetition: [max(0, a - 35), min(len-1, b + 35)]
            idx_a = int(np.where(f_all == a)[0][0])
            idx_b = int(np.where(f_all == b)[0][0])
            ctx_start = max(0, idx_a - 35)
            ctx_end = min(len(f_all) - 1, idx_b + 35)

            f_stream = f_all[ctx_start : ctx_end + 1]
            t_stream = t_all[ctx_start : ctx_end + 1]
            wl_stream = wl_all[ctx_start : ctx_end + 1]

            xyz = wl_stream[:, :, :3]
            u_act = xyz[:, active_idx[0]] - xyz[:, active_idx[1]]
            v_act = xyz[:, active_idx[2]] - xyz[:, active_idx[1]]
            c_act = np.sum(u_act * v_act, axis=-1) / (np.linalg.norm(u_act, axis=-1) * np.linalg.norm(v_act, axis=-1) + 1e-8)
            ang_act = np.degrees(np.arccos(np.clip(c_act, -1, 1)))

            u_opp = xyz[:, opposing_idx[0]] - xyz[:, opposing_idx[1]]
            v_opp = xyz[:, opposing_idx[2]] - xyz[:, opposing_idx[1]]
            c_opp = np.sum(u_opp * v_opp, axis=-1) / (np.linalg.norm(u_opp, axis=-1) * np.linalg.norm(v_opp, axis=-1) + 1e-8)
            ang_opp = np.degrees(np.arccos(np.clip(c_opp, -1, 1)))

            # Canonical window ground truth
            mask_canon = (f_stream >= a) & (f_stream <= b)
            t_canon = t_stream[mask_canon]
            dur_canon = float(t_canon[-1] - t_canon[0])
            rom_canon = float(np.max(ang_act[mask_canon]) - np.min(ang_act[mask_canon]))

            # Run strategy
            seg = strat_cls(hand=hand)
            emitted_reps = []

            for fi, ti, wli, ai, oi in zip(f_stream, t_stream, wl_stream, ang_act, ang_opp):
                bndl = seg.process_frame(int(fi), float(ti), wli, float(ai), float(oi))
                if bndl is not None:
                    emitted_reps.append(bndl)

            if len(emitted_reps) == 0:
                # Missed
                start_err = np.nan
                end_err = np.nan
                dur_err = np.nan
                rom_err = np.nan
                iou = 0.0
                pred_label = "Missed"
                svm_preds.append(1)  # Default fallback
                svm_true.append(y_true)
            else:
                if len(emitted_reps) > 1:
                    fragmented_count += 1
                best_bndl = None
                best_overlap = -1
                for bndl in emitted_reps:
                    s_a, s_b = bndl[4], bndl[5]
                    overlap = max(0, min(b, s_b) - max(a, s_a))
                    if overlap > best_overlap:
                        best_overlap = overlap
                        best_bndl = bndl

                wl_c, ts_c, dur_c, fc_c, s_a, s_b = best_bndl
                completed_count += 1

                start_err = s_a - a
                end_err = s_b - b
                dur_err = dur_c - dur_canon
                angles_seg = [ang_act[idx_f] for idx_f, f_val in enumerate(f_stream) if s_a <= f_val <= s_b]
                rom_seg = (max(angles_seg) - min(angles_seg)) if angles_seg else 0.0
                rom_err = rom_seg - rom_canon

                inter = max(0, min(b, s_b) - max(a, s_a))
                union = max(b, s_b) - min(a, s_a)
                iou = inter / max(union, 1)

                start_errors.append(start_err)
                end_errors.append(end_err)
                dur_errors.append(dur_err)
                rom_errors.append(rom_err)
                ious.append(iou)

                # Secondary diagnostic: evaluate frozen SVM
                res = adapter.predict(wl_c, ts_c, hand=hand, duration=dur_c)
                pred_label = res.predicted_label
                svm_preds.append(1 if pred_label == "Incorrect" else 0)
                svm_true.append(y_true)

            all_replay_records.append({
                "strategy": strat_name,
                "repetition_id": rid,
                "video_id": vid,
                "hand": hand,
                "ground_truth_label": label,
                "canon_start_frame": a,
                "canon_end_frame": b,
                "canon_duration": dur_canon,
                "canon_rom": rom_canon,
                "completed": (len(emitted_reps) > 0),
                "fragmented": (len(emitted_reps) > 1),
                "start_frame_error": start_err,
                "end_frame_error": end_err,
                "duration_error": dur_err,
                "rom_error": rom_err,
                "iou": iou,
                "predicted_label": pred_label,
            })

        completion_pct = completed_count / 280.0 * 100.0
        frag_pct = fragmented_count / 280.0 * 100.0
        missed_pct = (280 - completed_count) / 280.0 * 100.0

        med_start_err = float(np.median(start_errors)) if start_errors else np.nan
        med_end_err = float(np.median(end_errors)) if end_errors else np.nan
        med_dur_err = float(np.median(dur_errors)) if dur_errors else np.nan
        med_rom_err = float(np.median(rom_errors)) if rom_errors else np.nan
        mean_iou = float(np.mean(ious)) if ious else 0.0
        med_iou = float(np.median(ious)) if ious else 0.0

        ba = float(balanced_accuracy_score(svm_true, svm_preds))
        f1 = float(f1_score(svm_true, svm_preds, average="macro"))

        print(f"Results for {strat_name}:")
        print(f"  Completion: {completion_pct:.1f}% | Mean IoU: {mean_iou:.3f} (Median IoU: {med_iou:.3f})")
        print(f"  Median Start Error: {med_start_err:+.1f} frames | Median End Error: {med_end_err:+.1f} frames")
        print(f"  Median Duration Error: {med_dur_err:+.2f} s | Median ROM Error: {med_rom_err:+.1f}\u00b0")
        print(f"  Secondary Diagnostic SVM: Balanced Accuracy = {ba * 100.0:.2f}%, Macro-F1 = {f1 * 100.0:.2f}%")

        strategy_summary_rows.append({
            "strategy": strat_name,
            "completion_rate_pct": completion_pct,
            "mean_iou": mean_iou,
            "median_iou": med_iou,
            "median_start_frame_error": med_start_err,
            "median_end_frame_error": med_end_err,
            "median_duration_error_sec": med_dur_err,
            "median_rom_error_deg": med_rom_err,
            "fragmentation_rate_pct": frag_pct,
            "missed_rate_pct": missed_pct,
            "svm_diagnostic_balanced_accuracy": ba,
            "svm_diagnostic_macro_f1": f1,
        })

    # Save CSV deliverables
    df_replay = pd.DataFrame(all_replay_records)
    replay_csv_path = PHASE5_DIR / "canonical_replay_results.csv"
    df_replay.to_csv(replay_csv_path, index=False)
    print(f"\nSaved canonical replay results ({len(df_replay)} records) to: {replay_csv_path}")

    df_strat = pd.DataFrame(strategy_summary_rows)
    strat_csv_path = PHASE5_DIR / "segmentation_strategy_comparison.csv"
    df_strat.to_csv(strat_csv_path, index=False)
    print(f"Saved strategy comparison ({len(df_strat)} strategies) to: {strat_csv_path}")


if __name__ == "__main__":
    run_benchmark()
