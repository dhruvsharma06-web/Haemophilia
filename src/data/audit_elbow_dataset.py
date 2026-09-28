#!/usr/bin/env python3
"""Automated Dataset Audit Suite for Assisted Elbow Flexion.

Performs rigorous dataset integrity checks before model training or evaluation:
1. Duplicate videos across subjects or folder paths
2. Duplicate repetitions within and across recordings
3. Repeated / frozen consecutive frames in feature sequences
4. Missing annotations (null/blank ground truth, annotator, timestamp)
5. Ambiguous repetitions requiring quarantine
6. Inconsistent labels (conflicts between ground truth and error tags)
7. NaN / Inf feature values in metadata CSV and sequence arrays
8. Segmentation anomalies (inverted frames, zero ROM, invalid duration)
9. Subject leakage across video names, sequence files, and subject boundaries

Also provides a `--dry-run` / `--intake-validation` mode for validating newly
ingested participant datasets (e.g. Persons 4 and 5) before integration.
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Any

import numpy as np
import pandas as pd

REQUIRED_INTAKE_COLUMNS = [
    "subject_id",
    "video_name",
    "repetition_index",
    "assistance_type",
    "ground_truth_label",
    "error_tags",
    "annotator",
    "timestamp",
    "notes",
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

SUBJECT_ID_PATTERN = re.compile(r"^person[0-9]+$")


def validate_intake_dry_run(
    dataset_csv: Path,
    sequence_dir: Path,
) -> Dict[str, Any]:
    """Execute strict dry-run intake validation for new datasets.
    
    Verifies:
    1. Required columns present
    2. Valid subject IDs (e.g. person1, person2, person3, person4, person5)
    3. No duplicate video / sequence identifiers
    4. Required annotation fields populated (ground_truth_label, annotator, timestamp)
    5. No ambiguous rows entering the clean supervised dataset
    6. No NaN/Inf values in numeric columns or sequence arrays
    7. Valid sequence files on disk with correct shape (128, 8)
    """
    intake_results: Dict[str, Any] = {
        "status": "PASSED",
        "mode": "dry_run_intake_validation",
        "dataset_file": str(dataset_csv),
        "total_records": 0,
        "subjects": [],
        "checks": {
            "required_columns": {"passed": True, "issues": []},
            "valid_subject_ids": {"passed": True, "issues": []},
            "no_duplicate_identifiers": {"passed": True, "issues": []},
            "required_annotation_fields": {"passed": True, "issues": []},
            "no_ambiguous_rows_in_clean_dataset": {"passed": True, "issues": []},
            "no_nan_inf_features": {"passed": True, "issues": []},
            "valid_sequence_files": {"passed": True, "issues": []},
        },
        "errors_count": 0,
    }

    if not dataset_csv.exists():
        intake_results["status"] = "FAILED"
        intake_results["checks"]["required_columns"]["passed"] = False
        intake_results["checks"]["required_columns"]["issues"].append(
            f"File not found: {dataset_csv}"
        )
        intake_results["errors_count"] += 1
        return intake_results

    df = pd.read_csv(dataset_csv)
    intake_results["total_records"] = len(df)

    # 1. Required Columns Check
    missing_cols = [c for c in REQUIRED_INTAKE_COLUMNS if c not in df.columns]
    if missing_cols:
        intake_results["checks"]["required_columns"]["passed"] = False
        intake_results["checks"]["required_columns"]["issues"].append(
            f"Missing required columns: {missing_cols}"
        )
        intake_results["errors_count"] += len(missing_cols)

    # 2. Valid Subject IDs Check
    if "subject_id" in df.columns:
        subjects = df["subject_id"].dropna().unique().tolist()
        intake_results["subjects"] = [str(s) for s in sorted(subjects)]
        for s in subjects:
            if not isinstance(s, str) or not SUBJECT_ID_PATTERN.match(str(s).strip()):
                intake_results["checks"]["valid_subject_ids"]["passed"] = False
                intake_results["checks"]["valid_subject_ids"]["issues"].append(
                    f"Invalid subject ID format: '{s}' (must match regex ^person[0-9]+$)"
                )
                intake_results["errors_count"] += 1
    else:
        intake_results["checks"]["valid_subject_ids"]["passed"] = False
        intake_results["checks"]["valid_subject_ids"]["issues"].append("Column 'subject_id' missing")
        intake_results["errors_count"] += 1

    # 3. No Duplicate Video / Sequence Identifiers
    # A: duplicate sequence_file
    if "sequence_file" in df.columns:
        seq_series = df["sequence_file"].dropna()
        dup_seqs = seq_series[seq_series.duplicated()].unique().tolist()
        if dup_seqs:
            intake_results["checks"]["no_duplicate_identifiers"]["passed"] = False
            intake_results["checks"]["no_duplicate_identifiers"]["issues"].append(
                f"Duplicate sequence_file entries detected: {dup_seqs}"
            )
            intake_results["errors_count"] += len(dup_seqs)

    # B: duplicate (video_name, repetition_index)
    if "video_name" in df.columns and "repetition_index" in df.columns:
        dup_reps = df[df.duplicated(subset=["video_name", "repetition_index"], keep=False)]
        if len(dup_reps) > 0:
            dup_keys = dup_reps[["video_name", "repetition_index"]].drop_duplicates().values.tolist()
            intake_results["checks"]["no_duplicate_identifiers"]["passed"] = False
            intake_results["checks"]["no_duplicate_identifiers"]["issues"].append(
                f"Duplicate (video_name, repetition_index) pairs: {dup_keys}"
            )
            intake_results["errors_count"] += len(dup_keys)

    # C: duplicate (video_name, start_frame, end_frame)
    if all(c in df.columns for c in ["video_name", "start_frame", "end_frame"]):
        dup_frames = df[df.duplicated(subset=["video_name", "start_frame", "end_frame"], keep=False)]
        if len(dup_frames) > 0:
            dup_frame_keys = dup_frames[["video_name", "start_frame", "end_frame"]].drop_duplicates().values.tolist()
            intake_results["checks"]["no_duplicate_identifiers"]["passed"] = False
            intake_results["checks"]["no_duplicate_identifiers"]["issues"].append(
                f"Identical frame boundaries on same video: {dup_frame_keys}"
            )
            intake_results["errors_count"] += len(dup_frame_keys)

    # 4. Required Annotation Fields Check
    annotation_cols = ["ground_truth_label", "annotator", "timestamp"]
    for col in annotation_cols:
        if col in df.columns:
            empty_mask = df[col].isna() | (df[col].astype(str).str.strip().str.lower().isin(["nan", "none", "null", ""]))
            if empty_mask.any():
                bad_idx = df[empty_mask].index.tolist()
                intake_results["checks"]["required_annotation_fields"]["passed"] = False
                intake_results["checks"]["required_annotation_fields"]["issues"].append(
                    f"Field '{col}' has {len(bad_idx)} empty or null rows: row indices {bad_idx[:5]}"
                )
                intake_results["errors_count"] += len(bad_idx)

    # 5. No Ambiguous Rows Entering Clean Supervised Dataset
    if "ground_truth_label" in df.columns:
        ambiguous_mask = df["ground_truth_label"].astype(str).str.strip().str.lower() == "ambiguous"
        if ambiguous_mask.any():
            amb_idx = df[ambiguous_mask].index.tolist()
            intake_results["checks"]["no_ambiguous_rows_in_clean_dataset"]["passed"] = False
            intake_results["checks"]["no_ambiguous_rows_in_clean_dataset"]["issues"].append(
                f"{len(amb_idx)} rows marked 'Ambiguous' found in clean dataset. "
                f"Ambiguous samples must be quarantined to unreviewed queue: row indices {amb_idx[:5]}"
            )
            intake_results["errors_count"] += len(amb_idx)

        # Check for invalid labels (not in Correct, Incorrect)
        valid_labels = {"correct", "incorrect"}
        all_labels = set(df["ground_truth_label"].dropna().astype(str).str.strip().str.lower())
        invalid_labels = all_labels - valid_labels
        if invalid_labels:
            intake_results["checks"]["no_ambiguous_rows_in_clean_dataset"]["passed"] = False
            intake_results["checks"]["no_ambiguous_rows_in_clean_dataset"]["issues"].append(
                f"Invalid ground truth label values found: {invalid_labels} (only 'Correct' or 'Incorrect' allowed)"
            )
            intake_results["errors_count"] += len(invalid_labels)

    # 6. No NaN/Inf Features Check
    numeric_check_cols = [
        "rom", "min_elbow_angle", "max_elbow_angle", "elbow_flare",
        "torso_tilt", "torso_rotation", "duration_sec", "smoothness"
    ]
    for col in numeric_check_cols:
        if col in df.columns:
            nan_mask = df[col].isna() | np.isinf(df[col].values)
            if nan_mask.any():
                bad_idx = df[nan_mask].index.tolist()
                intake_results["checks"]["no_nan_inf_features"]["passed"] = False
                intake_results["checks"]["no_nan_inf_features"]["issues"].append(
                    f"Column '{col}' contains {len(bad_idx)} NaN or Inf entries: rows {bad_idx[:5]}"
                )
                intake_results["errors_count"] += len(bad_idx)

    # 7. Valid Sequence Files Check
    if "sequence_file" in df.columns:
        seq_issues = []
        for idx, row in df.iterrows():
            seq_fn = str(row.get("sequence_file", ""))
            if not seq_fn or pd.isna(seq_fn):
                seq_issues.append(f"Row {idx}: missing sequence_file reference")
                continue
            seq_p = sequence_dir / seq_fn
            if not seq_p.exists():
                seq_issues.append(f"Row {idx}: sequence file does not exist: {seq_fn}")
                continue
            try:
                arr = np.load(seq_p)
                if arr.ndim != 2 or arr.shape[0] != 128 or arr.shape[1] < 8:
                    seq_issues.append(f"Row {idx}: invalid shape {arr.shape} in {seq_fn} (expected (128, 8))")
                elif np.isnan(arr).any() or np.isinf(arr).any():
                    seq_issues.append(f"Row {idx}: NaN/Inf in sequence array: {seq_fn}")
            except Exception as e:
                seq_issues.append(f"Row {idx}: failed loading array {seq_fn}: {str(e)}")

        if seq_issues:
            intake_results["checks"]["valid_sequence_files"]["passed"] = False
            intake_results["checks"]["valid_sequence_files"]["issues"] = seq_issues[:10]
            intake_results["errors_count"] += len(seq_issues)

    if intake_results["errors_count"] > 0:
        intake_results["status"] = "FAILED"

    return intake_results


def print_dry_run_report(results: Dict[str, Any]):
    """Format and print intake dry-run summary."""
    print("=" * 80)
    print("ASSISTED ELBOW FLEXION: DRY-RUN INTAKE VALIDATION REPORT")
    print(f"Target CSV: {results.get('dataset_file')}")
    print(f"Total Records: {results.get('total_records')} | Enrolled Subjects: {results.get('subjects')}")
    print(f"Intake Status: {results.get('status')} ({results.get('errors_count')} errors flagged)")
    print("=" * 80)

    for check_name, info in results.get("checks", {}).items():
        pass_str = "[PASS]" if info.get("passed", True) else "[FAIL]"
        formatted = check_name.replace("_", " ").title()
        print(f"  {pass_str:<7} {formatted:<38}")
        if not info.get("passed", True):
            for issue in info.get("issues", [])[:3]:
                print(f"         * {issue}")
            if len(info.get("issues", [])) > 3:
                print(f"         * ... and {len(info.get('issues', [])) - 3} more")

    print("-" * 80)
    if results.get("status") == "PASSED":
        print("DRY-RUN SUCCESS: Dataset satisfies 100% of schema, annotation, and integrity requirements.")
    else:
        print("DRY-RUN FAILED: Resolve highlighted issues before adding dataset to evaluation pipeline.")
    print("=" * 80)


def audit_dataset(
    dataset_csv: Path,
    sequence_dir: Path,
    freeze_frame_threshold: int = 5,
    verbose: bool = False,
) -> Dict[str, Any]:
    """Run comprehensive integrity audit on repetition dataset."""
    audit_results: Dict[str, Any] = {
        "status": "PASSED",
        "dataset_file": str(dataset_csv),
        "total_records": 0,
        "subjects_found": [],
        "checks": {
            "duplicate_videos": {"passed": True, "count": 0, "issues": []},
            "duplicate_repetitions": {"passed": True, "count": 0, "issues": []},
            "repeated_frames": {"passed": True, "count": 0, "issues": []},
            "missing_annotations": {"passed": True, "count": 0, "issues": []},
            "ambiguous_repetitions": {"passed": True, "count": 0, "issues": []},
            "inconsistent_labels": {"passed": True, "count": 0, "issues": []},
            "nan_inf_features": {"passed": True, "count": 0, "issues": []},
            "segmentation_failures": {"passed": True, "count": 0, "issues": []},
            "subject_leakage": {"passed": True, "count": 0, "issues": []},
        },
        "summary": {}
    }

    if not dataset_csv.exists():
        audit_results["status"] = "FAILED"
        audit_results["error"] = f"Dataset file does not exist: {dataset_csv}"
        return audit_results

    df = pd.read_csv(dataset_csv)
    audit_results["total_records"] = len(df)
    subjects = sorted(list(df["subject_id"].dropna().unique()))
    audit_results["subjects_found"] = subjects

    # 1. Duplicate Videos check (same video assigned to different subjects)
    video_to_sub: Dict[str, set] = {}
    for _, row in df.iterrows():
        v = str(row.get("video_name", ""))
        s = str(row.get("subject_id", ""))
        if v not in video_to_sub:
            video_to_sub[v] = set()
        video_to_sub[v].add(s)

    for v, sub_set in video_to_sub.items():
        if len(sub_set) > 1:
            audit_results["checks"]["duplicate_videos"]["passed"] = False
            audit_results["checks"]["duplicate_videos"]["count"] += 1
            audit_results["checks"]["duplicate_videos"]["issues"].append({
                "video_name": v,
                "conflicting_subjects": list(sub_set)
            })

    # 2. Duplicate Repetitions check
    # A: duplicate (video_name, repetition_index)
    rep_counts = df.groupby(["video_name", "repetition_index"]).size()
    dup_reps = rep_counts[rep_counts > 1]
    for (v, r_idx), count in dup_reps.items():
        audit_results["checks"]["duplicate_repetitions"]["passed"] = False
        audit_results["checks"]["duplicate_repetitions"]["count"] += 1
        audit_results["checks"]["duplicate_repetitions"]["issues"].append({
            "video_name": str(v),
            "repetition_index": int(r_idx),
            "occurrences": int(count),
            "type": "duplicate_video_rep_id"
        })

    # B: duplicate (video_name, start_frame, end_frame)
    if "start_frame" in df.columns and "end_frame" in df.columns:
        frame_counts = df.groupby(["video_name", "start_frame", "end_frame"]).size()
        dup_frames = frame_counts[frame_counts > 1]
        for (v, sf, ef), count in dup_frames.items():
            audit_results["checks"]["duplicate_repetitions"]["passed"] = False
            audit_results["checks"]["duplicate_repetitions"]["count"] += 1
            audit_results["checks"]["duplicate_repetitions"]["issues"].append({
                "video_name": str(v),
                "start_frame": int(sf),
                "end_frame": int(ef),
                "occurrences": int(count),
                "type": "identical_frame_boundary"
            })

    # 3. Repeated / Frozen Frames Check in Sequence Files
    if sequence_dir.exists() and "sequence_file" in df.columns:
        for idx, row in df.iterrows():
            seq_fn = str(row.get("sequence_file", ""))
            if not seq_fn or pd.isna(seq_fn):
                continue
            seq_path = sequence_dir / seq_fn
            if not seq_path.exists():
                audit_results["checks"]["repeated_frames"]["passed"] = False
                audit_results["checks"]["repeated_frames"]["count"] += 1
                audit_results["checks"]["repeated_frames"]["issues"].append({
                    "row_index": int(idx),
                    "sequence_file": seq_fn,
                    "error": "Sequence file missing on disk"
                })
                continue

            try:
                arr = np.load(seq_path)
                if arr.ndim != 2 or arr.shape[1] < 1:
                    continue
                # Calculate consecutive frame differences
                diffs = np.linalg.norm(np.diff(arr, axis=0), axis=1)
                frozen_streaks = 0
                max_frozen = 0
                for d in diffs:
                    if np.isclose(d, 0.0, atol=1e-6):
                        frozen_streaks += 1
                        max_frozen = max(max_frozen, frozen_streaks)
                    else:
                        frozen_streaks = 0

                if max_frozen >= freeze_frame_threshold:
                    audit_results["checks"]["repeated_frames"]["passed"] = False
                    audit_results["checks"]["repeated_frames"]["count"] += 1
                    audit_results["checks"]["repeated_frames"]["issues"].append({
                        "row_index": int(idx),
                        "video_name": str(row.get("video_name", "")),
                        "repetition_index": int(row.get("repetition_index", 0)),
                        "sequence_file": seq_fn,
                        "consecutive_identical_frames": int(max_frozen)
                    })
            except Exception as e:
                audit_results["checks"]["repeated_frames"]["passed"] = False
                audit_results["checks"]["repeated_frames"]["count"] += 1
                audit_results["checks"]["repeated_frames"]["issues"].append({
                    "sequence_file": seq_fn,
                    "error": f"Failed loading array: {str(e)}"
                })

    # 4. Missing Annotations Check
    for idx, row in df.iterrows():
        gt = str(row.get("ground_truth_label", "")).strip()
        annotator = str(row.get("annotator", "")).strip()
        ts = str(row.get("timestamp", "")).strip()

        missing_fields = []
        if not gt or gt.lower() in ["nan", "none", "null", ""]:
            missing_fields.append("ground_truth_label")
        if not annotator or annotator.lower() in ["nan", "none", "null", ""]:
            missing_fields.append("annotator")
        if not ts or ts.lower() in ["nan", "none", "null", ""]:
            missing_fields.append("timestamp")

        if missing_fields:
            audit_results["checks"]["missing_annotations"]["passed"] = False
            audit_results["checks"]["missing_annotations"]["count"] += 1
            audit_results["checks"]["missing_annotations"]["issues"].append({
                "row_index": int(idx),
                "video_name": str(row.get("video_name", "")),
                "repetition_index": int(row.get("repetition_index", 0)),
                "missing_fields": missing_fields
            })

    # 5. Ambiguous Repetitions Check
    for idx, row in df.iterrows():
        gt = str(row.get("ground_truth_label", "")).strip()
        notes = str(row.get("notes", "")).lower()
        if gt.lower() == "ambiguous" or "occlusion" in notes or "tracking failure" in notes:
            audit_results["checks"]["ambiguous_repetitions"]["count"] += 1
            audit_results["checks"]["ambiguous_repetitions"]["issues"].append({
                "row_index": int(idx),
                "video_name": str(row.get("video_name", "")),
                "repetition_index": int(row.get("repetition_index", 0)),
                "label": gt,
                "notes": str(row.get("notes", ""))
            })
    # Ambiguous repetitions are flagged as warnings/counts (must be excluded from clean sets)
    if audit_results["checks"]["ambiguous_repetitions"]["count"] > 0:
        audit_results["checks"]["ambiguous_repetitions"]["passed"] = False

    # 6. Inconsistent Labels Check
    severe_error_keywords = [
        "insufficient_flexion", "excessive_elbow_flare", "torso_rotation",
        "rapid_drop", "poor_control", "rapid_eccentric_drop", "insufficient_rom"
    ]
    for idx, row in df.iterrows():
        gt = str(row.get("ground_truth_label", "")).strip().capitalize()
        tags = str(row.get("error_tags", "")).strip()
        notes = str(row.get("notes", "")).strip()

        # Inconsistency A: Label is 'Correct' but error tags specify severe failure
        if gt == "Correct" and tags and tags.lower() not in ["nan", "none", ""]:
            if any(k in tags.lower() for k in severe_error_keywords):
                audit_results["checks"]["inconsistent_labels"]["passed"] = False
                audit_results["checks"]["inconsistent_labels"]["count"] += 1
                audit_results["checks"]["inconsistent_labels"]["issues"].append({
                    "row_index": int(idx),
                    "video_name": str(row.get("video_name", "")),
                    "repetition_index": int(row.get("repetition_index", 0)),
                    "ground_truth_label": gt,
                    "conflicting_error_tags": tags,
                    "type": "correct_with_severe_error_tags"
                })

        # Inconsistency B: Label is 'Incorrect' but has no error tag and no note
        if gt == "Incorrect":
            tags_empty = not tags or tags.lower() in ["nan", "none", ""]
            notes_empty = not notes or notes.lower() in ["nan", "none", ""]
            if tags_empty and notes_empty:
                audit_results["checks"]["inconsistent_labels"]["passed"] = False
                audit_results["checks"]["inconsistent_labels"]["count"] += 1
                audit_results["checks"]["inconsistent_labels"]["issues"].append({
                    "row_index": int(idx),
                    "video_name": str(row.get("video_name", "")),
                    "repetition_index": int(row.get("repetition_index", 0)),
                    "ground_truth_label": gt,
                    "type": "incorrect_without_error_tags_or_notes"
                })

    # 7. NaN / Inf Features Check
    numeric_cols = [
        "rom", "min_elbow_angle", "max_elbow_angle", "elbow_flare",
        "torso_tilt", "torso_rotation", "duration_sec", "smoothness"
    ]
    for idx, row in df.iterrows():
        nan_cols = []
        for col in numeric_cols:
            if col in df.columns:
                val = row.get(col)
                if pd.isna(val) or np.isinf(val):
                    nan_cols.append(col)
        if nan_cols:
            audit_results["checks"]["nan_inf_features"]["passed"] = False
            audit_results["checks"]["nan_inf_features"]["count"] += 1
            audit_results["checks"]["nan_inf_features"]["issues"].append({
                "row_index": int(idx),
                "video_name": str(row.get("video_name", "")),
                "repetition_index": int(row.get("repetition_index", 0)),
                "nan_columns": nan_cols
            })

    # Also check sequence arrays for NaNs/Infs
    if sequence_dir.exists() and "sequence_file" in df.columns:
        for idx, row in df.iterrows():
            seq_fn = str(row.get("sequence_file", ""))
            if not seq_fn or pd.isna(seq_fn):
                continue
            seq_path = sequence_dir / seq_fn
            if seq_path.exists():
                arr = np.load(seq_path)
                if np.isnan(arr).any() or np.isinf(arr).any():
                    audit_results["checks"]["nan_inf_features"]["passed"] = False
                    audit_results["checks"]["nan_inf_features"]["count"] += 1
                    audit_results["checks"]["nan_inf_features"]["issues"].append({
                        "sequence_file": seq_fn,
                        "type": "nan_inf_in_sequence_array"
                    })

    # 8. Segmentation Failures Check
    for idx, row in df.iterrows():
        sf = row.get("start_frame")
        ef = row.get("end_frame")
        dur = row.get("duration_sec")
        rom = row.get("rom")

        seg_issues = []
        if pd.notna(sf) and pd.notna(ef) and ef <= sf:
            seg_issues.append(f"Inverted frames (start={sf}, end={ef})")
        if pd.notna(dur) and (dur <= 0.4 or dur > 20.0):
            seg_issues.append(f"Unrealistic duration ({dur:.2f}s)")
        if pd.notna(rom) and rom <= 0.0:
            seg_issues.append(f"Zero or negative ROM ({rom:.1f}°)")

        if seg_issues:
            audit_results["checks"]["segmentation_failures"]["passed"] = False
            audit_results["checks"]["segmentation_failures"]["count"] += 1
            audit_results["checks"]["segmentation_failures"]["issues"].append({
                "row_index": int(idx),
                "video_name": str(row.get("video_name", "")),
                "repetition_index": int(row.get("repetition_index", 0)),
                "segmentation_anomalies": seg_issues
            })

    # 9. Subject Leakage Check
    # Check if any sequence file contains references to multiple subjects
    seq_to_sub: Dict[str, set] = {}
    for _, row in df.iterrows():
        seq_fn = str(row.get("sequence_file", ""))
        sub = str(row.get("subject_id", ""))
        if seq_fn and pd.notna(seq_fn):
            if seq_fn not in seq_to_sub:
                seq_to_sub[seq_fn] = set()
            seq_to_sub[seq_fn].add(sub)

    for seq_fn, sub_set in seq_to_sub.items():
        if len(sub_set) > 1:
            audit_results["checks"]["subject_leakage"]["passed"] = False
            audit_results["checks"]["subject_leakage"]["count"] += 1
            audit_results["checks"]["subject_leakage"]["issues"].append({
                "sequence_file": seq_fn,
                "shared_across_subjects": list(sub_set)
            })

    # Overall Status Computation (ambiguous samples are flagged, but non-blocking if clean dataset is filtered)
    blocking_checks = [
        "duplicate_videos", "duplicate_repetitions", "repeated_frames",
        "missing_annotations", "inconsistent_labels", "nan_inf_features",
        "segmentation_failures", "subject_leakage"
    ]
    has_blocking_failure = any(not audit_results["checks"][c]["passed"] for c in blocking_checks)
    audit_results["status"] = "FAILED" if has_blocking_failure else "PASSED"

    audit_results["summary"] = {
        "total_records": len(df),
        "subjects": subjects,
        "blocking_failures": [c for c in blocking_checks if not audit_results["checks"][c]["passed"]],
        "warning_checks": ["ambiguous_repetitions"] if not audit_results["checks"]["ambiguous_repetitions"]["passed"] else []
    }

    return audit_results


def print_audit_report(results: Dict[str, Any]):
    """Format and print an executive audit summary to console."""
    print("=" * 80)
    print("ASSISTED ELBOW FLEXION: AUTOMATED DATASET AUDIT REPORT")
    print(f"Target: {results.get('dataset_file')}")
    print(f"Total Records: {results.get('total_records')} | Subjects: {results.get('subjects_found')}")
    print(f"Overall Audit Status: {results.get('status')}")
    print("=" * 80)

    for check_name, info in results.get("checks", {}).items():
        pass_str = "[PASS]" if info.get("passed", True) else "[FAIL]"
        count = info.get("count", 0)
        formatted_name = check_name.replace("_", " ").title()
        print(f"  {pass_str:<7} {formatted_name:<28} : {count} issue(s) flagged")
        if not info.get("passed", True) and info.get("issues"):
            for issue in info["issues"][:3]:  # Print first 3
                print(f"         * {issue}")
            if len(info["issues"]) > 3:
                print(f"         * ... and {len(info['issues']) - 3} more")

    print("-" * 80)
    summary = results.get("summary", {})
    if results.get("status") == "PASSED":
        print("AUDIT SUCCESS: Dataset satisfies all zero-leakage and integrity constraints.")
    else:
        print(f"AUDIT WARNING: Found failures in: {summary.get('blocking_failures')}")
    print("=" * 80)


def main():
    parser = argparse.ArgumentParser(description="Automated dataset audit for Assisted Elbow Flexion.")
    parser.add_argument(
        "--dataset",
        type=str,
        default="data/clean_elbow_train_expanded.csv",
        help="Path to repetition dataset CSV"
    )
    parser.add_argument(
        "--sequence-dir",
        type=str,
        default="processed_data/assisted_elbow_flexion/sequences",
        help="Path to sequence files directory"
    )
    parser.add_argument(
        "--freeze-thresh",
        type=int,
        default=5,
        help="Threshold of consecutive identical frames to flag as repeated frames"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="processed_data/assisted_elbow_flexion/dataset_audit_report.json",
        help="Output JSON destination"
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit with non-zero status code if any blocking check fails"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Execute strict dry-run intake validation mode for new datasets"
    )
    args = parser.parse_args()

    dataset_path = Path(args.dataset)
    seq_path = Path(args.sequence_dir)
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if args.dry_run:
        intake_res = validate_intake_dry_run(
            dataset_csv=dataset_path,
            sequence_dir=seq_path
        )
        print_dry_run_report(intake_res)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(intake_res, f, indent=2)
        print(f"Saved intake dry-run report to: {out_path}")
        if intake_res.get("status") != "PASSED":
            sys.exit(1)
        return

    results = audit_dataset(
        dataset_csv=dataset_path,
        sequence_dir=seq_path,
        freeze_frame_threshold=args.freeze_thresh,
    )

    print_audit_report(results)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print(f"Saved audit JSON report to: {out_path}")

    if args.strict and results.get("status") != "PASSED":
        sys.exit(1)


if __name__ == "__main__":
    main()
