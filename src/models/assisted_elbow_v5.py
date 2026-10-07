"""Frozen V5 research SVM export. Decision margins are not probabilities."""
import json
from pathlib import Path
import numpy as np


class AssistedElbowV5Model:
    def __init__(self):
        p = json.loads((Path(__file__).resolve().parents[2] / 'models' /
                        'assisted_elbow_v5_parameters.json').read_text())
        self.indices = np.asarray(p['feature_indices'], int)
        self.impute = np.asarray(p['imputer_statistics'], float)
        self.mean = np.asarray(p['scaler_mean'], float)
        self.scale = np.asarray(p['scaler_scale'], float)
        self.support = np.asarray(p['support_vectors'], float)
        self.dual = np.asarray(p['dual_coef'], float)
        self.intercept = float(p['intercept'])
        self.gamma = float(p['gamma'])
        self.feature_count = int(p['input_feature_count'])

    def decision_function(self, features):
        rows = np.atleast_2d(np.asarray(features, float))
        if rows.shape[1] != self.feature_count:
            raise ValueError('Unexpected V5 feature schema')
        selected = rows[:, self.indices]
        selected = np.where(np.isfinite(selected), selected, self.impute)
        scaled = (selected - self.mean) / self.scale
        squared = np.sum((scaled[:, None, :] - self.support[None, :, :]) ** 2, axis=2)
        return np.exp(-self.gamma * squared) @ self.dual + self.intercept

    def predict(self, features):
        return (self.decision_function(features) > 0).astype(int)
