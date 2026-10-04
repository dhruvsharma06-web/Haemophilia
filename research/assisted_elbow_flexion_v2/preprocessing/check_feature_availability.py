"""Unsupervised incremental QC; no labels or model outcomes are inspected."""
from pathlib import Path
import sys, json
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import ROOT, canonical, config
sys.path.insert(0, str(ROOT / 'features'))
from build_features import base_features, repair_channel, BASE
import numpy as np

rows, _ = canonical()
cfg = config()
cache = {p.stem: dict(np.load(p)) for p in (ROOT / 'preprocessing/raw_landmarks').glob('*.npz')}
failures = []
count = missing = 0
for r in rows:
    if r['video_id'] not in cache:
        continue
    count += 1
    d = cache[r['video_id']]
    mask = (d['frame_indices'] >= int(r['start_frame'])) & (d['frame_indices'] <= int(r['end_frame']))
    raw = base_features(d['world_landmarks'][mask], r['hand'], cfg['quality']['minimum_joint_visibility'])
    times = d['source_times'][mask]
    missing += int(np.isnan(raw).sum())
    for j, name in enumerate(BASE):
        _, _, error = repair_channel(raw[:, j], times, cfg['quality'])
        if error:
            failures.append({'repetition_id': r['repetition_id'], 'channel': name, 'error': error})
print(json.dumps({'checked_repetitions': count, 'raw_missing_values': missing, 'feature_failures': failures}, indent=2))
