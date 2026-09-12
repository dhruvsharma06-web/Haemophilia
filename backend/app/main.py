from fastapi import FastAPI

from backend.app.api.routes.health import (
    router as health_router,
)

from backend.app.api.routes.exercises import (
    router as exercises_router,
)

from backend.app.api.routes.assessments import (
    router as assessments_router,
)

from backend.app.api.routes.assets import (
    router as assets_router,
)

from backend.app.api.routes.live import (
    router as live_router,
)


app = FastAPI(
    title="Haemophilia Physiotherapy AI",
    version="1.0.0",
)


# ============================================================
# API ROUTES
# ============================================================

app.include_router(
    health_router,
)

app.include_router(
    exercises_router,
)

app.include_router(
    assessments_router,
)

app.include_router(
    assets_router,
)

app.include_router(
    live_router,
)


# ============================================================
# ROOT
# ============================================================

@app.get("/")
def root():
    return {
        "name": "Haemophilia Physiotherapy AI",
        "status": "running",
        "version": "1.0.0",
    }