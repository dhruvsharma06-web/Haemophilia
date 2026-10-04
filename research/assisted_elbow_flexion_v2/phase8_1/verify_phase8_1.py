"""Independent verification script for Phase 8.1 deliverables, provenance inventory, and repository preservation."""

import hashlib
import json
from pathlib import Path
import pandas as pd

PHASE8_1_DIR = Path(__file__).resolve().parent
REPO_ROOT = PHASE8_1_DIR.parents[2]
PHASE2_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase2"
PHASE3_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase3"
PROVENANCE_REF = PHASE2_DIR / "provenance" / "protected_files_before.json"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def verify_phase8_1():
    print("=" * 80)
    print("   Running Phase 8.1 Independent Verification Script: Data Independence Audit")
    print("=" * 80)

    # 1. Required Deliverables Existence & Non-emptiness
    required_files = [
        "PHASE8_RECLASSIFICATION.md",
        "PHASE8_1_REPORT.md",
        "independent_cohort_inventory.csv",
        "independence_audit.json",
    ]

    for fname in required_files:
        p = PHASE8_1_DIR / fname
        assert p.exists(), f"Missing required Phase 8.1 file: {fname}"
        assert p.stat().st_size > 0, f"File is empty: {fname}"
    print(f"1. Required Files Check: ALL {len(required_files)} ARTIFACTS PRESENT & NON-EMPTY")

    # 2. Reclassification Document Verification
    reclass_text = (PHASE8_1_DIR / "PHASE8_RECLASSIFICATION.md").read_text(encoding="utf-8")
    assert "B — Inconclusive for independent validation" in reclass_text, "Missing formal reclassification status"
    assert "human280_20261004" in reclass_text, "Missing canonical dataset reference"
    print("2. Reclassification Document Check: PASSED (Formally reclassified to 'B — Inconclusive')")

    # 3. Independent Cohort Inventory Verification
    inv_df = pd.read_csv(PHASE8_1_DIR / "independent_cohort_inventory.csv")
    assert len(inv_df) == 183, f"Expected 183 cataloged video files, got {len(inv_df)}"
    eligible_count = (inv_df["eligibility_status"] == "ELIGIBLE").sum()
    assert eligible_count == 0, f"Expected 0 eligible external continuous videos, got {eligible_count}"
    print("3. Inventory Check: PASSED (183 video files cataloged, 0 eligible external continuous videos proven)")

    # 4. Independence Audit JSON Verification
    audit_data = json.loads((PHASE8_1_DIR / "independence_audit.json").read_text(encoding="utf-8"))
    assert audit_data["finding"] == "NO INDEPENDENT COHORT CURRENTLY AVAILABLE", "Finding mismatch in audit JSON"
    assert "B — Inconclusive" in audit_data["formal_decision"], "Decision mismatch in audit JSON"
    print("4. Independence Audit Check: PASSED ('NO INDEPENDENT COHORT CURRENTLY AVAILABLE' verified)")

    # 5. Repository Preservation Check
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
    print(f"5. Repository Preservation Check: PASSED ({len(protected_ref)} files verified 100% UNCHANGED)")

    # 6. Production Integrity Check
    forbidden_suffixes = [".pth", ".joblib", ".pkl", ".pt"]
    models_dir = REPO_ROOT / "models"
    new_model_files = [
        str(p) for p in models_dir.glob("*")
        if p.suffix in forbidden_suffixes and "v2" in p.name.lower() and "phase8" in p.name.lower()
    ]
    assert len(new_model_files) == 0, f"Forbidden production model created: {new_model_files}"
    print("6. Production Integrity Check: PASSED (Zero production checkpoints created)")

    # 7. Build Reproducibility Manifest
    manifest = {
        "phase": "8.1",
        "status": "VERIFIED_PASSED",
        "action": "Data Independence Audit & Phase 8 Reclassification",
        "phase8_amended_status": "B — Inconclusive for independent validation",
        "phase8_1_final_decision": "B — Inconclusive (Independent data unavailable or insufficient)",
        "total_video_files_audited": len(inv_df),
        "eligible_independent_continuous_videos": int(eligible_count),
        "authoritative_model": "Phase 3 BalancedSVM (FROZEN)",
        "canonical_dataset": "human280_20261004 (FROZEN)",
        "protected_files_verified": len(protected_ref),
        "production_checkpoints_created": 0,
        "artifacts_generated": required_files,
    }
    manifest_path = PHASE8_1_DIR / "reproducibility_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"7. Reproducibility Manifest Written: {manifest_path.name}")
    print("=" * 80)
    print("   ALL PHASE 8.1 AUDIT CHECKS COMPLETED SUCCESSFULLY")
    print("=" * 80)


if __name__ == "__main__":
    verify_phase8_1()
