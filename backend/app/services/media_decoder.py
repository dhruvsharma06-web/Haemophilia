import cv2


def read_video_frames(video_path: str):
    capture = cv2.VideoCapture(video_path)

    if not capture.isOpened():
        raise ValueError(f"Could not open video: {video_path}")

    try:
        while True:
            success, frame = capture.read()

            if not success:
                break

            yield frame
    finally:
        capture.release()