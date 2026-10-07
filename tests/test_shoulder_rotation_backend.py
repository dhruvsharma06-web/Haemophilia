"""API checks for uploaded and live shoulder rotation assessment."""
import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import cv2
import numpy as np
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.app.api.routes import assessments, exercises, live
from backend.app.services.assessment_service import AssessmentService
from backend.app.services.exercise_factory import create_assessment, normalize_exercise
from tests.test_shoulder_rotation_timing import Collector, feature


app = FastAPI()
app.include_router(assessments.router)
app.include_router(exercises.router)
app.include_router(live.router)


class BackendTests(unittest.TestCase):
    def test_default_model_is_installed_classifier_and_catalog_is_available(self):
        engine = create_assessment("Shoulder Rotation", save_artifacts=False)
        self.assertEqual(type(engine.model).__name__, "ShoulderRotationTabular")
        with TestClient(app) as client:
            response = client.get("/v1/exercises/shoulder_rotation/health")
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(response.json()["status"], "ready")
            catalog = client.get("/v1/exercises").json()["exercises"]
        shoulder = next(e for e in catalog if e["id"] == "shoulder_rotation")
        self.assertFalse(shoulder["is_work_in_progress"])
        self.assertEqual(shoulder["rep_definition"], "centre -> one side -> centre")

    def test_upload_routes_shoulder_to_service_and_rejects_unknown_exercise(self):
        result = {"exercise": "shoulder_rotation", "rep_count": 2, "reps": []}
        with patch.object(assessments.assessment_service, "assess_video", return_value=result) as service, TestClient(app) as client:
            response = client.post("/v1/assessments/video", data={"exercise": "Shoulder Rotation"},
                                   files={"file": ("exercise.mp4", b"mocked video", "video/mp4")})
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(service.call_args.args[1], "shoulder_rotation")
            response = client.post("/v1/assessments/video", data={"exercise": "unknown"},
                                   files={"file": ("exercise.mp4", b"mocked video", "video/mp4")})
            self.assertEqual(response.status_code, 400)
            self.assertEqual(service.call_count, 1)

    def test_service_samples_60fps_video_at_training_rate_and_releases_capture(self):
        capture = MagicMock()
        capture.get.return_value = 60.0
        capture.isOpened.return_value = True
        frame = np.zeros((16, 16, 3), dtype=np.uint8)
        capture.read.side_effect = [(True, frame)] * 121 + [(False, None)]
        engine = MagicMock()
        engine.process_frame.return_value = None
        pose = MagicMock()
        pose.__enter__.return_value.process.return_value.pose_landmarks = None
        with patch("backend.app.services.assessment_service.cv2.VideoCapture", return_value=capture), \
             patch("backend.app.services.assessment_service.create_assessment", return_value=engine) as factory, \
             patch("backend.app.services.assessment_service.mp_pose.Pose", return_value=pose):
            result = AssessmentService().assess_video("mock.mp4", "shoulder_rotation")
        self.assertEqual(factory.call_args.kwargs["fps"], 20)
        self.assertEqual(engine.process_frame.call_count, 41)
        self.assertEqual(result["rep_count"], 0)
        capture.release.assert_called_once()

    def test_websocket_camera_protocol_reports_completed_reps_and_feedback(self):
        engine = Collector(None, "cpu", fps=20, save_artifacts=False)
        signal = np.concatenate([np.zeros(20), 25 * np.sin(np.linspace(0, 2 * np.pi, 101)), np.zeros(20)])
        signal_iter = iter(signal)
        engine._extract_feature = lambda landmarks: feature(next(signal_iter))
        landmarks = SimpleNamespace(landmark=[SimpleNamespace(x=0.5, y=0.5, z=0, visibility=1) for _ in range(33)])
        pose = MagicMock()
        pose.__enter__.return_value.process.return_value.pose_landmarks = landmarks
        _, encoded = cv2.imencode(".jpg", np.zeros((16, 16, 3), dtype=np.uint8))
        with patch.object(live, "_create_assessment", return_value=engine), \
             patch.object(live.mp_pose, "Pose", return_value=pose), TestClient(app) as client:
            with client.websocket_connect("/v1/assessments/live?exercise=shoulder_rotation") as socket:
                completed = []
                for index in range(len(signal)):
                    socket.send_json({"type": "frame_metadata", "timestamp_ms": index * 50})
                    socket.send_bytes(encoded.tobytes())
                    state = socket.receive_json()
                    self.assertEqual(state["type"], "live_state")
                    if "completed_rep" in state:
                        completed.append(state["completed_rep"])
                self.assertEqual(len(completed), 2)
                self.assertEqual(state["rep_count"], 2)
                self.assertEqual(state["score"], 90)
                self.assertIn("deg/s", state["speed"])
                self.assertTrue(completed[-1]["feedback"])
                self.assertFalse(completed[-1]["confidence_calibrated"])

    def test_aliases_match_app_identifiers(self):
        self.assertEqual(normalize_exercise("Elbow Flexion & Extension"), "elbow_flexion_extension")
        self.assertEqual(normalize_exercise("Assisted Shoulder Flexion with Bar"), "assisted_shoulder_flexion")
        with self.assertRaises(ValueError):
            normalize_exercise("unknown")


if __name__ == "__main__":
    unittest.main()
