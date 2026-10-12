"""Count bilateral centre -> extreme -> centre -> opposite extreme sequences.

Neutral is geometrically known; a stationary initial extreme cannot calibrate it.
Thresholds are engineering units, not clinical shoulder ROM measurements.
"""
from dataclasses import dataclass
import math
from statistics import median


@dataclass
class RotationCycleDetector:
    excursion: float = 10.0
    min_frames: int = 15
    max_frames: int = 500
    return_band: float = 3.0
    calibration_frames: int = 10
    confirm_frames: int = 3
    calibration_band: float = 8.0
    centre_confirm_frames: int = 1
    coordination_band: float = 15.0
    centre: float | None = None

    def __post_init__(self):
        if not 0 < self.return_band < self.excursion:
            raise ValueError("Return band must be positive and smaller than excursion.")
        self.hand_centres = None
        self.reset()

    def reset(self):
        self.state = "WAIT_FOR_CENTRE"
        self.direction = 0
        self.extreme = None
        self.start_frame = self.last_centre_frame = None
        self.candidate = None
        self.stable_count = 0
        self.last_frame = None
        self.calibration = []

    def update(self, value, frame):
        hands = list(value) if isinstance(value, (tuple, list)) else [value, value]
        frame = int(frame)
        if len(hands) != 2 or not all(math.isfinite(float(x)) for x in hands):
            self.reset()
            return None
        if self.last_frame is not None and frame <= self.last_frame:
            return None
        if self.last_frame is not None and frame - self.last_frame > 1:
            self.reset()
        self.last_frame = frame
        neutral = 0.0 if self.centre is None else self.centre
        offsets = [float(x) - (self.hand_centres[i] if self.hand_centres is not None else neutral)
                   for i, x in enumerate(hands)]
        # At geometric neutral the wand midpoint is over the elbow midpoint;
        # grip width and landmark bias need not place each wrist over its elbow.
        initial_neutral = self.centre is None and abs(sum(offsets) / 2) <= min(self.calibration_band, self.excursion * .8)
        coordinated_centre = (abs(sum(offsets) / 2) <= self.return_band
                              and abs(offsets[0] - offsets[1]) <= self.coordination_band)
        zone = (0 if initial_neutral or coordinated_centre else
                1 if all(x >= self.excursion for x in offsets) else
                -1 if all(x <= -self.excursion for x in offsets) else None)
        if self.start_frame is not None and frame - self.start_frame > self.max_frames:
            self.reset()
            self.last_frame = frame
        if zone is None:
            self.candidate, self.stable_count = None, 0
            self.calibration.clear()
            return None
        if zone == self.candidate:
            self.stable_count += 1
        else:
            self.candidate, self.stable_count = zone, 1
            self.calibration.clear()
        if self.centre is None and zone == 0:
            self.calibration.append(hands)
        required = (self.calibration_frames if self.centre is None else
                    self.centre_confirm_frames if zone == 0 else self.confirm_frames)
        if self.stable_count < required:
            return None
        if self.state == "WAIT_FOR_CENTRE" and zone == 0:
            if self.centre is None:
                self.hand_centres = [float(median(row[i] for row in self.calibration)) for i in range(2)]
            self.centre = neutral
            self.last_centre_frame = frame
            self.state = "FIRST_EXTREME"
        elif self.state == "FIRST_EXTREME":
            if zone == 0:
                self.last_centre_frame = frame
            else:
                self.start_frame = self.last_centre_frame
                self.direction = zone
                self.extreme = sum(hands) / 2
                self.state = "RETURN_TO_CENTRE"
        elif self.state == "RETURN_TO_CENTRE" and zone == 0:
            self.state = "OPPOSITE_EXTREME"
        elif self.state == "OPPOSITE_EXTREME" and zone == -self.direction:
            bounds = (self.start_frame, frame)
            duration = frame - self.start_frame + 1
            self.reset()
            self.last_frame = frame
            return bounds if self.min_frames <= duration <= self.max_frames else None
        return None
