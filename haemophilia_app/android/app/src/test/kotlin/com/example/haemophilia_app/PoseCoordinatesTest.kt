package com.example.haemophilia_app

import org.junit.Assert.assertEquals
import org.junit.Test

class PoseCoordinatesTest {
    @Test fun sidewaysPoseReturnsToOriginalCameraCoordinates() {
        val clockwise = cameraCoordinates(.7, .2, 90)
        assertEquals(.2, clockwise.first, 1e-9)
        assertEquals(.3, clockwise.second, 1e-9)
        val counterClockwise = cameraCoordinates(.3, .8, 270)
        assertEquals(.2, counterClockwise.first, 1e-9)
        assertEquals(.3, counterClockwise.second, 1e-9)
    }
    @Test fun cornersDoNotFlipOrSwapPreviewAxes() {
        assertEquals(0.0 to 1.0, cameraCoordinates(0.0, 0.0, 90))
        assertEquals(1.0 to 0.0, cameraCoordinates(0.0, 0.0, 270))
        assertEquals(.2 to .3, cameraCoordinates(.2, .3, 0))
    }
}
