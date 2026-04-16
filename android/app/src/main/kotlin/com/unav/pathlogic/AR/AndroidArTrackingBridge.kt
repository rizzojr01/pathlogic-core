package com.unav.pathlogic.AR

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Camera
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.unav.pathlogic.MainActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.atan2

class AndroidArTrackingBridge(
    private val activity: MainActivity
) : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val eventSinkRef = AtomicReference<EventChannel.EventSink?>()
    private val overlaySnapshotRef = AtomicReference(OverlaySnapshot())
    private val sessionLock = Any()
    private val previewViews = CopyOnWriteArraySet<AndroidArPreviewPlatformView>()

    private var session: Session? = null
    private var isSessionRunning = false
    private var latestViewProjectionMatrix: FloatArray? = null

    fun register(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        registerChannels(messenger)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            ArChannelContract.AR_PREVIEW_VIEW_TYPE,
            AndroidArPreviewFactory(this)
        )
    }

    private fun registerChannels(messenger: BinaryMessenger) {
        MethodChannel(messenger, ArChannelContract.AR_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                ArChannelContract.GET_CAPABILITIES_METHOD -> result.success(mapOf(
                    ArChannelContract.BACKEND_KEY to "androidArCore",
                    ArChannelContract.IS_SUPPORTED_KEY to true
                ))
                ArChannelContract.START_SESSION_METHOD -> startSession(result)
                ArChannelContract.STOP_SESSION_METHOD -> {
                    stopSession()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, ArChannelContract.AR_POSE_EVENT_CHANNEL).setStreamHandler(this)
    }

    private fun startSession(result: MethodChannel.Result) {
        if (!hasCameraPermission()) {
            ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.CAMERA), 9001)
            result.error("camera_permission_required", "Camera permission is required", null)
            return
        }

        try {
            synchronized(sessionLock) {
                if (session == null) {
                    session = Session(activity)
                    val config = Config(session)
                    config.focusMode = Config.FocusMode.AUTO
                    session?.configure(config)
                }
                session?.resume()
                isSessionRunning = true
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("arcore_error", e.message, null)
        }
    }

    private fun stopSession() {
        synchronized(sessionLock) {
            session?.pause()
            isSessionRunning = false
        }
    }

    private fun hasCameraPermission() = ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSinkRef.set(events)
    }

    override fun onCancel(arguments: Any?) {
        eventSinkRef.set(null)
    }

    fun handleFrame(frame: Frame) {
        val eventSink = eventSinkRef.get() ?: return
        val camera = frame.camera
        if (camera.trackingState == TrackingState.TRACKING) {
            val pose = camera.pose
            val translation = pose.translation
            val zAxis = pose.zAxis
            val heading = Math.toDegrees(atan2(-zAxis[2].toDouble(), -zAxis[0].toDouble()))

            val payload = mapOf(
                ArChannelContract.X_KEY to translation[0].toDouble(),
                ArChannelContract.Y_KEY to (-translation[2]).toDouble(),
                ArChannelContract.Z_KEY to translation[1].toDouble(),
                ArChannelContract.HEADING_KEY to heading,
                ArChannelContract.TIMESTAMP_KEY to System.currentTimeMillis()
            )
            mainHandler.post { eventSink.success(payload) }
        }
    }
}

data class OverlaySnapshot(
    val activePathPoints: List<Vector3> = emptyList(),
    val futurePathPoints: List<Vector3> = emptyList()
)

data class Vector3(val x: Float, val y: Float, val z: Float)
