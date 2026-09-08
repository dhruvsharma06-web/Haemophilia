import cv2

video_path = r"dataset\assisted_shoulder_flexion\correct\20260825_121824.mp4"

cap = cv2.VideoCapture(video_path)

ret, frame = cap.read()
cap.release()

if not ret:
    print("Could not read video")
    exit()

rotations = {
    "ORIGINAL": frame,
    "CLOCKWISE": cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE),
    "COUNTER_CLOCKWISE": cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE),
    "180_DEGREES": cv2.rotate(frame, cv2.ROTATE_180),
}

for name, image in rotations.items():

    h, w = image.shape[:2]

    scale = min(700 / h, 700 / w, 1)

    if scale < 1:
        image = cv2.resize(
            image,
            (int(w * scale), int(h * scale))
        )

    cv2.imshow(name, image)

print("Four windows opened.")
print("Look for the window where the person is upright.")
print("Press Q to close.")

while True:
    key = cv2.waitKey(100) & 0xFF

    if key == ord("q"):
        break

cv2.destroyAllWindows()