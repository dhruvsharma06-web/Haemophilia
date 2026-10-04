"""Independent structural/raw-coordinate audit; supports incremental extraction QA."""
from pathlib import Path
import sys, json, argparse
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import ROOT, DATA, canonical, verify_config, sha, dump, write_csv
import numpy as np

def main(partial=False):
    verify_config()
    rows, _ = canonical()
    sources = {}
    records = []
    for r in rows:
        sources.setdefault(r['video_id'], []).append(r)
    for vid, reps in sources.items():
        path = ROOT / 'preprocessing/raw_landmarks' / (vid + '.npz')
        if not path.exists():
            assert partial, f'Missing raw source {vid}'
            continue
        audit = json.loads((ROOT / 'preprocessing' / (vid + '_audit.json')).read_text())
        assert audit['status'] == 'success' and sha(path) == audit['raw_landmarks_sha256']
        d = dict(np.load(path))
        expected = sorted({i for r in reps for i in range(int(r['start_frame']), int(r['end_frame']) + 1)})
        assert np.array_equal(d['frame_indices'], expected), vid
        timing = json.loads((DATA / 'frame_audit' / (vid + '_source_times.json')).read_text())
        assert np.array_equal(d['source_times'], [timing[i]['start'] for i in expected])
        assert np.array_equal(d['source_end_times'], [timing[i]['end'] for i in expected])
        assert str(d['source_sha256']) == reps[0]['source_sha256']
        assert np.all(np.diff(d['source_times']) > 0)
        record = {'video_id': vid, 'source_sha256': reps[0]['source_sha256'], 'canonical_repetitions': len(reps), 'union_frames': len(expected)}
        for name in ['image_landmarks', 'world_landmarks']:
            x = d[name]
            assert x.shape == (len(expected), 33, 4)
            assert not np.isinf(x).any(), (vid, name)
            # Absence must be explicit whole-pose NaN, never a fake zero pose.
            present = np.isfinite(x).all(axis=(1, 2))
            absent = np.isnan(x).all(axis=(1, 2))
            assert np.all(present | absent), 'Partially corrupt pose'
            assert not (x[present, :, :3] == 0).all(axis=(1, 2)).any()
            vis = x[present, :, 3]
            assert np.all((vis >= 0) & (vis <= 1))
            record[name + '_present_frames'] = int(present.sum())
            record[name + '_absent_frames'] = int(absent.sum())
            record[name + '_xyz_min'] = float(x[present, :, :3].min()) if present.any() else None
            record[name + '_xyz_max'] = float(x[present, :, :3].max()) if present.any() else None
            record[name + '_visibility_mean'] = float(vis.mean()) if present.any() else None
            record[name + '_outside_image_xy_values'] = int(((x[present, :, :2] < 0) | (x[present, :, :2] > 1)).sum()) if name == 'image_landmarks' else None
        assert audit['repeatability_missing_mask_mismatches'] == 0
        assert audit['repeatability_max_absolute_delta'] <= 1e-6
        records.append(record)
    if not partial:
        assert len(records) == 29
        write_csv(ROOT / 'preprocessing/raw_coordinate_audit.csv', records)
        dump(ROOT / 'preprocessing/raw_validation.json', {'sources': len(records), 'canonical_repetitions': sum(r['canonical_repetitions'] for r in records), 'unique_frames': sum(r['union_frames'] for r in records), 'explicit_absent_world_frames': sum(r['world_landmarks_absent_frames'] for r in records), 'all_structural_and_timing_checks_passed': True, 'raw_files_actually_audited': True, 'image_outside_xy_policy': 'Recorded, not clipped: MediaPipe image coordinates can extend beyond image boundaries.', 'script_sha256': sha(__file__)})
    print(json.dumps({'validated_sources': len(records), 'canonical_repetitions': sum(r['canonical_repetitions'] for r in records), 'absent_world_frames': sum(r['world_landmarks_absent_frames'] for r in records), 'partial': partial}))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--partial', action='store_true')
    main(parser.parse_args().partial)
