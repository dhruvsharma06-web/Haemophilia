"""Independent verification script for Phase 3 research deliverables and preservation."""
import json, hashlib
from pathlib import Path
import numpy as np
import pandas as pd

from phase3_utils import P3, P2, P1, REPO, DATA, RELEASE, METRICS, inputs, sha, dump

def verify():
    print("=== Running Phase 3 Verification ===")
    df, d, frozen = inputs()
    y = (df.label == 'Incorrect').astype(int).to_numpy()
    
    # 1. Canonical data integrity
    assert len(df) == 280, f"Expected 280 canonical rows, got {len(df)}"
    assert int((df.label == 'Correct').sum()) == 183
    assert int((df.label == 'Incorrect').sum()) == 97
    assert int((df.hand == 'Left').sum()) == 143
    assert int((df.hand == 'Right').sum()) == 137
    assert df.source_sha256.nunique() == 29
    
    # Excluded candidates check
    contract = json.loads((RELEASE / 'CANONICAL_CONTRACT.json').read_text())
    assert not (set(df.repetition_id) & set(contract['excluded_repetition_ids'])), "Excluded candidate found in canonical set!"
    
    # 2. Participant grouping audit
    audit = pd.read_csv(P3 / 'participant_grouping_audit.csv')
    assert len(audit) == 29, f"Expected 29 audited sources, got {len(audit)}"
    assert (audit['subject_verified'] == False).all(), "Unverified subject IDs must remain marked unverified!"
    assert audit.session_block_id.nunique() == 5
    assert set(audit.inherited_subject_id) == {'person1', 'person2', 'person3', 'person4', 'person5'}
    
    # 3. Model comparison & fold metrics
    comp = pd.read_csv(P3 / 'development_model_comparison.csv')
    assert len(comp) == 6, f"Expected 6 development comparison rows, got {len(comp)}"
    
    # Check baseline match
    base_row = comp[(comp.protocol == '5fold_source_grouped') & (comp.model == 'FrozenPhase1SVM')].iloc[0]
    assert np.isclose(base_row.accuracy, 0.87142857)
    assert np.isclose(base_row.balanced_accuracy, 0.83865698)
    assert np.isclose(base_row.macro_f1, 0.85175599)
    assert np.isclose(base_row.correct_recall, 0.94535519)
    assert np.isclose(base_row.incorrect_recall, 0.73195876)
    
    # Check BalancedSVM match
    bal_row = comp[(comp.protocol == '5fold_source_grouped') & (comp.model == 'BalancedSVM')].iloc[0]
    assert np.isclose(bal_row.accuracy, 0.88214286)
    assert np.isclose(bal_row.balanced_accuracy, 0.86623289)
    assert np.isclose(bal_row.macro_f1, 0.86889712)
    assert np.isclose(bal_row.correct_recall, 0.91803279)
    assert np.isclose(bal_row.incorrect_recall, 0.81443299)
    
    # Check LOSO match
    loso_unw = comp[(comp.protocol == '29fold_loso') & (comp.model == 'FrozenPhase1SVM_LOSO')].iloc[0]
    assert np.isclose(loso_unw.balanced_accuracy, 0.80984170)
    assert np.isclose(loso_unw.incorrect_recall, 0.69072165)
    
    loso_bal = comp[(comp.protocol == '29fold_loso') & (comp.model == 'BalancedSVM_LOSO')].iloc[0]
    assert np.isclose(loso_bal.balanced_accuracy, 0.84257121)
    assert np.isclose(loso_bal.incorrect_recall, 0.78350515)
    
    # 4. Generalization gap
    gap = pd.read_csv(P3 / 'generalization_gap.csv')
    assert len(gap) == 7, f"Expected 7 generalization gap rows, got {len(gap)}"
    
    # 5. Final model selection
    sel = json.loads((P3 / 'final_model_selection.json').read_text())
    assert sel['selected_model'] == 'BalancedSVM'
    
    # 6. Feature definition snapshot
    feat = json.loads((P3 / 'feature_definition_snapshot.json').read_text())
    assert feat['feature_count'] == 34
    
    # 7. Final model metadata and parameters
    meta = json.loads((P3 / 'final_model_metadata.json').read_text())
    assert meta['canonical_examples_count'] == 280
    assert meta['feature_dimension'] == 34
    assert meta['pipeline_steps'][2]['class_weight'] == 'balanced'
    
    params = json.loads((P3 / 'checkpoints/final_model_v2_parameters.json').read_text())
    assert len(params['feature_names']) == 34
    assert params['class_weight'] == 'balanced'
    assert len(params['support_vectors']) == params['total_support_vectors']
    
    # 8. Plots check
    assert (P3 / 'plots/model_comparison.png').stat().st_size > 1000
    assert (P3 / 'plots/generalization_gap.png').stat().st_size > 1000
    
    # 9. Protected files audit (verify repository preservation)
    protected_ref = json.loads((P2 / 'provenance/protected_files_before.json').read_text())
    changed = [p for p, h in protected_ref.items() if sha(p) != h]
    
    preservation = {
        'protected_files_checked': len(protected_ref),
        'changed': changed,
        'all_unchanged': len(changed) == 0
    }
    dump(P3 / 'provenance/preservation_audit.json', preservation)
    assert len(changed) == 0, f"Protected files modified: {changed}"
    
    # 10. Check no production or root checkpoints were created
    forbidden_suffixes = ['.pth', '.joblib', '.pkl', '.pt']
    root_checkpoints = [str(p) for p in REPO.glob('models/*') if p.suffix in forbidden_suffixes and 'v2' in p.name.lower() and 'phase3' in p.name.lower()]
    assert not root_checkpoints, f"Forbidden production checkpoint created: {root_checkpoints}"
    
    verif = {
        'all_passed': True,
        'phase': 3,
        'canonical_examples': 280,
        'audited_sources': 29,
        'session_clusters': 5,
        'development_protocols_evaluated': 3,
        'winning_model': 'BalancedSVM',
        'final_fit_completed': True,
        'protected_files_verified': len(protected_ref),
        'protected_files_unchanged': len(changed) == 0,
        'script_sha256': sha(__file__)
    }
    dump(P3 / 'provenance/verification.json', verif)
    print(f"PASS: All Phase 3 checks passed. {len(protected_ref)} protected files verified unchanged.")

if __name__ == '__main__':
    verify()
