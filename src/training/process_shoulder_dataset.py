import os
import subprocess
import sys


EXERCISE_DIR = "dataset/assisted_shoulder_flexion"


def run_command(command):
    print("\n" + "=" * 60)
    print("Running:", " ".join(command))
    print("=" * 60)

    result = subprocess.run(command)

    if result.returncode != 0:
        print("ERROR:", " ".join(command))
        return False

    return True


def process_dataset():

    # Use the SAME Python interpreter running this script
    python_executable = sys.executable

    print("Python interpreter:")
    print(python_executable)

    for label in ["correct", "incorrect"]:

        folder = os.path.join(
            EXERCISE_DIR,
            label
        )

        if not os.path.exists(folder):
            print(f"Folder not found: {folder}")
            continue

        videos = [
            f for f in os.listdir(folder)
            if f.lower().endswith(".mp4")
        ]

        for video in videos:

            video_path = os.path.join(
                folder,
                video
            )

            filename = os.path.splitext(video)[0]

            keypoint_file = os.path.join(
                "processed_data",
                "keypoints",
                f"{filename}_keypoints.csv"
            )

            angle_file = os.path.join(
                "processed_data",
                "angles",
                f"{filename}_angles.csv"
            )

            # -----------------------------
            # 1. Pose extraction
            # -----------------------------

            if os.path.exists(keypoint_file):

                print(
                    f"\nSkipping pose extraction: "
                    f"{video}"
                )

            else:

                success = run_command([
                    python_executable,
                    "src/pose/pose_extraction.py",
                    video_path
                ])

                if not success:
                    continue

            # -----------------------------
            # 2. Angle extraction
            # -----------------------------

            if os.path.exists(angle_file):

                print(
                    f"Skipping angle extraction: "
                    f"{video}"
                )

            else:

                success = run_command([
                    python_executable,
                    "src/features/angle_extraction.py",
                    keypoint_file
                ])

                if not success:
                    continue

            # -----------------------------
            # 3. Rep extraction
            # -----------------------------

            success = run_command([
                python_executable,
                "src/feedback/rep_counter.py",
                angle_file
            ])

            if not success:
                continue

            print(
                f"\nFinished: {video}"
            )

    print("\n")
    print("=" * 60)
    print("SHOULDER DATASET PROCESSING COMPLETE")
    print("=" * 60)


if __name__ == "__main__":
    process_dataset()