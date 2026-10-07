"""Count centre -> one side -> centre excursions, with engineering thresholds."""
from dataclasses import dataclass
from statistics import median


@dataclass
class RotationCycleDetector:
    excursion: float = 10.0
    min_frames: int = 15
    max_frames: int = 500
    return_band: float = 3.0
    calibration_frames: int = 10
    confirm_frames: int = 3
    centre: float | None = None

    def __post_init__(self):
        if not 0 < self.return_band < self.excursion:
            raise ValueError("Return band must be positive and smaller than excursion.")
        self.direction = 0
        self.extreme = None
        self.start_frame = self.last_centre_frame = None
        self.calibration = []
        self.return_frame = None
        self.return_count = 0

    def update(self, value, frame):
        value, frame = float(value), int(frame)
        if self.centre is None:
            self.calibration.append(value)
            if len(self.calibration) >= self.calibration_frames:
                self.centre = float(median(self.calibration))
                self.last_centre_frame = frame
            return None
        offset = value - self.centre
        if self.direction == 0:
            if abs(offset) <= self.return_band:
                self.last_centre_frame = frame
            if abs(offset) < self.excursion or self.last_centre_frame is None:
                return None
            self.direction = 1 if offset > 0 else -1
            self.start_frame = self.last_centre_frame
            self.extreme = value
            self.return_count = 0
            self.return_frame = None
            return None
        if (self.direction == 1 and value > self.extreme) or (self.direction == -1 and value < self.extreme):
            self.extreme = value
        # Reaching centre or crossing it completes this side's excursion.
        # A sustained return band suppresses jitter; crossing prevents missed
        # completions when the next side starts without a pause at centre.
        near_centre = abs(offset) <= self.return_band
        crossed = self.direction * offset < 0
        if near_centre or crossed:
            if self.return_frame is None:
                self.return_frame = frame
            self.return_count += 1
        else:
            self.return_frame, self.return_count = None, 0
        if self.return_count >= self.confirm_frames or crossed:
            end = self.return_frame
            duration = end - self.start_frame + 1
            result = (self.start_frame, end) if self.min_frames <= duration <= self.max_frames else None
            self.direction = 0
            self.last_centre_frame = end
            self.return_count, self.return_frame = 0, None
            return result
        if frame - self.start_frame > self.max_frames:
            # Require a new centre visit rather than starting midway through
            # an unfinished movement after timing out.
            self.direction = 0
            self.last_centre_frame = None
            self.return_count, self.return_frame = 0, None
        return None
