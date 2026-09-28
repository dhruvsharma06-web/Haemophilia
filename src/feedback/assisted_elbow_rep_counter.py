"""Configurable Assisted Elbow Flexion repetition detector and segmenter.

Detects complete elbow flexion/extension cycles:
- Starts in EXTENSION (high joint angle ~130-160 deg)
- Enters FLEXION (angle drops below flexion threshold)
- Reaches inflection point (minimum angle / peak flexion)
- Returns to EXTENSION (angle rises back towards start)
Tracks accepted vs rejected repetitions with specific rejection reasons.
"""

from typing import Dict, List, Optional, Tuple
import numpy as np


class AssistedElbowRepCounter:
    def __init__(
        self,
        start_extend_threshold: float = 120.0,
        flexion_threshold: float = 110.0,
        min_rom: float = 20.0,
        min_duration_sec: float = 0.8,
        max_duration_sec: float = 8.0,
        debounce_sec: float = 0.3,
        max_lookback_sec: float = 3.5,
        max_lookforward_sec: float = 3.5,
        prominence_ratio: float = 0.5,
        min_visibility: float = 0.35,
        fps: float = 30.0,
    ):
        self.start_extend_threshold = start_extend_threshold
        self.flexion_threshold = flexion_threshold
        self.min_rom = min_rom
        self.min_duration_sec = min_duration_sec
        self.max_duration_sec = max_duration_sec
        self.debounce_sec = debounce_sec
        self.max_lookback_sec = max_lookback_sec
        self.max_lookforward_sec = max_lookforward_sec
        self.prominence_ratio = prominence_ratio
        self.min_visibility = min_visibility
        self.fps = max(fps, 1.0)

        # Dynamic rejection accounting
        self.total_detected = 0
        self.total_accepted = 0
        self.total_rejected = 0
        self.rejection_reasons: Dict[str, int] = {
            "INSUFFICIENT_ROM": 0,
            "INSUFFICIENT_DURATION": 0,
            "HIGH_DEBOUNCE_OVERLAP": 0,
            "INCOMPLETE_CYCLE": 0,
            "TRACKING_LOSS": 0,
        }

    def get_config(self) -> Dict[str, float]:
        """Return configurable threshold parameters."""
        return {
            "start_extend_threshold": self.start_extend_threshold,
            "flexion_threshold": self.flexion_threshold,
            "min_rom": self.min_rom,
            "min_duration_sec": self.min_duration_sec,
            "max_duration_sec": self.max_duration_sec,
            "debounce_sec": self.debounce_sec,
            "max_lookback_sec": self.max_lookback_sec,
            "max_lookforward_sec": self.max_lookforward_sec,
            "prominence_ratio": self.prominence_ratio,
            "min_visibility": self.min_visibility,
            "fps": self.fps,
        }

    def segment_series(
        self,
        angles: np.ndarray,
        visibilities: Optional[np.ndarray] = None,
    ) -> Tuple[List[Dict], List[Dict]]:
        """Segment an angle time series into accepted and rejected repetitions."""
        accepted_reps = []
        rejected_reps = []

        if len(angles) < int(self.fps * self.min_duration_sec):
            return accepted_reps, rejected_reps

        # Smooth angles with moving average filter
        w = max(5, int(self.fps * 0.15))
        if w % 2 == 0:
            w += 1
        angles_s = np.convolve(angles, np.ones(w) / w, mode="same")

        # Find inflection troughs (peaks of flexion)
        from scipy.signal import find_peaks

        min_distance = int(self.fps * self.min_duration_sec)
        prominence = float(self.min_rom * self.prominence_ratio)
        troughs, _ = find_peaks(
            -angles_s,
            distance=min_distance,
            prominence=prominence,
        )

        last_end_frame = 0

        for t in troughs:
            self.total_detected += 1

            # Constrain lookback search to guarantee rep_start >= last_end_frame
            lookback = int(self.fps * self.max_lookback_sec)
            start_window = max(last_end_frame, max(0, t - lookback))

            if t <= start_window:
                # Inflection occurs at or before the previous rep end -> overlap
                self.total_rejected += 1
                self.rejection_reasons["HIGH_DEBOUNCE_OVERLAP"] = (
                    self.rejection_reasons.get("HIGH_DEBOUNCE_OVERLAP", 0) + 1
                )
                rejected_reps.append({
                    "peak_frame": int(t),
                    "start_frame": int(start_window),
                    "end_frame": int(t),
                    "rejection_reason": "HIGH_DEBOUNCE_OVERLAP",
                })
                continue

            rep_start = start_window + int(np.argmax(angles_s[start_window:t]))

            # Lookforward for completion of extension (maximum extension after trough)
            lookforward = int(self.fps * self.max_lookforward_sec)
            end_window = min(len(angles_s), t + lookforward)
            if end_window <= t:
                rep_end = t
            else:
                rep_end = t + int(np.argmax(angles_s[t:end_window]))

            duration = (rep_end - rep_start) / self.fps
            start_ang = float(angles_s[rep_start])
            end_ang = float(angles_s[rep_end])
            min_ang = float(angles_s[t])
            rom = float(max(start_ang, end_ang) - min_ang)

            rep_info = {
                "start_frame": int(rep_start),
                "peak_frame": int(t),
                "end_frame": int(rep_end),
                "start_angle": start_ang,
                "peak_angle": min_ang,
                "end_angle": end_ang,
                "rom": rom,
                "duration": duration,
            }

            # Check rejection criteria
            rejection_reason = None

            if rep_start < (last_end_frame - int(self.fps * 0.1)):
                rejection_reason = "HIGH_DEBOUNCE_OVERLAP"
            elif duration < self.min_duration_sec:
                rejection_reason = "INSUFFICIENT_DURATION"
            elif duration > self.max_duration_sec:
                rejection_reason = "INCOMPLETE_CYCLE"
            elif rom < self.min_rom:
                rejection_reason = "INSUFFICIENT_ROM"
            elif visibilities is not None:
                rep_vis = visibilities[rep_start : rep_end + 1]
                if len(rep_vis) > 0 and np.mean(rep_vis) < self.min_visibility:
                    rejection_reason = "TRACKING_LOSS"

            if rejection_reason:
                self.total_rejected += 1
                self.rejection_reasons[rejection_reason] = (
                    self.rejection_reasons.get(rejection_reason, 0) + 1
                )
                rep_info["rejection_reason"] = rejection_reason
                rejected_reps.append(rep_info)
            else:
                self.total_accepted += 1
                last_end_frame = rep_end
                accepted_reps.append(rep_info)

        return accepted_reps, rejected_reps
