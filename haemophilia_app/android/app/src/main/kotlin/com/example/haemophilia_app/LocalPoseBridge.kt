package com.example.haemophilia_app

import android.graphics.*
import android.os.Handler
import android.os.Looper
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseDetector
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** One frame in flight. YUV packing and error-photo rendering never run on the UI thread. */
class LocalPoseBridge(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "hemo/local_pose")
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val busy = AtomicBoolean(false)
    private var detector: PoseDetector? = null
    private var closed = false
    @Volatile private var generation = 0
    private var lastImage: ByteArray? = null
    private var lastWidth = 0
    private var lastHeight = 0
    private var lastRotation = 0
    private var lastLandmarks: List<Map<String, Double>> = emptyList()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    if (detector == null) detector = PoseDetection.getClient(
                        PoseDetectorOptions.Builder().setDetectorMode(PoseDetectorOptions.STREAM_MODE).build())
                    result.success(null)
                }
                "reset" -> {
                    generation++
                    executor.execute {
                        lastImage = null
                        lastLandmarks = emptyList()
                        main.post { result.success(null) }
                    }
                }
                "detect" -> {
                    val arguments = call.arguments as? Map<*, *>
                    if (arguments == null || detector == null) {
                        result.error("NOT_READY", "Initialize joint tracking first.", null)
                    } else if (!busy.compareAndSet(false, true)) {
                        result.success(null) // Drop, never queue a stale image.
                    } else {
                        val frameGeneration = generation
                        executor.execute {
                            try {
                                val w = (arguments["width"] as Number).toInt()
                                val h = (arguments["height"] as Number).toInt()
                                val rotation = (arguments["rotation"] as Number).toInt()
                                require(w > 0 && h > 0 && w % 2 == 0 && h % 2 == 0)
                                val planes = arguments["planes"] as List<*>
                                val nv21 = packNv21(planes, w, h)
                                val input = InputImage.fromByteArray(nv21, w, h, rotation, InputImage.IMAGE_FORMAT_NV21)
                                val outW = if (rotation % 180 == 0) w else h
                                val outH = if (rotation % 180 == 0) h else w
                                detector!!.process(input).addOnSuccessListener(executor) { pose ->
                                    val points = (0..32).map { id ->
                                        val p = pose.getPoseLandmark(id)
                                        mapOf("x" to ((p?.position3D?.x ?: 0f).toDouble() / outW),
                                            "y" to ((p?.position3D?.y ?: 0f).toDouble() / outH),
                                            "z" to ((p?.position3D?.z ?: 0f).toDouble() / outW),
                                            "visibility" to (p?.inFrameLikelihood ?: 0f).toDouble())
                                    }
                                    if (generation == frameGeneration) {
                                        lastImage = nv21
                                        lastWidth = w; lastHeight = h; lastRotation = rotation
                                        lastLandmarks = points
                                    }
                                    busy.set(false)
                                    main.post { if (!closed) result.success(mapOf("landmarks" to points,
                                        "width" to outW, "height" to outH)) }
                                }.addOnFailureListener(executor) { e ->
                                    busy.set(false)
                                    main.post { if (!closed) result.error("POSE_FAILED", e.message, null) }
                                }
                            } catch (e: Exception) {
                                busy.set(false)
                                main.post { if (!closed) result.error("FRAME_FORMAT", e.message, null) }
                            }
                        }
                    }
                }
                "reviewImage" -> executor.execute {
                    try {
                        val bytes = reviewImage()
                        main.post { if (!closed) result.success(bytes) }
                    } catch (e: Exception) {
                        main.post { if (!closed) result.error("PHOTO_FAILED", e.message, null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun packNv21(planes: List<*>, w: Int, h: Int): ByteArray {
        require(planes.size == 3) { "Expected three YUV420 camera planes." }
        val data = planes.map { (it as Map<*, *>)["bytes"] as ByteArray }
        val row = planes.map { ((it as Map<*, *>)["rowStride"] as Number).toInt() }
        val pixel = planes.map { ((it as Map<*, *>)["pixelStride"] as Number).toInt() }
        val out = ByteArray(w * h * 3 / 2)
        for (y in 0 until h) for (x in 0 until w) out[y*w+x] = data[0][y*row[0]+x*pixel[0]]
        var offset = w*h
        for (y in 0 until h/2) for (x in 0 until w/2) {
            out[offset++] = data[2][y*row[2]+x*pixel[2]]
            out[offset++] = data[1][y*row[1]+x*pixel[1]]
        }
        return out
    }

    private fun reviewImage(): ByteArray? {
        val nv21 = lastImage ?: return null
        val jpeg = ByteArrayOutputStream()
        YuvImage(nv21, ImageFormat.NV21, lastWidth, lastHeight, null)
            .compressToJpeg(Rect(0, 0, lastWidth, lastHeight), 75, jpeg)
        val source = BitmapFactory.decodeByteArray(jpeg.toByteArray(), 0, jpeg.size())
        val matrix = Matrix().apply { postRotate(lastRotation.toFloat()) }
        val rotated = Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
        val annotated = rotated.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = Canvas(annotated)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(230, 65, 70); strokeWidth = 3f }
        val edges = arrayOf(11 to 12,11 to 13,13 to 15,12 to 14,14 to 16,
            11 to 23,12 to 24,23 to 24,23 to 25,25 to 27,24 to 26,26 to 28,27 to 29,28 to 30)
        for ((a,b) in edges) {
            val p = lastLandmarks[a]; val q = lastLandmarks[b]
            if (p.getValue("visibility") >= .5 && q.getValue("visibility") >= .5)
                canvas.drawLine((p.getValue("x")*annotated.width).toFloat(), (p.getValue("y")*annotated.height).toFloat(),
                    (q.getValue("x")*annotated.width).toFloat(), (q.getValue("y")*annotated.height).toFloat(), paint)
        }
        for (p in lastLandmarks) if (p.getValue("visibility") >= .5)
            canvas.drawCircle((p.getValue("x")*annotated.width).toFloat(), (p.getValue("y")*annotated.height).toFloat(), 4f, paint)
        val output = ByteArrayOutputStream()
        annotated.compress(Bitmap.CompressFormat.JPEG, 75, output)
        source.recycle(); if (rotated != source) rotated.recycle(); annotated.recycle()
        return output.toByteArray()
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        detector?.close(); detector = null
        executor.shutdown()
    }
}
