"""Physical bounds and timing checks independent of model training."""
from pathlib import Path
import sys, json
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import ROOT, canonical, verify_config, dump, sha
import numpy as np

def main():
    verify_config()
    rows, _ = canonical()
    d = dict(np.load(ROOT / 'features/model_ready.npz'))
    assert d['repetition_ids'].tolist() == [r['repetition_id'] for r in rows]
    scalars = d['scalar']
    seq = d['sequence']
    assert scalars.shape == (280, 34) and seq.shape == (280, 128, 11)
    assert not np.isinf(scalars).any() and not np.isinf(seq).any()
    for channels, low, high in [(seq[:,:,:2],0,180),(seq[:,:,4],0,90),(seq[:,:,5],0,1.000001)]:
        finite=channels[np.isfinite(channels)]
        assert np.all((finite>=low)&(finite<=high))
    assert np.all(seq[:,:,2:4][np.isfinite(seq[:,:,2:4])]>=0)
    assert np.all(seq[:,:,8:10][np.isfinite(seq[:,:,8:10])]>=0)
    names = d['scalar_names'].tolist()
    for i, r in enumerate(rows):
        p = dict(np.load(ROOT / 'features/per_repetition' / (r['repetition_id'] + '.npz')))
        assert np.array_equal(p['frame_indices'], np.arange(int(r['start_frame']), int(r['end_frame']) + 1))
        assert np.all(np.diff(p['source_times']) > 0)
        assert abs(scalars[i, names.index('duration')] - float(r['duration_sec'])) < 2e-5
        t = p['source_times']
        assert np.allclose(p['kinematics'][:, 10], t - t[0])
        if np.isfinite(scalars[i,names.index('flexion_duration')]):
            assert abs(scalars[i, names.index('flexion_duration')] + scalars[i, names.index('extension_duration')] - (t[-1] - t[0])) < 1e-8
        if np.isfinite(scalars[i,names.index('active_rom')]):
            assert abs(scalars[i, names.index('active_rom')] - (scalars[i, names.index('active_max_angle')] - scalars[i, names.index('active_min_angle')])) < 1e-8
        assert np.allclose(p['sequence'][[0, -1], :], p['kinematics'][[0, -1], :], rtol=1e-6, atol=1e-5,equal_nan=True)
    # Analytical signal checks guard radians/frame-speed errors and wrong arm semantics.
    sys.path.insert(0, str(ROOT / 'features'))
    from build_features import angle, derive, base_features, repair_channel
    a = np.array([[1., 0, 0]])
    b = np.zeros((1, 3))
    c = np.array([[0., 1, 0]])
    assert np.allclose(angle(a, b, c), 90)
    times = np.array([0., .02, .05, .11])
    base = np.zeros((4, 6)); base[:, 0] = 100 - 20*times; base[:, 1] = 40 + 10*times
    z = derive(base, times)
    assert np.allclose(z[:, 6], -20) and np.allclose(z[:, 7], 10)
    world = np.ones((1, 33, 4))
    world[0, :, :3] = 0
    world[0, 11, :3] = [-1, -1, 0]; world[0, 13, :3] = [-1, 0, 0]; world[0, 15, :3] = [0, 0, 0]
    world[0, 12, :3] = [1, -1, 0]; world[0, 14, :3] = [1, 0, 0]; world[0, 16, :3] = [1, 1, 0]
    left = base_features(world, 'Left', .5); right = base_features(world, 'Right', .5)
    assert np.allclose(left[0, :2], [90, 180]) and np.allclose(right[0, :2], [180, 90])
    policy = {'minimum_valid_fraction': .8, 'max_internal_gap_seconds': .5, 'max_endpoint_hold_seconds': .1}
    values = np.arange(10, dtype=float); values[5] = np.nan
    repaired, events, err = repair_channel(values, np.arange(10)*.03, policy)
    assert err is None and repaired[5] == 5 and events[0]['frames'] == 1
    _, _, err = repair_channel(values, np.arange(10)*.3, policy)
    assert err is not None  # Cannot conceal a long unsupported temporal gap.
    dump(ROOT / 'features/independent_validation.json', {'canonical_examples': 280, 'all_passed': True, 'checks': ['physical angle/ratio bounds', 'canonical exact ranges and durations', 'monotonic PTS', 'phase duration consistency', 'resampling endpoints', 'analytical degrees and nonuniform-PTS velocity', 'exercised-arm mapping', 'bounded missing-gap refusal'], 'script_sha256': sha(__file__)})
    print('PASS: 280 physical/timing representations and analytical kinematics controls')

if __name__ == '__main__':
    main()
