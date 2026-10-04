# Canonical Assisted Elbow Flexion V2 Phase 1

This independent research workspace uses only immutable release `human280_20261004`: 280 reviewed repetitions, binary quality target, source SHA-256 grouping. Read `reports/CODE_AUDIT.md`, `features/FEATURE_DEFINITIONS.md` and frozen `config.json` before running.

Use the recorded Python environment (`C:\Python310\python.exe`) and FFmpeg on PATH. From `C:\dev\Haemophilia`:

```powershell
# Initialization was completed once before extraction; never rerun it over this workspace.
# A clean reproduction needs a separate copy of the scripts/workspace with no outputs or protocol lock.
C:\Python310\python.exe research\assisted_elbow_flexion_v2\preprocessing\extract_landmarks.py
C:\Python310\python.exe research\assisted_elbow_flexion_v2\preprocessing\validate_raw.py
C:\Python310\python.exe research\assisted_elbow_flexion_v2\features\build_features.py
C:\Python310\python.exe research\assisted_elbow_flexion_v2\features\validate_features.py
C:\Python310\python.exe research\assisted_elbow_flexion_v2\baselines\benchmark.py classical
C:\Python310\python.exe research\assisted_elbow_flexion_v2\baselines\benchmark.py temporal
C:\Python310\python.exe research\assisted_elbow_flexion_v2\reports\verify_phase1.py
C:\Python310\python.exe research\assisted_elbow_flexion_v2\reports\build_report.py
```

Extraction resumes hash-verified fresh raw source caches. Model stages refuse to overwrite completed evaluations, preventing accidental retuning on inspected held-out folds. A clean reproduction runs `initialize.py` once before these stages and verifies the resulting config/fold hashes against the original protocol. Keep historical data and the canonical release outside the output workspace unchanged.

Outputs: raw original-frame image/world poses and decoder audits under `preprocessing`; physical-unit features, per-frame raw/repaired signals, model-ready arrays and distribution audits under `features`; immutable source folds under `splits`; predictions/fold/source/hand metrics under `baselines`; fold-only research models/scalers under `checkpoints`; final report and verification under `reports`.

The final feature version is `world_kinematics_v1_2`. Two QC-only preprocessing amendments were made before any model fitting: the internal interpolation cap became 0.50 seconds, then unsupported intervals in two remaining partial representations were preserved as NaN for training-fold mean imputation. Initial protocols and failure evidence remain under `provenance`; the final protocol/config are locked. The final representation has 278 fully supported and two partial repetitions; all 280 enter every model's grouped evaluation. Do not rerun the one-time amendment script over the completed workspace.

The final report is `reports/PHASE1_REPORT.md`. No production checkpoint, architecture search or integration is authorized. Stop after Phase 1.
