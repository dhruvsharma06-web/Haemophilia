import os
import shutil
import tempfile
import traceback

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from starlette.concurrency import run_in_threadpool

from backend.app.services.assessment_service import assessment_service
from backend.app.services.exercise_factory import normalize_exercise
from backend.app.core.config import UPLOADS_DIR


router = APIRouter(
    prefix="/v1/assessments",
    tags=["Assessments"],
)


@router.post("/video")
async def assess_video(
    file: UploadFile = File(...),
    exercise: str = Form(...),
):
    if not file.filename:
        raise HTTPException(
            status_code=400,
            detail="No video file supplied.",
        )

    try:
        exercise = normalize_exercise(exercise)
    except ValueError as error:
        raise HTTPException(
            status_code=400,
            detail=str(error),
        ) from error

    suffix = os.path.splitext(file.filename)[1].lower()

    if suffix not in {".mp4", ".mov", ".avi", ".mkv"}:
        raise HTTPException(
            status_code=400,
            detail="Unsupported video format.",
        )

    temp_path = None

    try:
        with tempfile.NamedTemporaryFile(
            delete=False,
            suffix=suffix,
            dir=UPLOADS_DIR,
        ) as temp_file:
            temp_path = temp_file.name

            shutil.copyfileobj(
                file.file,
                temp_file,
            )

        result = await run_in_threadpool(
            assessment_service.assess_video,
            temp_path,
            exercise,
        )

        return result

    except ValueError as exc:
        raise HTTPException(
            status_code=400,
            detail=str(exc),
        )

    except Exception as exc:
        traceback.print_exc()

        raise HTTPException(
            status_code=500,
            detail=f"Assessment failed: {exc}",
        )

    finally:
        if temp_path and os.path.exists(temp_path):
            os.remove(temp_path)
