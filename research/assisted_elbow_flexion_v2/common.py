"""Isolated, canonical-only Phase 1 utilities. No production imports."""
from pathlib import Path
import csv, hashlib, importlib.util, json
import numpy as np

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
DATA = REPO / 'processed_data/assisted_elbow_flexion_v2'
RELEASE = DATA / 'releases/human280_20261004'
MANIFEST_SHA = 'bb4669ec492ac26cbf5b064c89390e43cac207f9785c3a5cd0003cea3c587262'

def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(8 * 1024 * 1024), b''): h.update(block)
    return h.hexdigest()

def dump(path, obj):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(obj, indent=2, allow_nan=False, default=lambda x: x.item() if isinstance(x, np.generic) else str(x)), encoding='utf-8')

def write_csv(path, rows):
    if not rows: return
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with Path(path).open('w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

def canonical():
    assert sha(RELEASE / 'canonical_manifest.csv') == MANIFEST_SHA
    # Read the immutable release validator without creating __pycache__ in it.
    ns = {'__file__': str(RELEASE / 'load_canonical.py'), '__name__': 'release_validator'}
    exec(compile((RELEASE / 'load_canonical.py').read_text(), str(RELEASE / 'load_canonical.py'), 'exec'), ns)
    return ns['load_canonical'](), ns['assert_source_grouping']

def config(): return json.loads((ROOT / 'config.json').read_text())

def verify_config():
    lock = json.loads((ROOT / 'protocol_lock.json').read_text())
    assert sha(ROOT / 'config.json') == lock['config_sha256'], 'Frozen protocol changed'
    assert sha(ROOT / 'splits/fold_assignments.csv') == lock['fold_assignments_sha256']
    return lock
