import hashlib

import torch
from fastapi import APIRouter, HTTPException
from backend.app.services.model_registry import model_registry

router = APIRouter(prefix="/v1", tags=["Exercises"])


@router.get("/exercises/shoulder_rotation/health")
def shoulder_rotation_health():
    """Verify the deployed model actually loads and runs, rather than just listing it."""
    try:
        model, device = model_registry.get_shoulder_rotation()
        with torch.no_grad():
            output = model(torch.zeros(1, 128, 10, device=device))
        if output.shape != (1, 2) or not torch.isfinite(output).all():
            raise ValueError("Model inference failed.")
        return {"exercise": "shoulder_rotation", "status": "ready",
                "model_type": type(model).__name__,
                "checkpoint_sha256": hashlib.sha256(model_registry.shoulder_rotation_model_path.read_bytes()).hexdigest(),
                "rep_definition": "centre -> one side -> centre"}
    except Exception as error:
        raise HTTPException(status_code=503, detail=f"Shoulder model unavailable: {error}") from error


@router.get("/exercises")
def get_exercises():
    return {
        "exercises": [
            {
                "id": "assisted_shoulder_flexion",
                "name": "Assisted Shoulder Flexion with Bar",
                "target_joint": "Shoulders",
                "status": "validated",
                "available": True,
                "is_work_in_progress": False,
                "description": (
                    "Two-handed bar elevation exercise targeting shoulder mobility "
                    "and joint preservation."
                ),
            },
            {
                "id": "shoulder_rotation",
                "name": "Shoulder Rotation",
                "target_joint": "Rotator Cuff",
                "status": "available",
                "available": True,
                "is_work_in_progress": False,
                "rep_definition": "centre -> one side -> centre",
                "description": (
                    "Hold the bar at centre, rotate to one side, then return to centre. "
                    "Each centre-to-side-to-centre movement counts as one repetition."
                ),
            },
            {
                "id": "assisted_elbow_flexion",
                "name": "Assisted Elbow Flexion",
                "target_joint": "Elbow Joint",
                "status": "validated",
                "available": True,
                "is_work_in_progress": False,
                "description": (
                    "Supported elbow bending using contralateral hand guidance to "
                    "protect recovering joints."
                ),
            },
            {
                "id": "elbow_flexion_extension",
                "name": "Elbow Flexion & Extension",
                "target_joint": "Elbow Joint",
                "status": "validated",
                "available": True,
                "is_work_in_progress": False,
                "description": (
                    "Smooth, controlled elbow bending and straightening throughout "
                    "comfortable pain-free range of motion."
                ),
            },
        ]
    }
