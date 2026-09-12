from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
BACKEND_DATA_DIR = PROJECT_ROOT / "backend" / "data"
UPLOADS_DIR = BACKEND_DATA_DIR / "uploads"
ASSESSMENTS_DIR = BACKEND_DATA_DIR / "assessments"

for directory in (UPLOADS_DIR, ASSESSMENTS_DIR):
    directory.mkdir(parents=True, exist_ok=True)
