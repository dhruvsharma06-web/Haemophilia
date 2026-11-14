from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os

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

from backend.app.api.routes.notifications import (
    router as notifications_router,
)

from backend.app.api.routes.chatbot import (
    router as chatbot_router,
)


app = FastAPI(
    title="Haemophilia Physiotherapy AI",
    version="1.0.0",
)

# Opt-in browser testing; production keeps its existing CORS behavior.
if os.environ.get('HEMO_LOCAL_BROWSER') == '1':
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=r'http://(localhost|127\.0\.0\.1)(:\d+)?',
        allow_methods=['GET', 'POST'],
        allow_headers=['*'],
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

app.include_router(
    notifications_router,
)

app.include_router(
    chatbot_router,
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
