"""Assisted Elbow Flexion V2 - Phase 5 Segmentation Error Analysis.

Compares human-reviewed canonical windows against automatically segmented live windows
for the 30-repetition shadow cohort:
- start-frame difference
- end-frame difference
- duration difference
- start-angle difference
- end-angle difference
- minimum-angle difference
- ROM difference
- peak velocity difference
- feature-vector L2 norm deviation

Produces:
- research/assisted_elbow_flexion_v2/phase5/segmentation_error_analysis.csv
"""

import json
from pathlib import Path
import sys
import numpy as np
import pandas as pd

PHASE5_DIR = Path(__file__).resolve().parent
REPO_ROOT = PHASE5_DIR.parents[2]
PHASE4_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase4"
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(PHASE4_DIR) not in sys.path:
    sys.path.insert(0, str(PHASE4_DIR))

from deployment_adapter import BalancedSVMDeploymentAdapter
from live_elbow_camera_v2 import RepetitionSegmenter

MANIFEST_PATH = REPO_ROOT / "processed_data" / "assisted_elbow_flexion_v2" / "releases" / "human280_20261004" / "canonical_manifest.csv"
RAW_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "preprocessing" / "raw_landmarks"


def main():
    print("=" * 75)
    print("   Generating Phase 5 Segmentation Error Analysis (Step 3)")
    print("=" * 75)

    manifest = pd.read_csv(MANIFEST_PATH)
    adapter = BalancedSVMDeploymentAdapter()

    # Authoritative 30-repetition shadow cohort
    correct_left = manifest[(manifest["label"] == "Correct") & (manifest["hand"] == "Left")].head(8)
    correct_right = manifest[(manifest["label"] == "Correct") & (manifest["hand"] == "Right")].head(7)
    incorrect_left = manifest[(manifest["label"] == "Incorrect") & (manifest["hand"] == "Left")].head(7)
    incorrect_right = manifest[(manifest["label"] == "Incorrect") & (manifest["hand"] == "Right")].head(8)
    test_cohort = pd.concat([correct_left, correct_right, incorrect_left, incorrect_right]).reset_index(drop=True)

    raw_cache = {}
    rows = []

    for idx, r in test_cohort.iterrows():
        vid = r["video_id"]
        rid = r["repetition_id"]
        hand = r["hand"]
        label = r["label"]
        a, b = int(r["start_frame"]), int(r["end_frame"])

        if vid not in raw_cache:
            raw_cache[vid] = np.load(RAW_DIR / f"{vid}.npz")
        d = raw_cache[vid]

        mask_canon = (d["frame_indices"] >= a) & (d["frame_indices"] <= b)
        f_canon = d["frame_indices"][mask_canon]
        t_canon = d["source_times"][mask_canon]
        wl_canon = d["world_landmarks"][mask_canon]

        dur_canon = float(t_canon[-1] - t_canon[0])
        scalars_canon, feat_canon, _ = adapter.extract_features(wl_canon, t_canon, hand=hand, duration=dur_canon)

        # Stream context through Phase 4 live segmenter (135 deg baseline)
        seg = RepetitionSegmenter(hand=hand)
        completed_bundle = None
        for fi, ti, wi in zip(f_canon, t_canon, wl_canon):
            bndl, _ = seg.process_frame(int(fi), float(ti), wi)
            if bndl is not None:
                completed_bundle = bndl

        if completed_bundle is not None:
            wl_seg, ts_seg, dur_seg, f_cnt_seg = completed_bundle
            scalars_seg, feat_seg, _ = adapter.extract_features(wl_seg, ts_seg, hand=hand, duration=dur_seg)
            # Map start and end frame to f_canon
            start_i = int(np.argmin(np.abs(t_canon - ts_seg[0])))
            end_i = int(np.argmin(np.abs(t_canon - ts_seg[-1])))
            seg_start_frame = int(f_canon[start_i])
            seg_end_frame = int(f_canon[end_i])
            seg_status = "STREAM_COMPLETED"
        else:
            dur_seg = np.nan
            seg_start_frame = np.nan
            seg_end_frame = np.nan
            scalars_seg = np.full(34, np.nan)
            feat_seg = {}
            seg_status = "MISSED_BY_SEGMENTER"

        start_f_diff = seg_start_frame - a if np.isfinite(seg_start_frame) else np.nan
        end_f_diff = seg_end_frame - b if np.isfinite(seg_end_frame) else np.nan
        dur_diff = dur_seg - dur_canon if np.isfinite(dur_seg) else np.nan

        start_ang_diff = feat_seg.get("active_start_angle", np.nan) - feat_canon["active_start_angle"]
        end_ang_diff = feat_seg.get("active_end_angle", np.nan) - feat_canon["active_end_angle"]
        min_ang_diff = feat_seg.get("active_min_angle", np.nan) - feat_canon["active_min_angle"]
        rom_diff = feat_seg.get("active_rom", np.nan) - feat_canon["active_rom"]
        peak_vel_diff = feat_seg.get("active_peak_abs_velocity", np.nan) - feat_canon["active_peak_abs_velocity"]
        l2_diff = float(np.linalg.norm(scalars_seg - scalars_canon)) if np.isfinite(scalars_seg).all() else np.nan

        # Movement portion lost / added description
        if np.isnan(start_f_diff):
            loss_desc = "Entire repetition missed by segmenter."
        else:
            loss_desc = f"Lost initial {start_f_diff} frames ({start_ang_diff:+.1f}° flexion excursion); lost terminal {abs(end_f_diff)} frames ({end_ang_diff:+.1f}° extension return)."

        rows.append({
            "repetition_id": rid,
            "video_id": vid,
            "hand": hand,
            "ground_truth_label": label,
            "segmentation_status": seg_status,
            "canon_start_frame": a,
            "canon_end_frame": b,
            "canon_duration_sec": dur_canon,
            "seg_start_frame": seg_start_frame,
            "seg_end_frame": seg_end_frame,
            "seg_duration_sec": dur_seg,
            "start_frame_difference": start_f_diff,
            "end_frame_difference": end_f_diff,
            "duration_difference_sec": dur_diff,
            "canon_start_angle": feat_canon["active_start_angle"],
            "seg_start_angle": feat_seg.get("active_start_angle", np.nan),
            "start_angle_difference_deg": start_ang_diff,
            "canon_end_angle": feat_canon["active_end_angle"],
            "seg_end_angle": feat_seg.get("active_end_angle", np.nan),
            "end_angle_difference_deg": end_ang_diff,
            "canon_min_angle": feat_canon["active_min_angle"],
            "seg_min_angle": feat_seg.get("active_min_angle", np.nan),
            "min_angle_difference_deg": min_ang_diff,
            "canon_rom": feat_canon["active_rom"],
            "seg_rom": feat_seg.get("active_rom", np.nan),
            "rom_difference_deg": rom_diff,
            "canon_peak_velocity": feat_canon["active_peak_abs_velocity"],
            "seg_peak_velocity": feat_seg.get("active_peak_abs_velocity", np.nan),
            "peak_velocity_difference_deg_per_sec": peak_vel_diff,
            "feature_vector_l2_deviation": l2_diff,
            "movement_loss_analysis": loss_desc,
        })

    df_out = pd.DataFrame(rows)
    out_csv = PHASE5_DIR / "segmentation_error_analysis.csv"
    df_out.to_csv(out_csv, index=False)
    print(f"Saved segmentation error analysis ({len(df_out)} rows) to: {out_csv}")


if __name__ == "__main__":
    main()
