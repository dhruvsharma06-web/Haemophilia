from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse


router = APIRouter(
    prefix="/v1/assets",
    tags=["Assets"],
)

ERROR_FRAMES_DIR = (
    Path(__file__).resolve().parents[4]
    / "data"
    / "error_frames"
)


@router.get("/error-frames/{filename}")
def get_error_frame(filename: str):

    # Prevent path traversal.
    safe_name = Path(filename).name

    file_path = ERROR_FRAMES_DIR / safe_name

    if not file_path.exists() or not file_path.is_file():
        raise HTTPException(
            status_code=404,
            detail="Error frame not found.",
        )

    return FileResponse(
        path=file_path,
        media_type="image/jpeg",
        filename=safe_name,
    )