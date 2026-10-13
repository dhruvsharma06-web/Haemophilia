package com.example.haemophilia_app

/** Inverse of a clockwise image rotation, in normalized camera coordinates. */
internal fun cameraCoordinates(x: Double, y: Double, rotation: Int): Pair<Double, Double> = when (rotation) {
    90 -> y to (1-x)
    270 -> (1-y) to x
    else -> x to y
}
