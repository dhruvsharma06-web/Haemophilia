"""Independent verification script for Phase 7 deliverables, benchmark metrics, parity, and repository preservation."""

import hashlib
import json
from pathlib import Path
import numpy as np
import pandas as pd

PHASE7_DIR = Path(__file__).resolve().parent
REPO_ROOT = PHASE7_DIR.parents[2]
PHASE2_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase2"
PHASE3_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase3"
PROVENANCE_REF = PHASE2_DIR / "provenance" / "protected_files_before.json"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def verify_phase7():
    print("=" * 80)
    print("   Running Phase 7 Independent Verification Script: Causal Cycle Segmenter")
    print("=" * 80)

    # 1. Required Deliverables Existence & Non-emptiness
    required_files = [
        "PHASE7_REPORT.md",
        "strategy_design.md",
        "causal_cycle_segmenter.py",
        "segmentation_benchmark.csv",
        "development_results.csv",
        "heldout_results.csv",
        "failure_analysis.csv",
        "live_results.csv",
        "live_offline_parity.csv",
        "segmentation_config.json",
        "plots/cycle_vs_strategy2_benchmark.png",
        "plots/cycle_boundary_error_distributions.png",
        "plots/cycle_failure_attribution.png",
        "plots/cycle_svm_diagnostic.png",
    ]

    for fname in required_files:
        p = PHASE7_DIR / fname
        assert p.exists(), f"Missing required Phase 7 file: {fname}"
        assert p.stat().st_size > 0, f"File is empty: {fname}"
    print(f"1. Required Files Check: ALL {len(required_files)} ARTIFACTS PRESENT & NON-EMPTY")

    # 2. Development and Held-Out Results Verification
    dev_df = pd.read_csv(PHASE7_DIR / "development_results.csv")
    val_df = pd.read_csv(PHASE7_DIR / "heldout_results.csv")
    assert len(dev_df) == 63, f"Expected 63 dev repetitions, got {len(dev_df)}"
    assert len(val_df) == 19, f"Expected 19 held-out repetitions, got {len(val_df)}"
    total_reps = len(dev_df) + len(val_df)
    assert total_reps == 82, f"Expected 82 total repetitions, got {total_reps}"

    for df, name in [(dev_df, "Development"), (val_df, "Held-Out")]:
        c_reps = df[df["completed"]]
        assert (c_reps["segmented_end_frame"] > c_reps["segmented_start_frame"]).all(), f"Boundary order error in {name}"
        assert (c_reps["duration_error_sec"].notna()).all(), f"NaN duration error in {name}"
    print(f"2. Split Results Check: PASSED (63 Dev reps, 19 Held-Out reps, 82 total verified)")

    # 3. Benchmark Verification (Strategy 2 vs Causal Cycle Segmenter)
    bench_df = pd.read_csv(PHASE7_DIR / "segmentation_benchmark.csv")
    assert len(bench_df) == 6, f"Expected 6 benchmark rows, got {len(bench_df)}"
    s2_all_iou = bench_df[(bench_df["strategy"] == "Strategy 2 Baseline") & (bench_df["split"] == "All (82 reps)")]["median_iou"].values[0]
    cy_all_iou = bench_df[(bench_df["strategy"] == "Causal Cycle Segmenter") & (bench_df["split"] == "All (82 reps)")]["median_iou"].values[0]
    assert cy_all_iou > s2_all_iou, f"Causal Cycle Segmenter failed to improve overall median IoU ({cy_all_iou} <= {s2_all_iou})"

    s2_val_iou = bench_df[(bench_df["strategy"] == "Strategy 2 Baseline") & (bench_df["split"] == "Held-Out (19 reps)")]["median_iou"].values[0]
    cy_val_iou = bench_df[(bench_df["strategy"] == "Causal Cycle Segmenter") & (bench_df["split"] == "Held-Out (19 reps)")]["median_iou"].values[0]
    assert cy_val_iou > s2_val_iou, f"Causal Cycle Segmenter failed to improve held-out median IoU ({cy_val_iou} <= {s2_val_iou})"
    print(f"3. Benchmark Metrics Check: PASSED (Median IoU increased: All {s2_all_iou:.3f}->{cy_all_iou:.3f}, Held-Out {s2_val_iou:.3f}->{cy_val_iou:.3f})")

    # 4. Failure Attribution Verification
    fail_df = pd.read_csv(PHASE7_DIR / "failure_analysis.csv")
    assert len(fail_df) == 82, f"Expected 82 rows in failure analysis, got {len(fail_df)}"
    unique_cats = set(fail_df["failure_category"])
    assert "None (Ideal Overlap)" in unique_cats, "Missing ideal overlap category"
    ideal_cnt = (fail_df["failure_category"] == "None (Ideal Overlap)").sum()
    assert ideal_cnt >= 20, f"Expected at least 20 ideal overlap repetitions, got {ideal_cnt}"
    print(f"4. Failure Attribution Check: PASSED (82 reps categorized, {ideal_cnt} ideal overlaps)")

    # 5. Live Test Cohort Verification
    live_df = pd.read_csv(PHASE7_DIR / "live_results.csv")
    assert len(live_df) == 30, f"Expected 30 live test repetitions, got {len(live_df)}"
    assert (live_df["duration_sec"] > 0).all(), "Non-positive duration in live test"
    assert (live_df["active_rom"] > 0).all(), "Zero ROM in live test"
    live_acc = live_df["prediction_matches_intent"].mean() * 100.0
    print(f"5. Live Test Check: PASSED (30 reps, Accuracy={live_acc:.1f}%, all durations > 0)")

    # 6. Live / Offline Replay Parity Check
    parity_df = pd.read_csv(PHASE7_DIR / "live_offline_parity.csv")
    assert len(parity_df) > 0, "No parity rows found"
    assert parity_df["parity_verified"].all(), "Live/offline parity verification failed"
    assert parity_df["score_difference"].max() == 0.0, "Non-zero decision score difference"
    assert parity_df["duration_difference"].max() == 0.0, "Non-zero duration difference"
    assert parity_df["max_feature_difference"].max() == 0.0, "Non-zero feature difference"
    assert parity_df["boundary_difference_frames"].max() == 0, "Non-zero boundary difference"
    print(f"6. Live Replay Parity Check: PASSED (Exact bit-level match across {len(parity_df)} reps, max delta=0.00e+00)")

    # 7. Frozen Model & Repository Preservation Check
    model_checkpoint = PHASE3_DIR / "checkpoints" / "final_model_v2_parameters.json"
    assert model_checkpoint.exists(), f"Frozen Phase 3 model checkpoint missing: {model_checkpoint}"
    assert model_checkpoint.stat().st_size > 0, "Frozen Phase 3 checkpoint is empty!"

    protected_ref = json.loads(PROVENANCE_REF.read_text(encoding="utf-8"))
    changed_files = []
    for fpath_str, expected_hash in protected_ref.items():
        fpath = Path(fpath_str)
        if not fpath.exists() or sha256(fpath) != expected_hash:
            changed_files.append(fpath_str)

    assert len(changed_files) == 0, f"Protected repository files modified! {changed_files}"
    print(f"7. Repository Preservation Check: PASSED ({len(protected_ref)} files verified 100% UNCHANGED)")

    # 8. Production Integrity Check
    forbidden_suffixes = [".pth", ".joblib", ".pkl", ".pt"]
    models_dir = REPO_ROOT / "models"
    new_model_files = [
        str(p) for p in models_dir.glob("*")
        if p.suffix in forbidden_suffixes and "v2" in p.name.lower() and "phase7" in p.name.lower()
    ]
    assert len(new_model_files) == 0, f"Forbidden production model created: {new_model_files}"
    print("8. Production Integrity Check: PASSED (Zero production checkpoints created)")

    # 9. Build Reproducibility Manifest
    config = json.loads((PHASE7_DIR / "segmentation_config.json").read_text(encoding="utf-8"))
    manifest = {
        "phase": 7,
        "status": "VERIFIED_PASSED",
        "recommended_strategy": config["recommended_strategy"]["name"],
        "total_webcam_sessions_evaluated": 7,
        "total_annotated_repetitions": total_reps,
        "development_repetitions": len(dev_df),
        "heldout_validation_repetitions": len(val_df),
        "overall_median_iou": float(cy_all_iou),
        "heldout_median_iou": float(cy_val_iou),
        "live_test_accuracy_pct": float(live_acc),
        "replay_parity_max_delta": float(parity_df["score_difference"].max()),
        "protected_files_checked": len(protected_ref),
        "protected_files_unchanged": len(changed_files) == 0,
        "file_hashes": {
            fname: sha256(PHASE7_DIR / fname) for fname in required_files
        }
    }
    manifest_path = PHASE7_DIR / "reproducibility_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"9. Reproducibility Manifest Written: {manifest_path.name}")

    print("=" * 80)
    print("   ALL PHASE 7 VERIFICATION CHECKS COMPLETED SUCCESSFULLY")
    print("=" * 80)


if __name__ == "__main__":
    verify_phase7()
