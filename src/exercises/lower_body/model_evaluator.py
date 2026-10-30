import logging
from pathlib import Path
from typing import Any, Dict, List, Optional
import warnings
import numpy as np

try:
    import joblib
except ImportError:
    joblib = None

try:
    from src.exercises.lower_body.feature_extractor import extract_repetition_features
except ImportError:
    extract_repetition_features = None

logger = logging.getLogger("LowerBodyModelEvaluator")

MODELS_DIR = (
    Path(__file__).resolve().parents[3]
    / "backend"
    / "app"
    / "ml"
    / "lower_body"
)

MODEL_FILE_MAP = {
    "mini_squat": "mini_squat_rf.pkl",
    "seated_knee_extension": "seated_knee_extensions_rf.pkl",
    "straight_leg_raise": "straight_leg_raise_rf.pkl",
}


class LowerBodyModelEvaluator:
    """Singleton loader and inference runner for lower-body ML models."""

    _instance = None
    _loaded_bundles: Dict[str, Dict[str, Any]] = {}
    _load_errors: Dict[str, str] = {}

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(LowerBodyModelEvaluator, cls).__new__(cls)
            cls._instance._init_models()
        return cls._instance

    def _init_models(self):
        """Pre-load available models once at startup."""
        if joblib is None:
            logger.warning("joblib is not installed; ML inference disabled.")
            return

        # Pickled sklearn estimators are not supported across sklearn versions.
        # Keep the research artifacts, but do not silently hide a mismatch.
        for ex_id, filename in MODEL_FILE_MAP.items():
            model_path = MODELS_DIR / filename
            if model_path.exists():
                try:
                    with warnings.catch_warnings():
                        from sklearn.exceptions import InconsistentVersionWarning
                        warnings.simplefilter("error", InconsistentVersionWarning)
                        bundle = joblib.load(model_path)
                    self._validate_bundle_structure(ex_id, bundle)
                    self._loaded_bundles[ex_id] = bundle
                    logger.info("Successfully loaded ML model for %s from %s", ex_id, filename)
                except Exception as exc:
                    err_msg = f"Failed to load model {filename}: {exc}"
                    self._load_errors[ex_id] = err_msg
                    logger.warning(err_msg)
            else:
                self._load_errors[ex_id] = f"Artifact not found: {filename}"

    def _validate_bundle_structure(self, ex_id: str, bundle: Dict[str, Any]):
        """Verify the bundle matches the expected senior schema."""
        for required_key in ("models", "labels", "feature_names", "impute_median"):
            if required_key not in bundle:
                raise ValueError(f"Bundle for {ex_id} missing required key '{required_key}'")

        models = bundle["models"]
        labels = bundle["labels"]
        for lbl in labels:
            if lbl not in models:
                raise ValueError(f"Bundle for {ex_id} missing estimator for label '{lbl}'")

    def has_model(self, exercise_name: str) -> bool:
        return exercise_name in self._loaded_bundles

    def get_labels(self, exercise_name: str) -> List[str]:
        if exercise_name in self._loaded_bundles:
            return list(self._loaded_bundles[exercise_name].get("labels", []))
        return []

    def get_feature_count(self, exercise_name: str) -> int:
        if exercise_name in self._loaded_bundles:
            return len(self._loaded_bundles[exercise_name].get("feature_names", []))
        return 0

    def evaluate_repetition(
        self,
        exercise_name: str,
        rep_kinematics: List[Dict[str, Any]],
        rule_errors: List[str],
        landmark_frames: Optional[List[Any]] = None,
        simulated_error: Optional[Exception] = None,
    ) -> Dict[str, Any]:
        """
        Evaluate a completed repetition using the trained model if available.
        Maintains strict separation between rule-based and ML outputs.
        """
        # If exercise has no trained model in repository
        if exercise_name not in MODEL_FILE_MAP:
            return {
                "status": "rule_based_only",
                "has_trained_model": False,
                "message": (
                    "Biomechanical rule-based assessment only; no trained ML model "
                    f"packaged for {exercise_name}."
                ),
                "predicted_errors": [],
                "label_predictions": {},
                "label_probabilities": {},
            }

        # If model failed to load at startup
        if exercise_name not in self._loaded_bundles:
            err_detail = self._load_errors.get(exercise_name, "Model not loaded")
            return {
                "status": "prediction_unavailable",
                "has_trained_model": False,
                "error": err_detail,
                "predicted_errors": [],
                "label_predictions": {},
                "label_probabilities": {},
            }

        # Simulated exception for testing error handling
        if simulated_error is not None:
            logger.error("Simulated inference exception on %s: %s", exercise_name, simulated_error)
            return {
                "status": "prediction_failed",
                "has_trained_model": True,
                "error": str(simulated_error),
                "predicted_errors": [],
                "label_predictions": {},
                "label_probabilities": {},
            }

        bundle = self._loaded_bundles[exercise_name]
        labels = bundle.get("labels", [])
        feature_names = bundle.get("feature_names", [])
        impute_median = bundle.get("impute_median", {})
        models = bundle.get("models", {})

        try:
            # 1. Extract live aggregated features from raw landmark frames if available
            live_features: Dict[str, float] = {}
            if landmark_frames and len(landmark_frames) >= 2 and extract_repetition_features is not None:
                try:
                    live_features = extract_repetition_features(exercise_name, landmark_frames)
                except Exception as ext_err:
                    logger.warning("Feature extractor error for %s: %s", exercise_name, ext_err)
                    live_features = {}

            # 2. Construct feature vector X strictly aligned with feature_names
            X_vec = np.zeros(len(feature_names), dtype=np.float64)
            live_count = 0
            imputed_count = 0

            for i, fname in enumerate(feature_names):
                if fname in live_features and not np.isnan(live_features[fname]):
                    X_vec[i] = float(live_features[fname])
                    live_count += 1
                else:
                    X_vec[i] = float(impute_median.get(fname, 0.0))
                    imputed_count += 1

            # Fallback kinematics update if raw landmarks were absent but kinematics present
            if live_count == 0 and rep_kinematics:
                for fname in feature_names:
                    for metric in ["angle", "left_angle", "right_angle"]:
                        if fname.startswith(f"{metric}__"):
                            vals = [float(k[metric]) for k in rep_kinematics if metric in k]
                            if vals:
                                agg = fname.split("__")[-1]
                                idx = feature_names.index(fname)
                                if agg == "min":
                                    X_vec[idx] = float(np.min(vals))
                                elif agg == "max":
                                    X_vec[idx] = float(np.max(vals))
                                elif agg == "mean":
                                    X_vec[idx] = float(np.mean(vals))
                                elif agg == "std":
                                    X_vec[idx] = float(np.std(vals))
                                live_count += 1

            X = X_vec.reshape(1, -1)
            if live_count == 0:
                return {
                    "status": "insufficient_observations",
                    "has_trained_model": True,
                    "predicted_errors": [], "label_predictions": {},
                    "label_probabilities": {},
                    "message": "No observed model features; prediction withheld.",
                }
            predictions = {}
            probabilities = {}
            triggered_errors = []

            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                for lbl in labels:
                    clf = models.get(lbl)
                    if clf is None:
                        raise RuntimeError(f"Missing classifier for label '{lbl}'")

                    pred = int(clf.predict(X)[0])
                    if hasattr(clf, "predict_proba"):
                        classes = list(clf.classes_)
                        prob = float(clf.predict_proba(X)[0][classes.index(1)]) if 1 in classes else 0.0
                    else:
                        prob = 1.0 if pred else 0.0
                    predictions[lbl] = bool(pred)
                    probabilities[lbl] = round(prob, 3)
                    if pred:
                        triggered_errors.append(lbl)

            return {
                "status": "model_evaluated",
                "experimental": True,
                "clinically_validated": False,
                "used_for_rep_verdict": False,
                "validation_note": "Single-participant research model; generalization not established. See model_card.json.",
                "has_trained_model": True,
                "model_type": bundle.get("model_kind", "RandomForest"),
                "predicted_errors": triggered_errors,
                "label_predictions": predictions,
                "label_probabilities": probabilities,
                "live_feature_count": live_count,
                "imputed_feature_count": imputed_count,
                "total_features": len(feature_names),
            }

        except Exception as exc:
            err_str = f"ML inference error during {exercise_name} prediction: {type(exc).__name__}: {exc}"
            logger.error(err_str, exc_info=True)
            return {
                "status": "prediction_failed",
                "has_trained_model": True,
                "error": err_str,
                "predicted_errors": [],
                "label_predictions": {},
                "label_probabilities": {},
            }


model_evaluator = LowerBodyModelEvaluator()
