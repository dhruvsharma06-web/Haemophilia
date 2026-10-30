"""Similarity-invariant, front-view assisted elbow research features.

All classifier features and phase/QC decisions use image-plane observations.
The estimated world angle is retained only in raw channel 1 for compatibility;
it is never a feature or a substitute for a missing image observation. These
measurements do not establish physical support contact or clinical suitability.
"""
import numpy as np
from sklearn.base import BaseEstimator, TransformerMixin
from src.features.elbow_research_v3 import angle, valid_points, quantile, CausalSmoother, causal_trace


CHANNEL_NAMES = [
    'active_angle_2d', 'active_angle_3d_compatibility_only',
    'upper_direction_x', 'upper_direction_y',
    'forearm_direction_x', 'forearm_direction_y',
    'support_segment_distance', 'support_wrist_distance',
    'opposing_angle_2d', 'support_segment_location',
    'upper_to_shoulder_perpendicular_departure',
]
NAMES = [
    'active_angle_excursion', 'active_flexion_excursion',
    'active_return_excursion', 'active_closure_error', 'active_relative_return',
    'relative_flexion_phase', 'flexion_direction_fraction',
    'return_direction_fraction', 'active_angular_path_ratio',
    'upper_direction_change_p90', 'upper_direction_change_at_flexion',
    'upper_direction_change_at_end', 'upper_direction_change_variation',
    'forearm_direction_change_p90', 'forearm_direction_change_at_flexion',
    'forearm_direction_change_at_end',
]
SUPPORT_NAMES = [
    kind + '_' + stat
    for kind in ('support_segment', 'support_wrist')
    for stat in ('median', 'p90', 'variation', 'flexion_median',
                 'return_median', 'phase_change', 'end_change')
]
NAMES += SUPPORT_NAMES
NAMES += [
    'support_segment_location_median', 'support_segment_location_variation',
    'support_segment_location_phase_change',
    'opposing_angle_excursion', 'opposing_closure_error',
    'opposing_to_active_excursion', 'bilateral_angle_correlation',
    'bilateral_motion_direction_agreement',
    'upper_to_shoulder_departure_median', 'upper_to_shoulder_departure_p90',
]
COMPACT_EXCLUDED = {
    'active_angular_path_ratio', 'upper_direction_change_variation',
    'forearm_direction_change_p90', 'forearm_direction_change_at_flexion',
    'forearm_direction_change_at_end', 'support_segment_location_median',
    'support_segment_location_variation', 'support_segment_location_phase_change',
}
REQUIRED_IMAGE_CHANNELS = [0, 2, 3, 4, 5, 6, 7, 8, 9, 10]


class FeatureView(TransformerMixin, BaseEstimator):
    def __init__(self, view='all'):
        self.view = view

    def fit(self, X, y=None):
        self.n_features_in_ = X.shape[1]
        return self

    def transform(self, X):
        if self.view in ('all', 'image'):
            return X
        if self.view == 'compact':
            # Support proximity and dynamic features are mandatory in every view.
            indices = [i for i, name in enumerate(NAMES) if name not in COMPACT_EXCLUDED]
            return X[:, indices]
        raise ValueError('Invalid feature view')


def _angle_2d(first, center, last):
    """Geometric elbow angle without acos rounding near 0/180 degrees."""
    u, v = first - center, last - center
    dot = np.sum(u * v, axis=1)
    cross = u[:, 0] * v[:, 1] - u[:, 1] * v[:, 0]
    observed = np.linalg.norm(u, axis=1) * np.linalg.norm(v, axis=1) > 1e-8
    result = np.degrees(np.arctan2(np.abs(cross), dot))
    return np.where(observed, result, np.nan)


def channels(world, image, width=960, height=540, hand='Left'):
    """Return eleven raw channels, using equal pixel units for image x/y.

    Confidence alone cannot make an off-screen joint an observed joint.
    Both arm shoulder/elbow/wrist landmarks must be finite, visible >= 0.5,
    and within the image. Missing support observations mask every image channel.
    """
    if hand not in ('Left', 'Right'):
        raise ValueError('Invalid active side')
    if not np.isfinite(width) or not np.isfinite(height) or width <= 0 or height <= 0:
        raise ValueError('Invalid image dimensions')
    image = np.asarray(image, dtype=float)
    world = np.asarray(world, dtype=float)
    s, e, w = (11, 13, 15) if hand == 'Left' else (12, 14, 16)
    os, oe, ow = (12, 14, 16) if hand == 'Left' else (11, 13, 15)
    required = [11, 12, 13, 14, 15, 16]
    xy = image[:, :, :2] * np.asarray([width, height], dtype=float)
    xyz = world[:, :, :3]
    upper = xy[:, e] - xy[:, s]
    forearm = xy[:, w] - xy[:, e]
    upper_length = np.linalg.norm(upper, axis=1)
    forearm_length = np.linalg.norm(forearm, axis=1)
    shoulders = xy[:, 12] - xy[:, 11]
    shoulder_length = np.linalg.norm(shoulders, axis=1)
    safe_upper = np.where(upper_length > 1e-5, upper_length, np.nan)
    safe_forearm = np.where(forearm_length > 1e-5, forearm_length, np.nan)
    upper_direction = upper / safe_upper[:, None]
    forearm_direction = forearm / safe_forearm[:, None]
    shoulder_direction = shoulders / np.where(shoulder_length > 1e-5, shoulder_length, np.nan)[:, None]
    # A projected anatomical relation, not gravity orientation or true trunk lean.
    # Zero means the upper arm is perpendicular to the observed shoulder line.
    shoulder_departure = np.degrees(np.arcsin(np.clip(
        np.abs(np.sum(upper_direction * shoulder_direction, axis=1)), 0., 1.)))
    location = np.sum((xy[:, ow] - xy[:, e]) * forearm, axis=1) / safe_forearm**2
    nearest = xy[:, e] + np.clip(location, 0., 1.)[:, None] * forearm
    values = np.column_stack([
        _angle_2d(xy[:, s], xy[:, e], xy[:, w]),
        angle(xyz[:, s], xyz[:, e], xyz[:, w]),
        upper_direction, forearm_direction,
        np.linalg.norm(xy[:, ow] - nearest, axis=1) / safe_forearm,
        np.linalg.norm(xy[:, ow] - xy[:, w], axis=1) / safe_forearm,
        _angle_2d(xy[:, os], xy[:, oe], xy[:, ow]),
        np.clip(location, 0., 1.),
        shoulder_departure,
    ])
    within_image = ((image[:, required, :2] >= 0.) &
                    (image[:, required, :2] <= 1.)).all(axis=(1, 2))
    observed = valid_points(image, required, minimum=.5) & within_image
    observed &= (upper_length > 1e-5) & (forearm_length > 1e-5) & (shoulder_length > 1e-5)
    values[np.ix_(~observed, REQUIRED_IMAGE_CHANNELS)] = np.nan
    values[~valid_points(world, [s, e, w], minimum=.5), 1] = np.nan
    values[~np.isfinite(values)] = np.nan
    return values


def _unit(rows):
    length = np.linalg.norm(rows, axis=1)
    return rows / np.where(length > 1e-8, length, np.nan)[:, None]


def _angular_median_reference(directions, start_mask):
    """Observed angular medoid: a robust, rotation/reflection-equivariant median.

    A coordinate-wise x/y median is not rotation invariant. Instead choose the
    initial observed direction minimizing total pairwise angular distance.
    """
    initial = directions[start_mask & np.isfinite(directions).all(axis=1)]
    if len(initial) < 3:
        initial = directions[np.isfinite(directions).all(axis=1)][:3]
    if len(initial) < 3:
        return np.full(2, np.nan)
    pair_dot = initial @ initial.T
    pair_cross = (initial[:, None, 0] * initial[None, :, 1] -
                  initial[:, None, 1] * initial[None, :, 0])
    # acos(self dot) can add ~1e-8 radians to a cost that should contain a
    # zero diagonal. Even-size angular medians often have two equal minima;
    # that numerical noise previously chose different observed directions
    # under an otherwise identical roll/scale/translation of the clip.
    pair_angles = np.arctan2(np.abs(pair_cross), pair_dot)
    costs = np.sum(pair_angles, axis=1)
    tied = np.flatnonzero(costs <= np.min(costs) + 1e-10)
    return initial[int(tied[0])]  # Earliest observed median, deterministic ties.


def _direction_change(trace, columns, start_mask):
    direction = _unit(trace[:, columns])
    reference = _angular_median_reference(direction, start_mask)
    dot = direction @ reference
    cross = direction[:, 0] * reference[1] - direction[:, 1] * reference[0]
    return np.degrees(np.arctan2(np.abs(cross), dot))


def _correlation(a, b):
    observed = np.isfinite(a) & np.isfinite(b)
    if observed.sum() < 3:
        return np.nan
    a, b = a[observed], b[observed]
    if np.std(a) < 1e-8 or np.std(b) < 1e-8:
        return np.nan
    return float(np.clip(np.corrcoef(a, b)[0, 1], -1., 1.))


def _direction_fraction(values, expected):
    difference = np.diff(values)
    observed = np.isfinite(difference) & (np.abs(difference) > 1.)
    return float(np.mean(difference[observed] * expected > 0)) if observed.any() else np.nan


def rep_features(trace, times):
    """Return 40 features and image-only QC for one provisional cycle window.

    Raw angular excursion remains in degrees. Relative return/phase measure
    cycle structure; they do not prescribe a patient's therapeutic range.
    Absolute duration, cadence, angle endpoints and camera-gravity orientation
    are deliberately absent from classifier features.
    """
    trace = np.asarray(trace, dtype=float)
    times = np.asarray(times, dtype=float)
    if len(times) < 8 or len(trace) != len(times):
        raise ValueError('Insufficient window')
    if not np.isfinite(times).all() or np.any(np.diff(times) <= 0):
        raise ValueError('Nonmonotonic timestamps')
    seen = np.isfinite(trace[:, REQUIRED_IMAGE_CHANNELS]).all(axis=1)
    coverage = float(seen.mean())
    qc = {'active_coverage': coverage, 'both_arm_support_coverage': coverage,
          'phase_signal': 'active_image_elbow_angle', 'reason': None}
    if coverage < .8:
        return None, {**qc, 'reason': 'insufficient_both_arm_support_visibility'}
    primary = trace[:, 0]
    # Numerically equivalent flat minima use the earliest sample. This tiny
    # tolerance is below observation precision and is not a movement target.
    peak = int(np.flatnonzero(np.isfinite(primary) &
                             (primary <= np.nanmin(primary) + 1e-5))[0])
    relative_time = (times - times[0]) / (times[-1] - times[0])
    start_mask, end_mask = relative_time <= .12, relative_time >= .88
    # Short windows still need at least three samples for robust summaries.
    if start_mask.sum() < 3:
        start_mask[:3] = True
    if end_mask.sum() < 3:
        end_mask[-3:] = True
    # Use a neighbourhood in relative cycle time, with enough observed samples.
    peak_mask = np.abs(relative_time - relative_time[peak]) <= .06
    if peak_mask.sum() < 3:
        peak_mask[np.argsort(np.abs(relative_time - relative_time[peak]))[:3]] = True
    start, end = quantile(primary[start_mask], .5), quantile(primary[end_mask], .5)
    low = quantile(primary[peak_mask], .1)
    excursion = quantile(primary, .9) - quantile(primary, .1)
    flexion_excursion, return_excursion = start - low, end - low
    # Five degrees is a fixed engineering noise denominator, not a clinical ROM.
    return_fraction = return_excursion / max(flexion_excursion, 5.)
    difference = np.diff(primary)
    observed_path = np.sum(np.abs(difference[np.isfinite(difference)]))
    result = [
        excursion, flexion_excursion, return_excursion, abs(end - start),
        return_fraction, relative_time[peak],
        _direction_fraction(primary[:peak + 1], -1),
        _direction_fraction(primary[peak:], 1),
        observed_path / max(2. * excursion, 5.),
    ]
    upper_change = _direction_change(trace, [2, 3], start_mask)
    forearm_change = _direction_change(trace, [4, 5], start_mask)
    result += [quantile(upper_change, .9), quantile(upper_change[peak_mask], .5),
               quantile(upper_change[end_mask], .5),
               quantile(upper_change, .9) - quantile(upper_change, .1),
               quantile(forearm_change, .9), quantile(forearm_change[peak_mask], .5),
               quantile(forearm_change[end_mask], .5)]
    flex_mask, return_mask = relative_time <= relative_time[peak], relative_time >= relative_time[peak]
    for column in (6, 7):
        support = trace[:, column]
        flex, returning = quantile(support[flex_mask], .5), quantile(support[return_mask], .5)
        result += [quantile(support, .5), quantile(support, .9),
                   quantile(support, .9) - quantile(support, .1), flex, returning,
                   returning - flex,
                   quantile(support[end_mask], .5) - quantile(support[start_mask], .5)]
    location, opposing = trace[:, 9], trace[:, 8]
    opposing_excursion = quantile(opposing, .9) - quantile(opposing, .1)
    opposing_closure = abs(quantile(opposing[end_mask], .5) - quantile(opposing[start_mask], .5))
    active_difference, opposing_difference = np.diff(primary), np.diff(opposing)
    moving = (np.isfinite(active_difference) & np.isfinite(opposing_difference) &
              (np.abs(active_difference) > 1.) & (np.abs(opposing_difference) > 1.))
    agreement = float(np.mean(active_difference[moving] * opposing_difference[moving] > 0)) if moving.any() else np.nan
    result += [quantile(location, .5), quantile(location, .9) - quantile(location, .1),
               quantile(location[return_mask], .5) - quantile(location[flex_mask], .5),
               opposing_excursion, opposing_closure, opposing_excursion / max(excursion, 5.),
               _correlation(primary, opposing), agreement]
    # Keep sustained front-view posture evidence; do not normalize away a
    # consistently displaced arm. No clinical pass/fail target is supplied here.
    result += [quantile(trace[:, 10], .5), quantile(trace[:, 10], .9)]
    features = np.asarray(result, dtype=float)
    if len(features) != len(NAMES):
        raise ValueError('Feature schema mismatch')
    features[~np.isfinite(features)] = np.nan
    qc.update({'phase_peak_index': peak, 'peak_at_endpoint': peak in (0, len(times) - 1)})
    return features, qc
