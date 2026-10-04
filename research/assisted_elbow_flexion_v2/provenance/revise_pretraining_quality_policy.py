"""Explicit QC-only amendment, before any learned-model fits or OOF inspection."""
from pathlib import Path
import sys, json, shutil
from datetime import datetime, timezone
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import ROOT, verify_config, config, dump, sha

def main():
    old_lock = verify_config()
    assert not list((ROOT / 'checkpoints').rglob('*.joblib'))
    assert not list((ROOT / 'checkpoints').rglob('*.pth'))
    assert not list((ROOT / 'baselines').rglob('summary.json'))
    archive = ROOT / 'provenance/protocol_before_qc_revision'
    archive.mkdir(exist_ok=False)
    for name in ['config.json', 'protocol_lock.json']:
        shutil.copyfile(ROOT / name, archive / name)
    cfg = config()
    assert cfg['quality']['max_internal_gap_seconds'] == .25
    cfg['quality']['max_internal_gap_seconds'] = .50
    cfg['feature_version'] = 'world_kinematics_v1_1'
    dump(ROOT / 'config.json', cfg)
    dump(ROOT / 'provenance/pretraining_quality_amendment.json', {
        'amended_at_utc': datetime.now(timezone.utc).isoformat(),
        'stage': 'raw extraction / unsupervised feature availability, before any learned-model fits',
        'reason': 'One observed active-wrist visibility gap has valid bracketing support 0.466467 seconds apart. It passes the unchanged >=80% valid-frame condition but failed the initial 0.25-second cap.',
        'affected_repetition_at_decision': 'rep_3138501c806e115527',
        'change': 'Maximum internal bracketing gap 0.25 -> 0.50 seconds, applied uniformly to every channel/repetition; endpoint limit remains 0.10 seconds and visibility remains >=0.5.',
        'limitations': 'The 0.50-second bound is an engineering accommodation, not a clinically validated tolerance. Interpolated movement may miss real dynamics. Report every operation and preserve raw NaNs.',
        'no_labels_or_model_metrics_used_to_decide': True,
        'old_config_sha256': old_lock['config_sha256'],
        'new_config_sha256': sha(ROOT / 'config.json'),
        'fold_assignments_unchanged': old_lock['fold_assignments_sha256'],
        'model_hyperparameters_unchanged': True,
        'raw_pose_extraction_parameters_unchanged': True,
    })
    dump(ROOT / 'protocol_lock.json', {
        'frozen_at_utc': datetime.now(timezone.utc).isoformat(),
        'config_sha256': sha(ROOT / 'config.json'),
        'fold_assignments_sha256': old_lock['fold_assignments_sha256'],
        'manifest_sha256': old_lock['manifest_sha256'],
    })
    print('Recorded one QC-only pretraining amendment; no model/fold/range/label changes.')

if __name__ == '__main__':
    main()
