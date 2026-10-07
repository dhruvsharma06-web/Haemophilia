"""Compact biomechanical summaries and a Torch-compatible sklearn adapter."""
from pathlib import Path

import numpy as np
import torch


def summary_features(sequence, relative=False):
    """Use the same normalized (128,10) sequence as the live LSTM adapter.

    Percentile ranges reduce single-frame landmark spikes. Relative summaries
    additionally remove the repetition's initial camera-relative offsets.
    Visibility is used for extraction quality, not as a correctness predictor.
    """
    x = np.asarray(sequence, dtype=np.float64).copy()
    if x.shape != (128, 10) or not np.isfinite(x).all():
        raise ValueError("Expected a finite (128,10) normalized sequence.")
    base = np.median(x[:5], axis=0)
    if relative:
        x[:, [0, 1, 8, 9]] -= base[[0, 1, 8, 9]]
    values = []
    for column in [0, 1, 4, 5, 8, 9]:
        signal = x[:, column]
        q05, q50, q95 = np.percentile(signal, [5, 50, 95])
        values.extend([q50, q95 - q05, np.percentile(np.abs(signal), 90),
                       np.percentile(np.abs(signal - signal[0]), 90)])
    # Side-independent movement shape, bilateral disagreement and compensation.
    right, left = x[:, 0] - x[0, 0], x[:, 1] - x[0, 1]
    values.extend([np.percentile(np.abs(right - left), 90),
                   abs(np.ptp(right) - np.ptp(left)),
                   np.percentile(np.abs(x[:, 4] - x[:, 5]), 90),
                   np.median(np.abs(np.diff(right, n=2))),
                   np.median(np.abs(np.diff(left, n=2)))])
    for column in [2, 3]:
        values.extend([np.median(np.abs(x[:, column])), np.percentile(np.abs(x[:, column]), 90)])
    return np.asarray(values, dtype=np.float32)


class ShoulderRotationTabular(torch.nn.Module):
    """Inference adapter for locally trained sklearn pipelines.

    SVM decision scores are converted to logits, not calibrated probabilities.
    Other estimators' probability outputs are also uncalibrated estimates.
    """
    def __init__(self, estimator, relative=False):
        super().__init__()
        self.estimator = estimator
        self.relative = relative

    def forward(self, sequence):
        features = np.stack([summary_features(row, self.relative)
                             for row in sequence.detach().cpu().numpy()])
        if hasattr(self.estimator, "predict_proba"):
            probabilities = np.clip(self.estimator.predict_proba(features), 1e-7, 1)
            logits = np.log(probabilities)
        else:
            score = self.estimator.decision_function(features)
            logits = np.column_stack([-score / 2, score / 2])
        return torch.as_tensor(logits, dtype=sequence.dtype, device=sequence.device)


def load_tabular_model(path):
    # Only load the artifact produced locally by the comparison script.
    import joblib
    artifact = joblib.load(Path(path))
    if not np.array_equal(artifact["estimator"].classes_, [0, 1]):
        raise ValueError("Shoulder rotation classes must be 0=correct and 1=incorrect.")
    if artifact["estimator"].n_features_in_ != 33:
        raise ValueError("This classifier must use the 33-feature shoulder summary.")
    return ShoulderRotationTabular(artifact["estimator"], artifact["relative"]).eval()
