"""Phase 9 Research Deployment Adapter.

Implements pure NumPy inference for the Phase 9 optimized candidate model:
- Median imputation using exported Phase 9 imputer statistics
- Standard scaling using exported Phase 9 scaler mean and scale
- RBF SVM decision function using exported support vectors, dual coefficients, and intercept
- Strict parity verification with scikit-learn reference implementation

Hard Invariants:
- Research-only adapter under research/assisted_elbow_flexion_v2/phase9/
- Does NOT alter production code, Flutter, backend, or Phase 4 deployment adapter
"""

import json
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union
import numpy as np

PHASE9_DIR = Path(__file__).resolve().parent
DEFAULT_CHECKPOINT = PHASE9_DIR / "checkpoints" / "final_model_v2_optimized_parameters.json"

class Phase9ModelAdapter:
    """Pure NumPy research inference adapter for Phase 9 optimized candidate."""

    def __init__(self, checkpoint_path: Optional[Union[str, Path]] = None):
        self.checkpoint_path = Path(checkpoint_path or DEFAULT_CHECKPOINT)
        if not self.checkpoint_path.exists():
            raise FileNotFoundError(f"Checkpoint not found at {self.checkpoint_path}")

        with open(self.checkpoint_path, "r", encoding="utf-8") as f:
            self.params = json.load(f)

        assert self.params["algorithm"] == "RBF_SVM"
        assert len(self.params["feature_names"]) == 34
        assert self.params["classes"] == [0, 1]

        self.feature_names = self.params["feature_names"]
        self.support_vectors = np.array(self.params["support_vectors"], dtype=np.float64)
        self.dual_coefficients = np.array(self.params["dual_coefficients"][0], dtype=np.float64)
        self.intercept = float(self.params["intercept"])
        self.gamma = float(self.params.get("effective_gamma", 0.04))
        self.threshold = float(self.params.get("decision_threshold", 0.0))

        self.imputer_statistics = np.array(self.params["imputer_statistics"], dtype=np.float64)
        self.scaler_mean = np.array(self.params["scaler_mean"], dtype=np.float64)
        self.scaler_scale = np.array(self.params["scaler_scale"], dtype=np.float64)

    def preprocess(self, raw_features: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """Apply median imputation and standard scaling."""
        is_1d = (raw_features.ndim == 1)
        X = np.atleast_2d(raw_features.copy())

        # Impute missing values with median statistics
        nan_mask = np.isnan(X)
        imputed = np.where(nan_mask, self.imputer_statistics[None, :], X)

        # Standard scaling
        scaled = (imputed - self.scaler_mean[None, :]) / self.scaler_scale[None, :]

        if is_1d:
            return imputed[0], scaled[0]
        return imputed, scaled

    def decision_function(self, scaled_features: np.ndarray) -> Union[float, np.ndarray]:
        """Compute exact RBF SVM decision function score via vectorized NumPy math:
        K(x, s) = exp(-gamma * ||x - s||^2)
        score = sum(alpha_i * K(x, s_i)) + intercept
        """
        is_1d = (scaled_features.ndim == 1)
        X = np.atleast_2d(scaled_features)

        # Squared Euclidean distances to all support vectors: (N, N_sv)
        diff = X[:, None, :] - self.support_vectors[None, :, :]
        dist_sq = np.sum(diff ** 2, axis=-1)
        kernel = np.exp(-self.gamma * dist_sq)
        scores = np.dot(kernel, self.dual_coefficients) + self.intercept

        return float(scores[0]) if is_1d else scores

    def predict(self, raw_features: np.ndarray) -> Tuple[Union[int, np.ndarray], Union[float, np.ndarray]]:
        """End-to-end prediction from raw 34-feature vector(s).
        Returns:
            (predicted_class, decision_score)
            0 = Correct, 1 = Incorrect
        """
        is_1d = (raw_features.ndim == 1)
        _, scaled = self.preprocess(raw_features)
        scores = self.decision_function(scaled)

        if is_1d:
            pred = int(scores > self.threshold)
            return pred, float(scores)
        else:
            preds = (scores > self.threshold).astype(int)
            return preds, scores
