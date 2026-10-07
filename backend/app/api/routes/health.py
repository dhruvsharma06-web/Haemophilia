from fastapi import APIRouter

router = APIRouter(tags=["Health"])


@router.get("/health")
def health():
    return {"status": "ok", "release": "2026-10-07-session-expiry-elbow-v4"}
