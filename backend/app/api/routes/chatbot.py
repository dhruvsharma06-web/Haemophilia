from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from typing import Dict, Any, Optional

from backend.app.services.screening_ml_service import screening_ml_service

router = APIRouter(
    prefix="/v1/chatbot",
    tags=["Chatbot & Screening"],
)


class ScreeningPredictRequest(BaseModel):
    age: Optional[float] = 0
    sex: Optional[Any] = "male"
    prolonged_bleeding_minor_cut: Optional[Any] = "never"
    excessive_post_surgery_bleeding: Optional[Any] = "no"
    excessive_dental_bleeding: Optional[Any] = "no"
    easy_bruising: Optional[Any] = "never"
    muscle_hematoma: Optional[Any] = "no"
    recurrent_joint_bleeding: Optional[Any] = "no"
    joint_warmth: Optional[Any] = "no"
    joint_tightness: Optional[Any] = "no"
    reduced_joint_mobility: Optional[Any] = "no"
    hematuria: Optional[Any] = "no"
    hematochezia: Optional[Any] = "no"
    family_history_bleeding_disorder: Optional[Any] = "no"
    male_relative_with_hemophilia: Optional[Any] = "no"
    previous_factor_test: Optional[Any] = "no"
    language: Optional[str] = "en"


class ChatbotMessageRequest(BaseModel):
    message: str
    language: Optional[str] = "en"


@router.get("/health")
def chatbot_health():
    return {
        "success": True,
        "message": "Screening chatbot and calibrated ML prediction service are running.",
    }


@router.post("/predict")
def predict_screening(req: ScreeningPredictRequest):
    try:
        data = req.dict()
        lang = data.get("language") or "en"
        result = screening_ml_service.predict(data, language=lang)
        return result
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Unable to generate the ML screening prediction: {str(e)}",
        )
