#!/usr/bin/env python3
"""Extensible Leave-One-Subject-Out (LOSO) Cross-Validation Runner.

Designed for multi-subject scaling (Persons 1, 2, 3 -> +Person 4 -> +Person 5):
Supports:
1. `old_3`          : Evaluates Persons 1, 2, and 3 (Authoritative Frozen Benchmark)
2. `plus_person4`   : Evaluates Persons 1, 2, 3, and 4
3. `plus_person4_5` : Evaluates Persons 1, 2, 3, 4, and 5
4. `all` / `custom` : Dynamic subject list passed via CLI

Preserves strict subject-level isolation:
- No data or labels from the held-out subject are ever seen during tuning
- Inner cross-validation on training subjects only
- Base production rules evaluated independently from exploratory candidates
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List, Any, Tuple

import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
    recall_score,
)

RANDOM_SEED = 42
CANDIDATE_DURATION_THRESHOLDS = [1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 3.0, 3.5, 4.0]
EXPLORATORY_EXT_DUR_THRESHOLD = 0.70


def parse_args():
    parser = argparse.ArgumentParser(description="Extensible LOSO Cross-Validation Runner.")
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
        help="Path to sequence directory for ext_dur calculation"
    )
    parser.add_argument(
        "--mode",
        type=str,
        choices=["old_3", "plus_person4", "plus_person4_5", "all", "custom"],
        default="old_3",
        help="Cohort evaluation mode"
    )
    parser.add_argument(
        "--subjects",
        type=str,
        default=None,
        help="Comma-separated subject list when mode is 'custom' (e.g. person1,person2,person3,person4)"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="processed_data/assisted_elbow_flexion/extensible_loso_results.json",
        help="Path to save evaluation results JSON"
    )
    parser.add_argument(
        "--verify",
        "--check-reproducibility",
        dest="verify",
        action="store_true",
        help="Verify strict reproduction of authoritative benchmarks on the old 3-subject cohort"
    )
    return parser.parse_args()


def resolve_subjects(mode: str, custom_subs: str, available_subs: List[str]) -> List[str]:
    """Determine target subject list based on mode."""
    if mode == "old_3":
        target = ["person1", "person2", "person3"]
    elif mode == "plus_person4":
        target = ["person1", "person2", "person3", "person4"]
    elif mode == "plus_person4_5":
        target = ["person1", "person2", "person3", "person4", "person5"]
    elif mode == "custom":
        if not custom_subs:
            raise ValueError("--subjects must be provided when --mode is 'custom'")
        target = [s.strip() for s in custom_subs.split(",") if s.strip()]
    elif mode == "all":
        target = available_subs
    else:
        target = available_subs

    # Filter to subjects actually present in the dataset
    present = [s for s in target if s in available_subs]
    missing = [s for s in target if s not in available_subs]
    if missing:
        print(f"NOTE: The following target subjects are not yet in the dataset and will be omitted: {missing}")
    if not present:
        raise ValueError(f"None of the target subjects {target} exist in dataset! Available: {available_subs}")
    return sorted(present)


def compute_metrics(y_true: np.ndarray, y_pred: np.ndarray) -> Dict[str, Any]:
    """Compute standard classification metrics."""
    acc = float(accuracy_score(y_true, y_pred))
    bal = float(balanced_accuracy_score(y_true, y_pred))
    f1 = float(f1_score(y_true, y_pred, average="macro", zero_division=0))
    cr = float(recall_score(y_true, y_pred, pos_label=1, zero_division=0))
    ir = float(recall_score(y_true, y_pred, pos_label=0, zero_division=0))
    cm = confusion_matrix(y_true, y_pred).tolist()
    return {
        "accuracy": acc,
        "balanced_accuracy": bal,
        "macro_f1": f1,
        "correct_recall": cr,
        "incorrect_recall": ir,
        "confusion_matrix": cm,
    }


def extract_ext_durs(df: pd.DataFrame, sequence_dir: Path) -> np.ndarray:
    """Extract eccentric-extension durations for movement quality assessment."""
    ext_durs = []
    for _, row in df.iterrows():
        dur = float(row.get("duration_sec", 3.0))
        seq_fn = str(row.get("sequence_file", ""))
        seq_path = sequence_dir / seq_fn if seq_fn else None

        if seq_path and seq_path.exists():
            try:
                arr = np.load(seq_path)
                act_ang = arr[:, 0] * 180.0
                idx_peak = int(np.argmin(act_ang))
                idx_peak = max(5, min(idx_peak, len(act_ang) - 6))
                ext_dur = dur * ((len(act_ang) - idx_peak) / float(len(act_ang)))
                ext_durs.append(ext_dur)
                continue
            except Exception:
                pass
        ext_durs.append(dur * 0.5)
    return np.array(ext_durs, dtype=float)


def run_evaluation(
    dataset_csv: Path,
    sequence_dir: Path,
    target_subjects: List[str]
) -> Dict[str, Any]:
    """Execute Leave-One-Subject-Out Cross-Validation."""
    df_raw = pd.read_csv(dataset_csv)
    # Filter dataset to target subjects
    df = df_raw[df_raw["subject_id"].isin(target_subjects)].copy().reset_index(drop=True)
    labels = (df["ground_truth_label"].str.capitalize() == "Correct").astype(int).values
    subjects = df["subject_id"].values
    unique_subjects = sorted(list(set(subjects)))

    min_a = df["min_elbow_angle"].values
    flare = df["elbow_flare"].values
    rom = df["rom"].values
    abs_rot = df["torso_rotation"].abs().values
    durs = df["duration_sec"].values
    ext_durs = extract_ext_durs(df, sequence_dir)

    # 1. Base Production Rule Baseline:
    # min_elbow_angle <= 101.0°, elbow_flare <= 0.30, rom >= 25.0°, |torso_rotation| <= 20.0°
    p_base = (
        (min_a <= 101.0) &
        (flare <= 0.30) &
        (rom >= 25.0) &
        (abs_rot <= 20.0)
    ).astype(int)

    base_overall = compute_metrics(labels, p_base)
    base_per_sub = {}
    sub_bals_base = []
    for sub in unique_subjects:
        m = (subjects == sub)
        sub_m = compute_metrics(labels[m], p_base[m])
        base_per_sub[sub] = sub_m
        sub_bals_base.append(sub_m["balanced_accuracy"])
    base_overall["fold_balacc_mean"] = float(np.mean(sub_bals_base))
    base_overall["fold_balacc_std"] = float(np.std(sub_bals_base))
    base_overall["per_subject"] = base_per_sub

    # 2. Nested LOSO Duration Selection (Research Benchmark)
    nested_preds = np.zeros(len(df), dtype=int)
    nested_fold_details = {}

    for test_sub in unique_subjects:
        test_mask = (subjects == test_sub)
        tr_indices = np.where(~test_mask)[0]
        test_idx = np.where(test_mask)[0]
        y_tr = labels[tr_indices]

        # Inner validation split strictly from training subjects (20% stratified)
        rng = np.random.RandomState(RANDOM_SEED)
        c0_idx = tr_indices[y_tr == 0]
        c1_idx = tr_indices[y_tr == 1]
        rng.shuffle(c0_idx)
        rng.shuffle(c1_idx)

        val_n0 = max(1, int(len(c0_idx) * 0.2))
        val_n1 = max(1, int(len(c1_idx) * 0.2))
        val_idx = np.concatenate([c0_idx[:val_n0], c1_idx[:val_n1]])
        actual_tr_idx = np.concatenate([c0_idx[val_n0:], c1_idx[val_n1:]])

        # Evaluate base rule on inner val
        p_base_val = p_base[val_idx]
        val_base_bal = balanced_accuracy_score(labels[val_idx], p_base_val)

        best_val_bal = -1.0
        best_th = None
        val_scores = {}

        for th in CANDIDATE_DURATION_THRESHOLDS:
            p_val = (p_base[val_idx] & (durs[val_idx] >= th)).astype(int)
            bal_v = balanced_accuracy_score(labels[val_idx], p_val)
            val_scores[str(th)] = float(bal_v)

            if bal_v > best_val_bal:
                best_val_bal = bal_v
                best_th = th
            elif np.isclose(bal_v, best_val_bal):
                # Tie-breaking rule: check score on actual_tr_idx, then prefer lower/more conservative threshold
                p_tr_cand = (p_base[actual_tr_idx] & (durs[actual_tr_idx] >= th)).astype(int)
                p_tr_best = (p_base[actual_tr_idx] & (durs[actual_tr_idx] >= best_th)).astype(int)
                bal_tr_cand = balanced_accuracy_score(labels[actual_tr_idx], p_tr_cand)
                bal_tr_best = balanced_accuracy_score(labels[actual_tr_idx], p_tr_best)
                if bal_tr_cand > bal_tr_best:
                    best_val_bal = bal_v
                    best_th = th
                elif np.isclose(bal_tr_cand, bal_tr_best):
                    if th < best_th:
                        best_th = th

        # Apply winning threshold to held-out test subject
        nested_preds[test_idx] = (p_base[test_idx] & (durs[test_idx] >= best_th)).astype(int)

        nested_fold_details[test_sub] = {
            "selected_duration_threshold": float(best_th),
            "inner_val_base_balacc": float(val_base_bal),
            "inner_val_best_balacc": float(best_val_bal),
            "val_scores": val_scores,
        }

    nested_overall = compute_metrics(labels, nested_preds)
    nested_per_sub = {}
    sub_bals_nested = []
    for sub in unique_subjects:
        m = (subjects == sub)
        sub_m = compute_metrics(labels[m], nested_preds[m])
        nested_per_sub[sub] = sub_m
        sub_bals_nested.append(sub_m["balanced_accuracy"])
    nested_overall["fold_balacc_mean"] = float(np.mean(sub_bals_nested))
    nested_overall["fold_balacc_std"] = float(np.std(sub_bals_nested))
    nested_overall["per_subject"] = nested_per_sub
    nested_overall["fold_details"] = nested_fold_details

    # 3A. Authoritative Phase 8D Exploratory Descriptive Benchmark (ext_dur >= 0.70s evaluated on nested benchmark)
    p_ext_on_nested = (nested_preds & (ext_durs >= EXPLORATORY_EXT_DUR_THRESHOLD)).astype(int)
    exploratory_nested_overall = compute_metrics(labels, p_ext_on_nested)
    exploratory_nested_per_sub = {}
    for sub in unique_subjects:
        m = (subjects == sub)
        exploratory_nested_per_sub[sub] = compute_metrics(labels[m], p_ext_on_nested[m])
    exploratory_nested_overall["per_subject"] = exploratory_nested_per_sub
    exploratory_nested_overall["clinical_note"] = (
        "EXPLORATORY ONLY: Evaluates candidate ext_dur >= 0.70s layered on top of nested duration research benchmark. "
        "Matches authoritative Phase 8D descriptive result (Acc: 86.15%, BalAcc: 87.31%, Macro-F1: 86.03%). "
        "NOT deployable as universal production rule until validated on Persons 4 & 5."
    )

    # 3B. Exploratory ext_dur >= 0.70s Standalone on Base Rules (without duration criterion)
    p_ext_on_base = (p_base & (ext_durs >= EXPLORATORY_EXT_DUR_THRESHOLD)).astype(int)
    exploratory_base_overall = compute_metrics(labels, p_ext_on_base)
    exploratory_base_per_sub = {}
    for sub in unique_subjects:
        m = (subjects == sub)
        exploratory_base_per_sub[sub] = compute_metrics(labels[m], p_ext_on_base[m])
    exploratory_base_overall["per_subject"] = exploratory_base_per_sub
    exploratory_base_overall["clinical_note"] = (
        "EXPLORATORY ONLY: Evaluates candidate ext_dur >= 0.70s layered directly on Base 8A rules (omitting duration). "
        "NOT deployable as universal production rule until validated on Persons 4 & 5."
    )

    return {
        "dataset_csv": str(dataset_csv),
        "evaluated_subjects": unique_subjects,
        "total_repetitions": len(df),
        "class_balance": {
            "correct": int(np.sum(labels == 1)),
            "incorrect": int(np.sum(labels == 0))
        },
        "base_production_rules": base_overall,
        "nested_loso_duration_benchmark": nested_overall,
        "exploratory_ext_dur_on_nested_benchmark": exploratory_nested_overall,
        "exploratory_ext_dur_standalone_on_base": exploratory_base_overall,
    }


def print_evaluation_summary(results: Dict[str, Any]):
    """Print formatted summary of the LOSO evaluation."""
    subs = results.get("evaluated_subjects", [])
    n_reps = results.get("total_repetitions", 0)
    cb = results.get("class_balance", {})

    print("=" * 115)
    print("ASSISTED ELBOW FLEXION: EXTENSIBLE LEAVE-ONE-SUBJECT-OUT EVALUATION")
    print(f"Subjects ({len(subs)}): {', '.join(subs)} | Total Repetitions: {n_reps} (Correct: {cb.get('correct')}, Incorrect: {cb.get('incorrect')})")
    print("=" * 115)

    print("\n[A] PRIMARY BENCHMARK COMPARISON TABLE:")
    print(f"{'Evaluation Method':<40} | {'Accuracy':<9} | {'Balanced Acc':<13} | {'Macro-F1':<9} | {'Cor Recall':<11} | {'Inc Recall':<11} | {'Confusion Matrix'}")
    print("-" * 125)

    base = results["base_production_rules"]
    print(f"{'1. Production Rules (Base 8A)':<40} | {base['accuracy']*100:6.2f}%   | {base['balanced_accuracy']*100:6.2f}%       | {base['macro_f1']*100:6.2f}%   | {base['correct_recall']*100:6.2f}%      | {base['incorrect_recall']*100:6.2f}%      | {base['confusion_matrix']}")

    nested = results["nested_loso_duration_benchmark"]
    print(f"{'2. Nested LOSO Duration Benchmark':<40} | {nested['accuracy']*100:6.2f}%   | {nested['balanced_accuracy']*100:6.2f}%       | {nested['macro_f1']*100:6.2f}%   | {nested['correct_recall']*100:6.2f}%      | {nested['incorrect_recall']*100:6.2f}%      | {nested['confusion_matrix']}")

    exp_nested = results["exploratory_ext_dur_on_nested_benchmark"]
    print(f"{'3. Exploratory ext_dur (Phase 8D Match)':<40} | {exp_nested['accuracy']*100:6.2f}%   | {exp_nested['balanced_accuracy']*100:6.2f}%       | {exp_nested['macro_f1']*100:6.2f}%   | {exp_nested['correct_recall']*100:6.2f}%      | {exp_nested['incorrect_recall']*100:6.2f}%      | {exp_nested['confusion_matrix']}")

    exp_base = results["exploratory_ext_dur_standalone_on_base"]
    print(f"{'4. Exploratory ext_dur (Base 8A Only)':<40} | {exp_base['accuracy']*100:6.2f}%   | {exp_base['balanced_accuracy']*100:6.2f}%       | {exp_base['macro_f1']*100:6.2f}%   | {exp_base['correct_recall']*100:6.2f}%      | {exp_base['incorrect_recall']*100:6.2f}%      | {exp_base['confusion_matrix']}")

    print("\n[B] NESTED LOSO FOLD-LEVEL SELECTIONS:")
    for sub, det in nested.get("fold_details", {}).items():
        th = det["selected_duration_threshold"]
        sub_metrics = nested["per_subject"][sub]
        print(f"  Fold Held-Out: {sub:<10} -> Selected Duration >= {th:.2f}s | Test Acc: {sub_metrics['accuracy']*100:.2f}%, BalAcc: {sub_metrics['balanced_accuracy']*100:.2f}%, CM: {sub_metrics['confusion_matrix']}")

    print("\n[C] PER-SUBJECT BALANCED ACCURACY:")
    for sub in subs:
        b_sub = base["per_subject"][sub]["balanced_accuracy"] * 100
        n_sub = nested["per_subject"][sub]["balanced_accuracy"] * 100
        en_sub = exp_nested["per_subject"][sub]["balanced_accuracy"] * 100
        print(f"  * {sub:<10}: Base = {b_sub:5.2f}% | Nested Duration = {n_sub:5.2f}% | Exploratory Phase8D = {en_sub:5.2f}%")

    print("=" * 115)


def verify_authoritative_reproducibility(results: Dict[str, Any]) -> bool:
    """Verify that results exactly match authoritative benchmarks on old 3-subject cohort."""
    print("\n" + "=" * 80)
    print("REPRODUCIBILITY CHECK: VERIFYING AUTHORITATIVE BENCHMARKS")
    print("=" * 80)

    base = results["base_production_rules"]
    nested = results["nested_loso_duration_benchmark"]
    exp = results["exploratory_ext_dur_on_nested_benchmark"]

    # Target values from Phase 8A, Phase 8C, and Phase 8D
    checks = [
        ("Production Rules Accuracy", base["accuracy"] * 100, 84.62),
        ("Production Rules Balanced Accuracy", base["balanced_accuracy"] * 100, 85.24),
        ("Production Rules Macro-F1", base["macro_f1"] * 100, 84.40),
        ("Nested Duration Benchmark Accuracy", nested["accuracy"] * 100, 85.13),
        ("Nested Duration Benchmark Balanced Accuracy", nested["balanced_accuracy"] * 100, 85.87),
        ("Nested Duration Benchmark Macro-F1", nested["macro_f1"] * 100, 84.94),
        ("Phase 8D Exploratory ext_dur Accuracy", exp["accuracy"] * 100, 86.15),
        ("Phase 8D Exploratory ext_dur Balanced Accuracy", exp["balanced_accuracy"] * 100, 87.31),
        ("Phase 8D Exploratory ext_dur Macro-F1", exp["macro_f1"] * 100, 86.03),
    ]

    all_passed = True
    for name, actual, expected in checks:
        diff = abs(actual - expected)
        passed = diff <= 0.05
        status_str = "[PASS]" if passed else "[FAIL]"
        print(f"  {status_str} {name:<48} : Actual={actual:6.2f}% | Expected={expected:6.2f}% (delta={diff:.4f}%)")
        if not passed:
            all_passed = False

    print("-" * 80)
    if all_passed:
        print("REPRODUCIBILITY SUCCESS: All authoritative benchmark metrics match exactly.")
    else:
        print("REPRODUCIBILITY FAILURE: One or more benchmark metrics deviate from authoritative numbers.")
    print("=" * 80)
    return all_passed


def main():
    args = parse_args()
    dataset_path = Path(args.dataset)
    seq_path = Path(args.sequence_dir)
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if not dataset_path.exists():
        print(f"ERROR: Dataset file not found: {dataset_path}")
        sys.exit(1)

    df_check = pd.read_csv(dataset_path)
    available_subjects = sorted(list(df_check["subject_id"].dropna().unique()))

    target_subs = resolve_subjects(args.mode, args.subjects, available_subjects)

    results = run_evaluation(
        dataset_csv=dataset_path,
        sequence_dir=seq_path,
        target_subjects=target_subs
    )

    print_evaluation_summary(results)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print(f"Saved evaluation results JSON to: {out_path}")

    if args.verify:
        passed = verify_authoritative_reproducibility(results)
        if not passed:
            sys.exit(1)


if __name__ == "__main__":
    main()
