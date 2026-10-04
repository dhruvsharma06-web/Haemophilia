# Assisted Elbow Flexion V2 — canonical dataset approval report

Release: **human280_20261004**. Date: **4 October 2026** (Asia/Calcutta).

**Dataset finalization PASSED: 280 authoritative human-reviewed examples retained.** This finalizes dataset membership and annotation provenance; it does not authorize model training. No training, feature selection, architecture experiment, feature engineering, or production modification was performed.

## Canonical membership and target

| Measure | Count |
| --- | --- |
| Original candidate ranges | 302 |
| Current manually reviewed decisions | 280 |
| Final canonical supervised examples | 280 |
| Unreviewed candidates excluded | 22 |
| Reviewed examples excluded for structural problems | 0 |
| Correct | 183 |
| Incorrect | 97 |
| Left | 143 |
| Right | 137 |

| Arm being exercised | Correct | Incorrect | Total |
| --- | --- | --- | --- |
| Left | 95 | 48 | 143 |
| Right | 88 | 49 | 137 |
| Total | 183 | 97 | 280 |

The supervised target is exactly **Correct vs Incorrect** (`label`). Hand is metadata only. The four folder combinations are storage groups, not four classes. No balancing was performed.

## Human review authority and administrative fields

Authoritative export: `aef_v2_review_2026-10-04T14-18-12-118Z.json`, preserved byte-for-byte in `evidence/`. SHA-256: `44b233be34340ff48f45013f0d75c6d0d90eb8ac731b678f4794f1529c2b1e11`.

The user's explicit confirmation of these 280 hand/label decisions is preserved in `evidence/user_finalization_instructions.txt`. Every record matches one unique candidate ID, video ID and immutable source SHA-256; original and reviewed frame ranges are both recorded. All hand/label decisions and all exported frame endpoints match the source review JSON exactly. No rule-generated label was promoted and no reviewer identity was invented.

All 280 reviewer names are blank; subject checkbox is false for 279 records and true for 1; boundary checkbox is false for 277 and true for 3; new-repetition flag is false for all 280. These exact values are retained. They are **not exclusion criteria** and do not override the user's authoritative quality/hand decisions. An isolated subject checkbox does not establish a cross-video participant identity map; inherited subject IDs remain appropriately described as unverified.

## Reconciliation with trusted historical human annotations

- **134** reviewed IDs have trusted prior manual quality evidence. There are **0 quality-label disagreements** on candidate lineage.
- **2 additional exact-source/range rematches** connect revised candidate ranges to a different old candidate ID; both old/new labels agree (`Correct`). They are recorded as provenance links, not additional examples.
- **9 prior provisional hand assignments differ** from the current hand decisions. Those old assignments were assistant-inferred metadata, not human-reviewed hand labels. Every difference is listed in `audit/prior_provisional_hand_differences.csv`, including old and new frame ranges; some reflect the user's retiming of candidate IDs to different physical cycles.
- Full old/new audit paths, old CSV row numbers, old evidence hashes, original reviewers/timestamps, and new JSON pointers are preserved in `audit/historical_label_reconciliation.csv`. `audit/historical_label_conflicts.csv` is an explicitly empty, header-only conflict table.
- Where a reviewed range changed, its old label comparison is a **lineage comparison**, not a claim that both labels covered identical frames. New explicit review is always authoritative. Old rule/folder-derived decisions were not treated as historical human evidence.

## Frame provenance and shared-boundary adjudication

The user changed **104 frame ranges** in the review export. The canonical manifest preserves every edit verbatim; original candidate bounds remain in `original_start_frame`/`original_end_frame`. `audit/frame_range_revisions.csv` records every change and its review JSON pointer. **No additional assistant frame repairs or trims were applied.** Historical candidate indices are retained as provenance and should not be interpreted as newly verified chronological repetition numbering after retiming.

Every reviewed range has valid zero-based inclusive bounds within the decoded source and a positive presentation-timestamp duration. Source frame counts and source/proxy timestamp mappings are reused only after verifying original video hashes against the prior audited inventory. Both source and review provenance are retained.

The original **252** shared-endpoint pairs reconcile as follows:

| Original pair disposition | Pairs |
| --- | --- |
| Retained with one inclusive endpoint shared | 171 |
| Retained with transition overlap after human retiming | 4 |
| No longer overlap after human range revisions | 47 |
| One member not in the current review; that candidate remains excluded | 27 |
| Both members absent from current review; both remain excluded | 3 |
| Total | 252 |

Thus **175 original shared-boundary pairs remain**, **47 were resolved by the user's edits**, and **30 pair relationships are absent because they involve unreviewed candidates**. No reviewed repetition was excluded on this basis. Human retiming introduces **4 additional overlap pairs**, giving **179 current pairs: 174 single-frame endpoints + 5 transition overlaps**.

The 174 single endpoints are retained as inclusive-boundary sharing between distinct reviewed examples, not treated as duplicate complete repetitions. This adjudication uses the user's completed repetition review plus range arithmetic; it is not a claim that the assistant re-watched all 174 boundaries. The five longer overlaps were separately inspected in sampled context frames, with evidence images retained:

| video | frames | shared | disposition |
| --- | --- | --- | --- |
| 20260825_120853.mp4 | 2990-3000 | 11 | Shared frames show lowered left arm at the end of A, followed by release and preparation of the right arm for B. Separate flexion cycles; retain transition padding. |
| 20260825_135545.mp4 | 780-800 | 21 | Shared frames show return of the right arm and hand repositioning before the next left-arm flexion. Separate cycles; retain transition padding. |
| 20260910_150357.mp4 | 748-770 | 23 | Shared frames show the right arm lowered between distinct flexion peaks. Retain common turnaround/extension context. |
| 20260910_150438.mp4 | 844-850 | 7 | Shared frames show the lowered arm at the turnaround between distinct movements. Retain common transition context. |
| 20260825_121007.mp4 | 560-600 | 41 | Shared interval includes late lowering from A before a lowered-arm pause and the distinct next flexion in B. It does not duplicate the flexion core. Retain with previous-cycle-tail-context note; clips remain source-grouped. |

The fifth overlap contains late lowering from the previous movement, not just a static neutral frame. It is explicitly retained as previous-cycle tail context: the two flexion cores are distinct, both examples were manually reviewed, and shared frames remain in the same source validation group. The four other cases show lowered-arm/turnaround or arm-switch transitions. None duplicates a complete movement. No hidden trimming is used to manufacture disjoint ranges.

The earlier suspected merged ranges in `20260825_135545` and `20260825_135917` were revised in the human export (496–798 became 496–640; 1572–1896 became 1572–1740). Their successor IDs also carry explicit reviewed ranges. The apparent stopping/non-cycle range `rep_19da0e3948c0931a74` is among the 22 unreviewed exclusions. These facts supersede the initial intake's blanket boundary hold without changing the historical intake files.

## Per-subject counts

These are **inherited grouping IDs, not independently verified participant identities**. They remain useful descriptive metadata without invalidating the reviewed labels.

| subject_id | total | Correct | Incorrect | Left | Right | Left_Correct | Left_Incorrect | Right_Correct | Right_Incorrect |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| person1 | 59 | 39 | 20 | 29 | 30 | 21 | 8 | 18 | 12 |
| person2 | 70 | 44 | 26 | 35 | 35 | 21 | 14 | 23 | 12 |
| person3 | 52 | 36 | 16 | 25 | 27 | 18 | 7 | 18 | 9 |
| person4 | 60 | 44 | 16 | 34 | 26 | 25 | 9 | 19 | 7 |
| person5 | 39 | 20 | 19 | 20 | 19 | 10 | 10 | 10 | 9 |

## Per-video counts

| video | total | Correct | Incorrect | Left | Right | Left_Correct | Left_Incorrect | Right_Correct | Right_Incorrect |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 20260825_120853.mp4 | 14 | 14 | 0 | 7 | 7 | 7 | 0 | 7 | 0 |
| 20260825_135545.mp4 | 12 | 12 | 0 | 5 | 7 | 5 | 0 | 7 | 0 |
| 20260825_121230.mp4 | 13 | 7 | 6 | 6 | 7 | 4 | 2 | 3 | 4 |
| 20260825_135917.mp4 | 14 | 7 | 7 | 7 | 7 | 4 | 3 | 3 | 4 |
| VID20260825125415.mp4 | 12 | 12 | 0 | 6 | 6 | 6 | 0 | 6 | 0 |
| VID20260825125816.mp4 | 8 | 4 | 4 | 4 | 4 | 2 | 2 | 2 | 2 |
| 20260910_144241.mp4 | 9 | 9 | 0 | 7 | 2 | 7 | 0 | 2 | 0 |
| 20260910_144325.mp4 | 11 | 11 | 0 | 5 | 6 | 5 | 0 | 6 | 0 |
| 20260910_144405.mp4 | 12 | 12 | 0 | 6 | 6 | 6 | 0 | 6 | 0 |
| 20260910_144448.mp4 | 10 | 10 | 0 | 5 | 5 | 5 | 0 | 5 | 0 |
| 20260910_150515.mp4 | 7 | 7 | 0 | 3 | 4 | 3 | 0 | 4 | 0 |
| 20260910_150539.mp4 | 6 | 6 | 0 | 3 | 3 | 3 | 0 | 3 | 0 |
| 20260910_150602.mp4 | 7 | 7 | 0 | 4 | 3 | 4 | 0 | 3 | 0 |
| 20260910_144115.mp4 | 8 | 2 | 6 | 5 | 3 | 2 | 3 | 0 | 3 |
| 20260910_144154.mp4 | 10 | 0 | 10 | 6 | 4 | 0 | 6 | 0 | 4 |
| 20260910_150357.mp4 | 11 | 0 | 11 | 6 | 5 | 0 | 6 | 0 | 5 |
| 20260910_150438.mp4 | 8 | 0 | 8 | 4 | 4 | 0 | 4 | 0 | 4 |
| 20260825_120754.mp4 | 10 | 10 | 0 | 10 | 0 | 10 | 0 | 0 | 0 |
| 20260825_135508.mp4 | 10 | 10 | 0 | 10 | 0 | 10 | 0 | 0 | 0 |
| VID20260825125333.mp4 | 10 | 10 | 0 | 10 | 0 | 10 | 0 | 0 | 0 |
| 20260825_121059.mp4 | 6 | 0 | 6 | 6 | 0 | 0 | 6 | 0 | 0 |
| 20260825_135701.mp4 | 13 | 2 | 11 | 13 | 0 | 2 | 11 | 0 | 0 |
| VID20260825125720.mp4 | 5 | 0 | 5 | 5 | 0 | 0 | 5 | 0 | 0 |
| 20260825_120703.mp4 | 8 | 8 | 0 | 0 | 8 | 0 | 0 | 8 | 0 |
| 20260825_135423.mp4 | 13 | 13 | 0 | 0 | 13 | 0 | 0 | 13 | 0 |
| VID20260825125257.mp4 | 10 | 10 | 0 | 0 | 10 | 0 | 0 | 10 | 0 |
| 20260825_121007.mp4 | 8 | 0 | 8 | 0 | 8 | 0 | 0 | 0 | 8 |
| 20260825_135633.mp4 | 8 | 0 | 8 | 0 | 8 | 0 | 0 | 0 | 8 |
| VID20260825125647.mp4 | 7 | 0 | 7 | 0 | 7 | 0 | 0 | 0 | 7 |

## All excluded candidates

Each of these 22 IDs is absent from the authoritative review. Current supervised hand/label fields are left blank; no old or inferred label is promoted. All have reason `not_reviewed_in_current_human_review` and are prohibited from training, supervised validation, feature selection, calibration, augmentation and any supervised experiment unless separately reviewed and explicitly approved later.

| repetition_id | video | frames | reason |
| --- | --- | --- | --- |
| rep_a50caba1b30632132e | 20260825_120703.mp4 | 336-464 | not_reviewed_in_current_human_review |
| rep_0b135d94919765ba55 | 20260825_120703.mp4 | 1616-1814 | not_reviewed_in_current_human_review |
| rep_409193d34aefb813d4 | 20260825_120703.mp4 | 2096-2184 | not_reviewed_in_current_human_review |
| rep_bc1fd36f25173f6e33 | 20260825_120703.mp4 | 2604-2758 | not_reviewed_in_current_human_review |
| rep_8b080db6d298e45fa2 | 20260825_121007.mp4 | 436-560 | not_reviewed_in_current_human_review |
| rep_1f9c8b1933493f8aad | 20260825_121007.mp4 | 856-1078 | not_reviewed_in_current_human_review |
| rep_2c54e8aa18e1e05c58 | 20260825_121007.mp4 | 1078-1246 | not_reviewed_in_current_human_review |
| rep_26a043c99e5d6a87ee | 20260825_121007.mp4 | 1392-1514 | not_reviewed_in_current_human_review |
| rep_6d6c5c575a89de65bb | 20260825_121007.mp4 | 1514-1684 | not_reviewed_in_current_human_review |
| rep_cac0d9fbb1bee389bc | 20260825_121007.mp4 | 2290-2348 | not_reviewed_in_current_human_review |
| rep_37ad9c5d6437dd59ab | 20260825_121007.mp4 | 2348-2470 | not_reviewed_in_current_human_review |
| rep_60b1cedae181775f91 | 20260825_121007.mp4 | 2648-2708 | not_reviewed_in_current_human_review |
| rep_d172d6fb43d2d89039 | 20260825_121059.mp4 | 336-470 | not_reviewed_in_current_human_review |
| rep_5a0f951c5faa74946c | 20260825_121059.mp4 | 1310-1370 | not_reviewed_in_current_human_review |
| rep_00a92ff62a94153bbf | 20260825_121059.mp4 | 1894-1992 | not_reviewed_in_current_human_review |
| rep_6d16ac3bbfd9f57aea | 20260825_121059.mp4 | 2408-2500 | not_reviewed_in_current_human_review |
| rep_fc9628ef544928d170 | 20260910_144154.mp4 | 364-600 | not_reviewed_in_current_human_review |
| rep_7114055409e6341911 | 20260910_150357.mp4 | 158-342 | not_reviewed_in_current_human_review |
| rep_19da0e3948c0931a74 | VID20260825125415.mp4 | 1116-1159 | not_reviewed_in_current_human_review |
| rep_ca9a7d6adf90f9cde8 | VID20260825125647.mp4 | 692-739 | not_reviewed_in_current_human_review |
| rep_1cdc0449410c0c6fd2 | VID20260825125720.mp4 | 264-337 | not_reviewed_in_current_human_review |
| rep_8e5f2fbf2b0c4650c6 | VID20260825125720.mp4 | 569-610 | not_reviewed_in_current_human_review |

Some revised approved ranges overlap portions of old excluded ranges: **23 range relationships** are recorded in `audit/canonical_vs_excluded_range_overlap.csv`. Exclusion operates on the unreviewed candidate records, not a blanket ban on every raw frame they formerly referenced. Only the explicitly reviewed current ranges are canonical; the 22 old candidate representations are never appended or used as separate examples, and none of their historical labels is used.

## Structural, representation and leakage audit

| Check | Result |
| --- | --- |
| Duplicate canonical IDs | 0 |
| Duplicate current source/frame ranges | 0 |
| Duplicate complete decoded-range content hashes | 0 |
| Missing/invalid binary quality labels | 0 |
| Missing/invalid Left/Right hand values | 0 |
| Invalid frame bounds or nonpositive durations | 0 |
| Source SHA/video/review membership mismatches | 0 |
| Historical normalized representations checked | 280 |
| Representations with NaN/Inf | 0 |
| Duplicate historical representation file groups | 0 |
| Source video groups | 29 |
| Train/test or validation splits created | 0 |
| Raw landmark validation | Not performed; raw landmarks unavailable |

Full-resolution decoded-frame hash evidence from the prior audit is used to recompute hashes for the **revised** current ranges, after raw source hashes are checked. Exact hashes do not rule out transformed/recompressed near-duplicates. Existing normalized arrays were checked for finite values, shape and file identity; these checks do not validate raw landmarks or imply new feature approval.

**104 historical representations have stale frame ranges for this release.** All 280 old arrays remain historical-only rather than approved canonical model inputs: even unchanged ranges need hand/canonicalization semantics checked before a future approved processing phase. No new features were engineered or extracted and no feature arrays were copied into the four label folders.

**277 current IDs have historical training-export lineage; 178 current ranges exactly match a historical training-export range**, including retimed IDs that now match another old range. This is dataset-version reuse, not independent data. The release includes exactly one row per approved current ID, with no appended historical samples. The old 153-record dataset and other historical exports must not be concatenated as extra data or used as independent held-out tests against this release.

No split exists, so absence of observed cross-split leakage is not a future validation guarantee. `source_sha256` is the immutable source group and must remain together across every split. `load_canonical.py` includes a source-group split checker that rejects one source spanning folds. Once supported subject identity evidence exists, all sources belonging to the same verified subject must remain in the same fold. Current person1–person5 metadata does not itself establish that identity evidence.

Descriptive Cramer's V: hand/label **0.0231**, inherited subject/label **0.1421**, source-video/label **0.9011**. These are descriptive associations, not independent-sample significance claims. Source-level label association is flagged when V >= 0.5; source-grouped validation is essential because many recordings predominantly contain one quality label. No balancing or feature selection was performed.

## Release organization, validation and remaining uncertainty

Canonical entry points:

- `canonical_manifest.csv`: exactly 280 reviewed source-range records.
- `CANONICAL_CONTRACT.json`: immutable membership allowlist, binary target, exact review/manifest hashes, 22-ID exclusion list and future-use policy.
- `Assisted Elbow Flexion V2/Left Hand Assisted/Correct`, `/Incorrect`, and corresponding Right folders: 280 source-range JSON descriptors in the requested logical organization. They reference original videos and frame ranges; no duplicate raw videos are created.
- `excluded_candidates.csv` and `excluded_provenance/`: the separate 22 exclusions.
- `dataset_summary.json`, `per_subject_counts.csv`, `per_video_counts.csv`, `audit/`, `analysis/`, `evidence/`: distributions, audit outcomes, visual evidence and immutable original review/instructions.
- V2-root `CURRENT_CANONICAL_RELEASE.json` and `CANONICAL_DATASET_POLICY.md`: route future work to this release, not the initial 302-row intake or old checkbox-gated importer.

Remaining limitations are inherited subject identity verification, limited precision/transition context of repetition boundaries, lack of raw-landmark evidence and lack of a current aligned processed feature release. These limitations are disclosed without downgrading or silently excluding the 280 authoritative human hand/label decisions. No claim is made that this is a feature-ready or clinically validated model dataset.

The canonical loader and **11 integrity tests passed**, covering exact membership, preserving reviewed labels/hands/ranges, accepting blank/default administrative fields, rejecting unreviewed/extra historical IDs and four-class targets, and rejecting source-video leakage. Tests create no model and train nothing.

Protected pre-existing files: **1687** hashed before and after; **0 changed**, **0 missing**. Pre-existing Git status unchanged: **True**. All files created by this task are listed in `FILES_CREATED.txt` and checksummed in `release_file_hashes.json`. No pre-existing file was modified, including initial V2 history, raw videos, historical datasets, Flutter/frontend/backend/live/production code, or checkpoints.

**Stop condition reached: finalized dataset, manifest and approval report produced. No model training or experiments are authorized or performed. Await explicit approval of the new training phase.**
