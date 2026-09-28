"""Audit script to compute exact hard-negative selection statistics per fold.

Computes:
- Total training Incorrect repetitions in actual_tr_idx
- Number of unique repetitions selected as hard negatives
- Percentage of training Incorrect class selected
- Breakdown by individual criteria:
  1. Flare criterion (0.27 <= peak_flare <= 0.38 or 0.17 <= mean_flare <= 0.30)
  2. Borderline depth (97.0 <= min_ang <= 106.0)
  3. Eccentric compensation (rom >= 35.0 and (ecc_conc >= 1.05 or flex_ext_ratio >= 1.25))
- Number of augmented copies for mild (1x) and moderate (2x)
- Evaluation of whether this is narrow targeting vs broad oversampling.
"""

import sys
import numpy as np
import pandas as pd
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.append(str(BASE_DIR))
sys.path.append(str(BASE_DIR / "scratch"))

from run_hard_negative_augmentation import (
    DATA_PATH, SEQUENCE_DIR, extract_phase_aware_scalars_34, is_hard_negative_candidate, RANDOM_SEED
)

def audit_stats():
    df = pd.read_csv(DATA_PATH)
    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values
    unique_subjects = sorted(list(set(subjects)))

    raw_seqs = []
    durations = []
    for _, r in df.iterrows():
        raw_seqs.append(np.load(SEQUENCE_DIR / r["sequence_file"]))
        durations.append(float(r["duration_sec"]))

    scalars_all = [extract_phase_aware_scalars_34(raw_seqs[i], durations[i]) for i in range(len(df))]

    print("=" * 80)
    print("EXACT HARD-NEGATIVE SELECTION BREAKDOWN PER LOSO FOLD")
    print("=" * 80)

    for test_sub in unique_subjects:
        test_mask = (subjects == test_sub)
        train_mask = ~test_mask
        tr_indices = np.where(train_mask)[0]
        y_train_full = labels[tr_indices]

        # Inner validation split (20% stratified)
        rng = np.random.RandomState(RANDOM_SEED)
        c0_idx = tr_indices[y_train_full == 0]
        c1_idx = tr_indices[y_train_full == 1]
        rng.shuffle(c0_idx)
        rng.shuffle(c1_idx)

        val_n0 = max(1, int(len(c0_idx) * 0.2))
        val_n1 = max(1, int(len(c1_idx) * 0.2))

        actual_tr_idx = np.concatenate([c0_idx[val_n0:], c1_idx[val_n1:]])
        tr_labels = labels[actual_tr_idx]

        # Filter to actual training Incorrect
        tr_inc_indices = [idx for idx in actual_tr_idx if labels[idx] == 0]
        total_tr_inc = len(tr_inc_indices)

        selected_hn = []
        c_flare = 0
        c_depth = 0
        c_eccentric = 0
        c_overlap = 0

        for idx in tr_inc_indices:
            sc = scalars_all[idx]
            rom = sc[0]
            min_ang = sc[1]
            peak_flare = sc[6]
            mean_flare = sc[7]
            flex_ext_ratio = sc[12]
            ecc_conc = sc[18]

            f_flare = (0.27 <= peak_flare <= 0.38) or (0.17 <= mean_flare <= 0.30)
            f_depth = (97.0 <= min_ang <= 106.0)
            f_ecc = (rom >= 35.0) and (ecc_conc >= 1.05 or flex_ext_ratio >= 1.25)

            if f_flare: c_flare += 1
            if f_depth: c_depth += 1
            if f_ecc: c_eccentric += 1
            if (f_flare + f_depth + f_ecc) > 1: c_overlap += 1

            if f_flare or f_depth or f_ecc:
                selected_hn.append(idx)

        num_selected = len(selected_hn)
        pct_selected = (num_selected / max(total_tr_inc, 1)) * 100.0
        copies_mild = num_selected * 1
        copies_moderate = num_selected * 2

        print(f"\nFold excluding {test_sub} (Trained on {len(actual_tr_idx)} actual training reps):")
        print(f"  - Total training Incorrect repetitions : {total_tr_inc}")
        print(f"  - Selected as hard negatives (UNIQUE)   : {num_selected} ({pct_selected:.1f}%)")
        print(f"  - Unselected gross Incorrect reps       : {total_tr_inc - num_selected} ({100 - pct_selected:.1f}%)")
        print(f"  - Criteria breakdown:")
        print(f"      * Mild flare (0.27-0.38 / 0.17-0.30)  : {c_flare} / {total_tr_inc} ({c_flare/total_tr_inc*100:.1f}%)")
        print(f"      * Borderline depth (97°-106°)         : {c_depth} / {total_tr_inc} ({c_depth/total_tr_inc*100:.1f}%)")
        print(f"      * Eccentric rushing (ROM>=35, ecc>1.05): {c_eccentric} / {total_tr_inc} ({c_eccentric/total_tr_inc*100:.1f}%)")
        print(f"      * Multi-criteria overlap              : {c_overlap} / {total_tr_inc} ({c_overlap/total_tr_inc*100:.1f}%)")
        print(f"  - Augmented copies generated:")
        print(f"      * Mild condition (1x)                 : +{copies_mild} augmented samples")
        print(f"      * Moderate condition (2x)             : +{copies_moderate} augmented samples")

if __name__ == "__main__":
    audit_stats()
