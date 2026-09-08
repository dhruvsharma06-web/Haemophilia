import cv2
import mediapipe as mp
import csv
import os
import sys

mp_pose = mp.solutions.pose
mp_drawing = mp.solutions.drawing_utils


def process_video(video_path):

    if not os.path.exists(video_path):
        print(f"Video not found: {video_path}")
        return

    filename = os.path.splitext(os.path.basename(video_path))[0]

    keypoint_dir = "processed_data/keypoints"
    video_dir = "processed_data/video_clips"

    os.makedirs(keypoint_dir, exist_ok=True)
    os.makedirs(video_dir, exist_ok=True)

    keypoint_file = os.path.join(
        keypoint_dir,
        f"{filename}_keypoints.csv"
    )

    output_video = os.path.join(
        video_dir,
        f"{filename}_pose.mp4"
    )

    cap = cv2.VideoCapture(video_path)

    if not cap.isOpened():
        print("Could not open video.")
        return

    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS)

    if fps <= 0:
        fps = 30

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")

    writer = cv2.VideoWriter(
        output_video,
        fourcc,
        fps,
        (width, height)
    )

    # CSV headers
    headers = ["frame"]

    for i in range(33):
        headers.extend([
            f"landmark_{i}_x",
            f"landmark_{i}_y",
            f"landmark_{i}_z",
            f"landmark_{i}_visibility"
        ])

    pose = mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        smooth_landmarks=True,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5
    )

    frame_number = 0

    with open(keypoint_file, "w", newline="") as f:

        csv_writer = csv.writer(f)
        csv_writer.writerow(headers)

        while True:

            ret, frame = cap.read()

            if not ret:
                break

            # NO ROTATION
            # The original video orientation is correct.

            rgb = cv2.cvtColor(
                frame,
                cv2.COLOR_BGR2RGB
            )

            results = pose.process(rgb)

            row = [frame_number]

            if results.pose_landmarks:

                for landmark in results.pose_landmarks.landmark:
                    row.extend([
                        landmark.x,
                        landmark.y,
                        landmark.z,
                        landmark.visibility
                    ])

                # Draw 33 pose landmarks
                mp_drawing.draw_landmarks(
                    frame,
                    results.pose_landmarks,
                    mp_pose.POSE_CONNECTIONS
                )

            else:

                # No pose detected
                row.extend([0] * (33 * 4))

            csv_writer.writerow(row)

            writer.write(frame)

            # Resize only the preview window
            display = frame.copy()

            max_width = 1200
            max_height = 700

            h, w = display.shape[:2]

            scale = min(
                max_width / w,
                max_height / h,
                1.0
            )

            if scale < 1:

                display = cv2.resize(
                    display,
                    (
                        int(w * scale),
                        int(h * scale)
                    )
                )

            cv2.imshow(
                "Pose Extraction",
                display
            )

            key = cv2.waitKey(1) & 0xFF

            if key == ord("q"):
                print("\nStopped by user.")
                break

            frame_number += 1

    cap.release()
    writer.release()
    pose.close()
    cv2.destroyAllWindows()

    print()
    print("Pose extraction completed!")
    print(f"Frames processed: {frame_number}")
    print(f"Keypoints: {keypoint_file}")
    print(f"Video:     {output_video}")


if __name__ == "__main__":

    if len(sys.argv) < 2:

        print("Usage:")
        print(
            'python src\\pose\\pose_extraction.py "path\\to\\video.mp4"'
        )

        sys.exit(1)

    process_video(sys.argv[1])