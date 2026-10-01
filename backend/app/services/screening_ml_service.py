import os
import joblib
import pandas as pd
from typing import Dict, Any, List

BASE_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ml"
)
MODEL_PATH = os.path.join(BASE_DIR, "hemophilia_chatbot_calibrated_model.pkl")
FEATURE_INFO_PATH = os.path.join(BASE_DIR, "chatbot_model_features.pkl")

CLASS_LABELS = {
    0: "Healthy",
    1: "Mild",
    2: "Moderate",
    3: "Severe",
}

CLASS_LABELS_HI = {
    0: "स्वस्थ",
    1: "हल्का",
    2: "मध्यम",
    3: "गंभीर",
}

EXPECTED_FEATURES = [
    "age",
    "sex",
    "prolonged_bleeding_minor_cut",
    "excessive_post_surgery_bleeding",
    "excessive_dental_bleeding",
    "easy_bruising",
    "muscle_hematoma",
    "recurrent_joint_bleeding",
    "joint_warmth",
    "joint_tightness",
    "reduced_joint_mobility",
    "hematuria",
    "hematochezia",
    "family_history_bleeding_disorder",
    "male_relative_with_hemophilia",
    "previous_factor_test",
]


class ScreeningMLService:
    def __init__(self):
        self.model = None
        self.feature_info = None
        self.features: List[str] = EXPECTED_FEATURES
        self._load_artifacts()

    def _load_artifacts(self):
        try:
            if os.path.exists(MODEL_PATH):
                self.model = joblib.load(MODEL_PATH)
            if os.path.exists(FEATURE_INFO_PATH):
                self.feature_info = joblib.load(FEATURE_INFO_PATH)
                self.features = self.feature_info.get("features", EXPECTED_FEATURES)
        except Exception as e:
            print(f"[ScreeningMLService] Warning loading artifacts: {e}")

    @staticmethod
    def _normalize_text(value: Any) -> str:
        if value is None:
            return ""
        return str(value).strip().lower()

    @classmethod
    def encode_sex(cls, value: Any) -> int:
        norm = cls._normalize_text(value)
        if norm in ["male", "m", "0"]:
            return 0
        if norm in ["female", "f", "1"]:
            return 1
        return 0

    @classmethod
    def encode_binary(cls, value: Any) -> int:
        norm = cls._normalize_text(value)
        if norm in ["yes", "y", "true", "1", "positive"]:
            return 1
        return 0

    @classmethod
    def encode_ordinal(cls, value: Any) -> int:
        norm = cls._normalize_text(value)
        if norm in ["never", "0"]:
            return 0
        if norm in ["sometimes", "1"]:
            return 1
        if norm in ["often", "2"]:
            return 2
        try:
            num = int(float(norm))
            if num in [0, 1, 2]:
                return num
        except Exception:
            pass
        return 0

    def predict(self, data: Dict[str, Any], language: str = "en") -> Dict[str, Any]:
        if not self.model:
            self._load_artifacts()
            if not self.model:
                raise RuntimeError("Screening ML model is not available.")

        # Age
        try:
            age = float(data.get("age", 0))
        except Exception:
            age = 0.0
        age = max(0.0, min(120.0, age))

        features_dict: Dict[str, Any] = {
            "age": age,
            "sex": self.encode_sex(data.get("sex")),
            "prolonged_bleeding_minor_cut": self.encode_ordinal(
                data.get("prolonged_bleeding_minor_cut")
            ),
            "easy_bruising": self.encode_ordinal(data.get("easy_bruising")),
        }

        binary_keys = [
            "excessive_post_surgery_bleeding",
            "excessive_dental_bleeding",
            "muscle_hematoma",
            "recurrent_joint_bleeding",
            "joint_warmth",
            "joint_tightness",
            "reduced_joint_mobility",
            "hematuria",
            "hematochezia",
            "family_history_bleeding_disorder",
            "male_relative_with_hemophilia",
            "previous_factor_test",
        ]

        for k in binary_keys:
            features_dict[k] = self.encode_binary(data.get(k))

        input_df = pd.DataFrame(
            [[features_dict[f] for f in self.features]],
            columns=self.features,
        )

        prediction_val = int(self.model.predict(input_df)[0])
        probabilities_raw = self.model.predict_proba(input_df)[0]

        prob_map: Dict[str, float] = {}
        for class_val, prob in zip(self.model.classes_, probabilities_raw):
            prob_map[str(int(class_val))] = round(float(prob), 4)

        prediction_confidence = prob_map.get(str(prediction_val), 0.0)
        prediction_label = CLASS_LABELS.get(prediction_val, "Unknown")
        display_label = (
            CLASS_LABELS_HI.get(prediction_val, "अज्ञात")
            if language == "hi"
            else prediction_label
        )

        return {
            "success": True,
            "prediction": prediction_val,
            "predictionLabel": prediction_label,
            "displayLabel": display_label,
            "predictionConfidence": prediction_confidence,
            "probabilities": prob_map,
            "features": features_dict,
            "language": language,
        }


screening_ml_service = ScreeningMLService()
