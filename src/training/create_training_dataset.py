import pandas as pd
from pathlib import Path

# Project paths
BASE_DIR = Path(__file__).resolve().parents[2]
ANGLES_DIR = BASE_DIR / "processed_data" / "angles"
OUTPUT_FILE = BASE_DIR / "processed_data" / "shoulder_training_data.csv"

all_data = []

# Find all rep-level CSV files
rep_files = sorted(ANGLES_DIR.glob("*_reps.csv"))

if not rep_files:
    print("No *_reps.csv files found.")
    exit()

for file in rep_files:
    df = pd.read_csv(file)

    # Video ID
    video_id = file.stem.replace("_reps", "")

    df["video_id"] = video_id

    all_data.append(df)

# Combine everything
combined = pd.concat(all_data, ignore_index=True)

# Keep useful columns
columns = [
    "video_id",
    "rep",
    "exercise",
    "min_angle",
    "max_angle",
    "range_of_motion",
    "duration",
    "speed_deg_per_sec",
    "speed",
    "smoothness",
    "label"
]

combined = combined[columns]

# Save
OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
combined.to_csv(OUTPUT_FILE, index=False)

print("\nTraining dataset created successfully!")
print(f"File: {OUTPUT_FILE}")
print(f"Total reps: {len(combined)}")

print("\nLabel distribution:")
print(combined["label"].value_counts())

print("\nReps per video:")
print(combined.groupby(["video_id", "label"]).size())