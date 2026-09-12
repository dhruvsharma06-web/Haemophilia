from typing import Optional

from pydantic import BaseModel


class Measurements(BaseModel):
    range_of_motion: Optional[float] = None
    duration: Optional[float] = None
    smoothness: Optional[float] = None


class RepResult(BaseModel):
    rep_number: int
    form: str
    predicted_label: str
    confidence: Optional[float] = None
    score: Optional[float] = None
    feedback: Optional[str] = None
    error_type: Optional[str] = None
    error_frame_url: Optional[str] = None
    measurements: Measurements


class AssessmentResponse(BaseModel):
    assessment_id: str
    exercise: str
    media_type: str
    status: str
    rep_count: int
    reps: list[RepResult]