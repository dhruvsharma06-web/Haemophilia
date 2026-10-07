"""Install a verified shoulder classifier bundle for the backend."""
import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from src.models.shoulder_rotation_loader import load_shoulder_rotation_model


def install(source, destination):
    source, destination = Path(source), Path(destination)
    if destination.exists():
        raise ValueError("Destination exists. Preserve it and select a new destination.")
    artifact = source / "shoulder_rotation_classifier.joblib"
    config = json.loads((source / "config.json").read_text())
    hashes = json.loads((source / "checkpoint_sha256.json").read_text())
    if hashlib.sha256(artifact.read_bytes()).hexdigest() != hashes[artifact.name]:
        raise ValueError("Model checksum does not match its recorded artifact.")
    if config.get("model_type") != "shoulder_rotation_tabular" or config.get("sequence_shape") != [128, 10]:
        raise ValueError("Expected the shoulder rotation 128-by-10 classifier.")
    model, device = load_shoulder_rotation_model(artifact)
    with torch.no_grad():
        output = model(torch.from_numpy(np.zeros((1, 128, 10), dtype=np.float32)).to(device))
    if output.shape != (1, 2) or not torch.isfinite(output).all():
        raise ValueError("Model inference check failed.")
    destination.mkdir(parents=True)
    for filename in [artifact.name, "config.json", "checkpoint_sha256.json", "environment.txt", "summary.json"]:
        shutil.copy2(source / filename, destination / filename)
    print(f"Installed verified shoulder classifier: {destination / artifact.name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default=str(ROOT / "models/shoulder_rotation_improved01"))
    parser.add_argument("--destination", default=str(ROOT / "models/shoulder_rotation"))
    try:
        args = parser.parse_args()
        install(args.source, args.destination)
    except (ValueError, FileNotFoundError, KeyError) as error:
        parser.exit(1, f"Error: {error}\n")
