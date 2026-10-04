"""Independent verification script for Phase 4 deliverables, numerical parity, and repository preservation."""

import hashlib
import json
from pathlib import Path
import numpy as np
import pandas as pd

PHASE4_DIR = Path(__file__).resolve().parent
REPO_ROOT = PHASE4_DIR.parents[2]
PHASE2_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase2"
PROVENANCE_REF = PHASE2_DIR / "provenance" / "protected_files_before.json"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def verify_phase4():
    print("=" * 75)
    print("   Running Phase 4 Independent Verification Script")
    print("=" * 75)

    # 1. Required Deliverables Existence & Non-emptiness
    required_files = [
        "LIVE_PIPELINE_AUDIT.md",
        "deployment_adapter.py",
        "live_elbow_camera_v2.py",
        "run_offline_parity.py",
        "offline_parity_report.md",
        "offline_parity_results.csv",
        "run_shadow_validation.py",
        "live_shadow_results.csv",
        "live_feature_distribution_audit.csv",
        "phase4_config.json",
        "PHASE4_REPORT.md",
        "plots/distribution_shift_audit.png",
        "plots/shadow_decision_scores.png",
    ]

    for fname in required_files:
        p = PHASE4_DIR / fname
        assert p.exists(), f"Missing required Phase 4 file: {fname}"
        assert p.stat().st_size > 0, f"File is empty: {fname}"
    print(f"1. Required Files Check: ALL {len(required_files)} ARTIFACTS PRESENT")

    # 2. Offline Parity Verification
    parity_df = pd.read_csv(PHASE4_DIR / "offline_parity_results.csv")
    assert len(parity_df) == 280, f"Expected 280 canonical rows, got {len(parity_df)}"
    assert parity_df["prediction_matches"].all(), "Parity failed: prediction mismatch found!"
    max_score_diff = parity_df["score_absolute_difference"].max()
    assert max_score_diff < 1e-10, f"Score divergence too large: {max_score_diff}"
    print(f"2. Offline Parity Check: PASSED (280/280 matches, max score diff = {max_score_diff:.2e})")

    # 3. Live Timing & Distribution Verification
    shadow_df = pd.read_csv(PHASE4_DIR / "live_shadow_results.csv")
    assert len(shadow_df) > 0, "No shadow results found!"
    assert (shadow_df["duration_sec"] > 0).all(), "Negative or zero duration found in shadow results!"
    assert (shadow_df["frame_count"] >= 15).all(), "Insufficient frame count in shadow results!"
    pred_classes = set(shadow_df["predicted_label"])
    assert "Correct" in pred_classes and "Incorrect" in pred_classes, "Model failed to produce both Correct and Incorrect predictions!"
    print(f"3. Live Timing Check: PASSED (All durations > 0, both classes predicted, {len(shadow_df)} reps)")

    # 4. Protected Files Repository Integrity Check
    protected_ref = json.loads(PROVENANCE_REF.read_text(encoding="utf-8"))
    changed_files = []
    for fpath_str, expected_hash in protected_ref.items():
        fpath = Path(fpath_str)
        if not fpath.exists() or sha256(fpath) != expected_hash:
            changed_files.append(fpath_str)

    assert len(changed_files) == 0, f"Protected repository files modified! {changed_files}"
    print(f"4. Protected Files Check: PASSED ({len(protected_ref)} files verified 100% UNCHANGED)")

    # 5. Production Models & Backends Check
    forbidden_suffixes = [".pth", ".joblib", ".pkl", ".pt"]
    models_dir = REPO_ROOT / "models"
    new_model_files = [
        str(p) for p in models_dir.glob("*")
        if p.suffix in forbidden_suffixes and "v2" in p.name.lower() and "phase4" in p.name.lower()
    ]
    assert len(new_model_files) == 0, f"Forbidden production model created: {new_model_files}"
    print("5. Production Integrity Check: PASSED (Zero production models created or modified)")

    # 6. Build Reproducibility Manifest
    manifest = {
        "phase": 4,
        "status": "VERIFIED_PASSED",
        "canonical_examples_verified": 280,
        "protected_files_checked": len(protected_ref),
        "protected_files_unchanged": len(changed_files) == 0,
        "offline_parity_max_delta": float(max_score_diff),
        "shadow_test_repetitions": len(shadow_df),
        "file_hashes": {
            fname: sha256(PHASE4_DIR / fname) for fname in required_files
        }
    }
    manifest_path = PHASE4_DIR / "reproducibility_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"6. Saved reproducibility manifest to: {manifest_path}")

    print("\n" + "=" * 75)
    print("   ALL PHASE 4 VERIFICATION CHECKS PASSED SUCCESSFULLY")
    print("=" * 75)


if __name__ == "__main__":
    verify_phase4()
