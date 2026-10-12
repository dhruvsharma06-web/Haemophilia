import unittest
from types import SimpleNamespace
import numpy as np
from src.exercises.shoulder_rotation_assessment import ShoulderRotationAssessment


def pose():
    points = [SimpleNamespace(x=.5, y=.5, z=0., visibility=1.) for _ in range(33)]
    for index, x, y, z in [(11,.4,.3,0),(12,.6,.3,0),(13,.4,.5,0),(14,.6,.5,0),
                           (15,.4,.5,-.15),(16,.6,.5,-.15),(23,.4,.7,0),(24,.6,.7,0)]:
        points[index] = SimpleNamespace(x=x,y=y,z=z,visibility=1.)
    return SimpleNamespace(landmark=points)


class FeatureTests(unittest.TestCase):
    def test_geometric_centre_and_upper_arm_distance(self):
        engine = ShoulderRotationAssessment(None,'cpu',save_artifacts=False)
        feature = engine._extract_feature(pose())
        np.testing.assert_allclose(feature[4:6],90)
        np.testing.assert_allclose(feature[10:14],0)

    def test_bilateral_lateral_motion_does_not_use_flexion(self):
        engine = ShoulderRotationAssessment(None,'cpu',save_artifacts=False)
        landmarks = pose()
        landmarks.landmark[15].x += .06
        landmarks.landmark[16].x += .06
        np.testing.assert_allclose(engine._extract_feature(landmarks)[10:12], [27,27],atol=.001)

    def test_missing_hip_and_nonfinite_landmark_drop_tracking(self):
        engine = ShoulderRotationAssessment(None,'cpu',save_artifacts=False)
        landmarks = pose()
        landmarks.landmark[23].visibility = .1
        self.assertIsNone(engine.process_frame(None,landmarks))
        self.assertFalse(engine.get_live_state(landmarks)['tracking_ok'])
        self.assertEqual(engine.get_live_state(landmarks)['landmarks'],[])
        landmarks = pose()
        landmarks.landmark[15].x = float('nan')
        self.assertIsNone(engine.process_frame(None,landmarks))
        self.assertFalse(engine.tracking_ok)

    def test_azimuth_wrap_does_not_make_velocity_spike(self):
        engine = ShoulderRotationAssessment(None,'cpu',save_artifacts=False)
        landmarks = pose()
        for index in [15,16]:
            landmarks.landmark[index].z = .15
            landmarks.landmark[index].x += .001
        first = engine._extract_feature(landmarks)
        for index in [15,16]: landmarks.landmark[index].x -= .002
        second = engine._extract_feature(landmarks)
        self.assertTrue(np.all(np.abs(second[:2]-first[:2]) < 2))
        self.assertTrue(np.all(np.abs(second[2:4]) < 40))
