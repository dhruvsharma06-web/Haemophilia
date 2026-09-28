#!/usr/bin/env python3
"""Automated Dataset Summary Reporter for Assisted Elbow Flexion.

Generates comprehensive demographic, kinematic, and movement-quality distribution
reports across all enrolled subjects (including Persons 4 and 5 when added):
- Repetitions per subject
- Class balance (Correct vs Incorrect) per subject and overall
- Assistance mode distribution
- Error tag frequency breakdown
- Biomechanical metric distributions:
  * Range of Motion (ROM)
  * Peak Active Elbow Flare
  * Transverse Torso Rotation (|torso_rotation|)
  * Repetition Duration (duration_sec)
  * Eccentric-Extension Duration (ext_dur)
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List, Any, Optional

import numpy as np
import pandas as pd


def compute_distribution_stats(values: np.ndarray) -> Dict[str, float]:
    """Calculate mean, std, median, min, max, Q1, Q3 for a numeric array."""
    if len(values) == 0:
        return {
            "count": 0, "mean": 0.0, "std": 0.0, "median": 0.0,
            "min": 0.0, "max": 0.0, "q25": 0.0, "q75": 0.0
        }
    val = np.asarray(values, dtype=float)
    return {
        "count": int(len(val)),
        "mean": float(np.mean(val)),
        "std": float(np.std(val)),
        "median": float(np.median(val)),
        "min": float(np.min(val)),
        "max": float(np.max(val)),
        "q25": float(np.percentile(val, 25)),
        "q75": float(np.percentile(val, 75))
    }


def extract_eccentric_durations(df: pd.DataFrame, sequence_dir: Path) -> np.ndarray:
    """Extract eccentric-extension durations from sequence files."""
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
        # Fallback approximation (50% of duration) if sequence unavailable
        ext_durs.append(dur * 0.5)
    return np.array(ext_durs, dtype=float)


def generate_dataset_report(
    dataset_csv: Path,
    sequence_dir: Path
) -> Dict[str, Any]:
    """Generate structured summary dictionary of the dataset."""
    df = pd.read_csv(dataset_csv)
    subjects = sorted(list(df["subject_id"].dropna().unique()))

    # Calculate ext_dur
    ext_durations = extract_eccentric_durations(df, sequence_dir)
    df["ext_dur"] = ext_durations

    report: Dict[str, Any] = {
        "dataset_file": str(dataset_csv),
        "total_repetitions": len(df),
        "total_subjects": len(subjects),
        "subjects": subjects,
        "per_subject_summary": {},
        "assistance_type_distribution": {},
        "error_tag_distribution": {},
        "kinematic_distributions": {
            "overall": {},
            "by_label": {},
            "by_subject": {}
        }
    }

    # 1. Per-subject summary (reps, balance)
    for sub in subjects:
        sub_df = df[df["subject_id"] == sub]
        n_tot = len(sub_df)
        n_cor = int((sub_df["ground_truth_label"].str.capitalize() == "Correct").sum())
        n_inc = int((sub_df["ground_truth_label"].str.capitalize() == "Incorrect").sum())
        n_amb = int((sub_df["ground_truth_label"].str.capitalize() == "Ambiguous").sum())

        report["per_subject_summary"][sub] = {
            "total_reps": n_tot,
            "correct_reps": n_cor,
            "incorrect_reps": n_inc,
            "ambiguous_reps": n_amb,
            "correct_pct": round(n_cor / n_tot * 100, 2) if n_tot > 0 else 0.0,
            "incorrect_pct": round(n_inc / n_tot * 100, 2) if n_tot > 0 else 0.0,
        }

    # Overall class balance
    n_cor_all = int((df["ground_truth_label"].str.capitalize() == "Correct").sum())
    n_inc_all = int((df["ground_truth_label"].str.capitalize() == "Incorrect").sum())
    report["overall_class_balance"] = {
        "correct": n_cor_all,
        "incorrect": n_inc_all,
        "correct_pct": round(n_cor_all / len(df) * 100, 2) if len(df) > 0 else 0.0,
        "incorrect_pct": round(n_inc_all / len(df) * 100, 2) if len(df) > 0 else 0.0,
    }

    # 2. Assistance-type distribution
    assist_counts = df["assistance_type"].value_counts().to_dict()
    for atype, cnt in assist_counts.items():
        report["assistance_type_distribution"][str(atype)] = {
            "count": int(cnt),
            "percentage": round(cnt / len(df) * 100, 2)
        }

    # 3. Error-tag distribution
    tag_counts: Dict[str, int] = {}
    for _, row in df.iterrows():
        tags = str(row.get("error_tags", "")).strip()
        if tags and tags.lower() not in ["nan", "none", ""]:
            # split on comma or semicolon
            split_tags = [t.strip() for t in tags.replace(";", ",").split(",") if t.strip()]
            for t in split_tags:
                tag_counts[t] = tag_counts.get(t, 0) + 1

    sorted_tags = sorted(tag_counts.items(), key=lambda x: x[1], reverse=True)
    report["error_tag_distribution"] = {k: v for k, v in sorted_tags}

    # 4. Kinematic distributions (ROM, Flare, Torso Rotation, Duration, Eccentric Duration)
    metrics = {
        "rom": df["rom"].dropna().values,
        "elbow_flare": df["elbow_flare"].dropna().values,
        "torso_rotation": df["torso_rotation"].abs().dropna().values,
        "duration_sec": df["duration_sec"].dropna().values,
        "ext_dur": df["ext_dur"].dropna().values,
    }

    for m_name, vals in metrics.items():
        report["kinematic_distributions"]["overall"][m_name] = compute_distribution_stats(vals)

    # By label
    for label in ["Correct", "Incorrect"]:
        sub_m = df[df["ground_truth_label"].str.capitalize() == label]
        report["kinematic_distributions"]["by_label"][label] = {
            "rom": compute_distribution_stats(sub_m["rom"].dropna().values),
            "elbow_flare": compute_distribution_stats(sub_m["elbow_flare"].dropna().values),
            "torso_rotation": compute_distribution_stats(sub_m["torso_rotation"].abs().dropna().values),
            "duration_sec": compute_distribution_stats(sub_m["duration_sec"].dropna().values),
            "ext_dur": compute_distribution_stats(sub_m["ext_dur"].dropna().values),
        }

    # By subject
    for sub in subjects:
        sub_m = df[df["subject_id"] == sub]
        report["kinematic_distributions"]["by_subject"][sub] = {
            "rom": compute_distribution_stats(sub_m["rom"].dropna().values),
            "elbow_flare": compute_distribution_stats(sub_m["elbow_flare"].dropna().values),
            "torso_rotation": compute_distribution_stats(sub_m["torso_rotation"].abs().dropna().values),
            "duration_sec": compute_distribution_stats(sub_m["duration_sec"].dropna().values),
            "ext_dur": compute_distribution_stats(sub_m["ext_dur"].dropna().values),
        }

    return report


def format_markdown_report(report: Dict[str, Any]) -> str:
    """Format report dictionary into publication-ready GitHub markdown."""
    lines = [
        "# Assisted Elbow Flexion: Dataset Demographic & Kinematic Summary",
        "",
        f"- **Dataset File**: `{report.get('dataset_file')}`",
        f"- **Total Human-Verified Repetitions**: {report.get('total_repetitions')}",
        f"- **Enrolled Subjects ({report.get('total_subjects')})**: {', '.join(report.get('subjects', []))}",
        "",
        "---",
        "",
        "## 1. Subject Cohort & Class Balance",
        "",
        "| Subject ID | Total Reps | Correct | Incorrect | Ambiguous | Class Balance (Cor / Inc) |",
        "| :--- | :---: | :---: | :---: | :---: | :---: |"
    ]

    for sub, info in report.get("per_subject_summary", {}).items():
        lines.append(
            f"| **{sub}** | {info['total_reps']} | {info['correct_reps']} | {info['incorrect_reps']} | "
            f"{info['ambiguous_reps']} | {info['correct_pct']}% / {info['incorrect_pct']}% |"
        )
    oc = report.get("overall_class_balance", {})
    lines.append(
        f"| **OVERALL** | **{report.get('total_repetitions')}** | **{oc.get('correct')}** | **{oc.get('incorrect')}** | "
        f"0 | **{oc.get('correct_pct')}% / {oc.get('incorrect_pct')}%** |"
    )

    lines.extend([
        "",
        "---",
        "",
        "## 2. Assistance Mode Distribution",
        "",
        "| Assistance Mode | Repetitions | Percentage |",
        "| :--- | :---: | :---: |"
    ])
    for atype, info in report.get("assistance_type_distribution", {}).items():
        lines.append(f"| `{atype}` | {info['count']} | {info['percentage']}% |")

    lines.extend([
        "",
        "---",
        "",
        "## 3. Human-Verified Error Tag Frequency",
        "",
        "| Error Tag | Frequency | Percentage of Incorrect Reps |",
        "| :--- | :---: | :---: |"
    ])
    n_inc = report.get("overall_class_balance", {}).get("incorrect", 1)
    for tag, count in report.get("error_tag_distribution", {}).items():
        pct = round(count / n_inc * 100, 1)
        lines.append(f"| `{tag}` | {count} | {pct}% |")

    lines.extend([
        "",
        "---",
        "",
        "## 4. Biomechanical Feature Distributions",
        "",
        "### A. Overall Cohort Distributions",
        "",
        "| Metric | Mean ± Std | Median | Q1 (25%) | Q3 (75%) | Min – Max |",
        "| :--- | :---: | :---: | :---: | :---: | :---: |"
    ])

    metric_names = [
        ("rom", "ROM (deg)"),
        ("elbow_flare", "Elbow Flare (W_ref)"),
        ("torso_rotation", "|Torso Rotation| (deg)"),
        ("duration_sec", "Duration (sec)"),
        ("ext_dur", "Eccentric Duration (sec)")
    ]

    for key, display in metric_names:
        stats = report["kinematic_distributions"]["overall"].get(key, {})
        m_s = f"{stats.get('mean', 0.0):.2f} ± {stats.get('std', 0.0):.2f}"
        med = f"{stats.get('median', 0.0):.2f}"
        q1 = f"{stats.get('q25', 0.0):.2f}"
        q3 = f"{stats.get('q75', 0.0):.2f}"
        rng = f"{stats.get('min', 0.0):.2f} – {stats.get('max', 0.0):.2f}"
        lines.append(f"| **{display}** | {m_s} | {med} | {q1} | {q3} | {rng} |")

    lines.extend([
        "",
        "### B. Correct vs Incorrect Biomechanical Distributions",
        "",
        "| Metric | Correct (Mean ± Std) | Correct Median | Incorrect (Mean ± Std) | Incorrect Median |",
        "| :--- | :---: | :---: | :---: | :---: |"
    ])
    for key, display in metric_names:
        c_stats = report["kinematic_distributions"]["by_label"].get("Correct", {}).get(key, {})
        i_stats = report["kinematic_distributions"]["by_label"].get("Incorrect", {}).get(key, {})
        c_ms = f"{c_stats.get('mean', 0.0):.2f} ± {c_stats.get('std', 0.0):.2f}"
        c_med = f"{c_stats.get('median', 0.0):.2f}"
        i_ms = f"{i_stats.get('mean', 0.0):.2f} ± {i_stats.get('std', 0.0):.2f}"
        i_med = f"{i_stats.get('median', 0.0):.2f}"
        lines.append(f"| **{display}** | {c_ms} | {c_med} | {i_ms} | {i_med} |")

    lines.extend([
        "",
        "### C. Per-Subject Kinematic Median Breakdown",
        "",
        "| Subject | Reps | ROM Median | Flare Median | |Rotation| Median | Duration Median | Ext Dur Median |",
        "| :--- | :---: | :---: | :---: | :---: | :---: | :---: |"
    ])
    for sub in report.get("subjects", []):
        s_stats = report["kinematic_distributions"]["by_subject"].get(sub, {})
        s_reps = report["per_subject_summary"].get(sub, {}).get("total_reps", 0)
        lines.append(
            f"| **{sub}** | {s_reps} | {s_stats.get('rom', {}).get('median', 0.0):.1f}° | "
            f"{s_stats.get('elbow_flare', {}).get('median', 0.0):.3f} | "
            f"{s_stats.get('torso_rotation', {}).get('median', 0.0):.1f}° | "
            f"{s_stats.get('duration_sec', {}).get('median', 0.0):.2f}s | "
            f"{s_stats.get('ext_dur', {}).get('median', 0.0):.2f}s |"
        )

    return "\n".join(lines)


def print_console_summary(report: Dict[str, Any]):
    """Print ASCII summary table to stdout."""
    print("=" * 80)
    print("ASSISTED ELBOW FLEXION: AUTOMATED DATASET SUMMARY REPORT")
    print(f"Dataset: {report.get('dataset_file')}")
    print(f"Total Repetitions: {report.get('total_repetitions')} across {report.get('total_subjects')} subjects: {report.get('subjects')}")
    print("=" * 80)

    print("\n[1] SUBJECT REPETITION & CLASS BALANCE:")
    print(f"{'Subject':<12} | {'Total':<6} | {'Correct':<8} | {'Incorrect':<10} | {'Balance (Cor/Inc)':<18}")
    print("-" * 65)
    for sub, info in report.get("per_subject_summary", {}).items():
        bal_str = f"{info['correct_pct']}% / {info['incorrect_pct']}%"
        print(f"{sub:<12} | {info['total_reps']:<6} | {info['correct_reps']:<8} | {info['incorrect_reps']:<10} | {bal_str:<18}")
    oc = report.get("overall_class_balance", {})
    all_bal = f"{oc.get('correct_pct')}% / {oc.get('incorrect_pct')}%"
    print("-" * 65)
    print(f"{'OVERALL':<12} | {report.get('total_repetitions'):<6} | {oc.get('correct'):<8} | {oc.get('incorrect'):<10} | {all_bal:<18}")

    print("\n[2] ASSISTANCE MODE BREAKDOWN:")
    for atype, info in report.get("assistance_type_distribution", {}).items():
        print(f"  * {atype:<24}: {info['count']:>3} reps ({info['percentage']:>5.1f}%)")

    print("\n[3] ERROR TAG FREQUENCY:")
    for tag, cnt in list(report.get("error_tag_distribution", {}).items())[:8]:
        print(f"  * {tag:<30}: {cnt:>3} reps")

    print("\n[4] KEY BIOMECHANICAL DISTRIBUTIONS:")
    print(f"{'Metric':<25} | {'Mean ± Std':<18} | {'Median':<8} | {'Q1 - Q3':<14} | {'Range':<14}")
    print("-" * 85)
    metrics_list = [
        ("rom", "ROM (deg)"),
        ("elbow_flare", "Elbow Flare (W_ref)"),
        ("torso_rotation", "|Torso Rotation| (deg)"),
        ("duration_sec", "Duration (sec)"),
        ("ext_dur", "Eccentric Duration (sec)")
    ]
    for key, display in metrics_list:
        st = report["kinematic_distributions"]["overall"].get(key, {})
        m_s = f"{st.get('mean', 0.0):.2f} ± {st.get('std', 0.0):.2f}"
        med = f"{st.get('median', 0.0):.2f}"
        iqr = f"{st.get('q25', 0.0):.2f} - {st.get('q75', 0.0):.2f}"
        rng = f"{st.get('min', 0.0):.2f} - {st.get('max', 0.0):.2f}"
        print(f"{display:<25} | {m_s:<18} | {med:<8} | {iqr:<14} | {rng:<14}")
    print("=" * 80)


def main():
    parser = argparse.ArgumentParser(description="Generate dataset summary report for Assisted Elbow Flexion.")
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
        "--output-json",
        type=str,
        default="processed_data/assisted_elbow_flexion/dataset_summary_report.json",
        help="Path to save output JSON summary"
    )
    parser.add_argument(
        "--output-md",
        type=str,
        default="processed_data/assisted_elbow_flexion/dataset_summary_report.md",
        help="Path to save output Markdown summary"
    )
    args = parser.parse_args()

    dataset_path = Path(args.dataset)
    seq_path = Path(args.sequence_dir)
    out_json = Path(args.output_json)
    out_md = Path(args.output_md)

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_md.parent.mkdir(parents=True, exist_ok=True)

    report = generate_dataset_report(dataset_path, seq_path)
    print_console_summary(report)

    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"Saved summary JSON report to: {out_json}")

    md_content = format_markdown_report(report)
    with open(out_md, "w", encoding="utf-8") as f:
        f.write(md_content)
    print(f"Saved summary Markdown report to: {out_md}")


if __name__ == "__main__":
    main()
