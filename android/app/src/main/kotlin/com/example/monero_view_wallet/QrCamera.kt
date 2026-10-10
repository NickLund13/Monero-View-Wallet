package com.example.monero_view_wallet

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Matrix
import android.graphics.RectF
import android.graphics.SurfaceTexture
import android.hardware.display.DisplayManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Size
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.WindowManager
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ProcessLifecycleOwner
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.HybridBinarizer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The camera for Scan wallet QR and Key images by QR on Android
 * (lib/scan_screen.dart is the other end of the channel), as
 * ios/Runner/QrCamera.swift is on iPhone. AndroidX's CameraX runs the camera
 * and ZXing reads the codes, both inside the app: no Google Play services, no
 * scanning service, nothing sent anywhere.
 *
 * Each camera view on the Dart side is a platform view with a camera of its
 * own, which runs from the moment the view is made until it reads one code or
 * the Dart side takes the view away, and only while the app is on screen. A
 * view for an animated code keeps reading, and hands over each part as it
 * appears. The picture is only ever shown on screen and read in memory, never
 * saved, and no code's text is logged.
 */
class QrCamera :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        private const val ASK = 0x5143 // "QC"
    }

    private var channel: MethodChannel? = null
    private var activity: ActivityPluginBinding? = null

    /** The answers waiting for the person to allow the camera or not. */
    private val asking = mutableListOf<MethodChannel.Result>()

    /** The views still on the Dart side's screen, by id, so "stop" can reach them. */
    private val views = mutableMapOf<Int, CameraView>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val channel = MethodChannel(binding.binaryMessenger, "monero_view_wallet/camera")
        channel.setMethodCallHandler(this)
        this.channel = channel
        binding.platformViewRegistry.registerViewFactory(
            "monero_view_wallet/camera",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                    // The Dart side says whether the view reads an animated code.
                    val animated = (args as? Map<*, *>)?.get("animated") == true
                    return CameraView(context, viewId, channel, animated)
                }
            },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        views.values.toList().forEach { it.stop() }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity?.removeRequestPermissionsResultListener(this)
        activity = null
        // The question went with the activity.
        answer(false)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val activity = activity?.activity
        when (call.method) {
            // Whether the camera may be used, without asking. Android doesn't
            // say whether the person was asked before.
            "status" -> result.success(if (allowed(activity)) "authorized" else "notAuthorized")
            // Asks the first time, and again until the person has said no
            // twice: Android then answers no by itself, and only the app's page
            // in Settings can allow it.
            "allowed" ->
                when {
                    activity == null -> result.success(false)
                    allowed(activity) -> result.success(true)
                    else -> {
                        asking += result
                        if (asking.size == 1) {
                            activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), ASK)
                        }
                    }
                }
            "openSettings" -> {
                activity?.startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", activity.packageName, null),
                    ),
                )
                result.success(null)
            }
            "stop" -> {
                (call.arguments as? Int)?.let { views[it]?.stop() }
                result.success(null)
            }
            // While the app shows an animated code to another device's camera,
            // or reads one: the screen doesn't dim or lock. Android applies it
            // only while the app is in front.
            "keepScreenOn" -> {
                val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                if (call.arguments == true) {
                    activity?.window?.addFlags(flag)
                } else {
                    activity?.window?.clearFlags(flag)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != ASK) return false
        answer(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        return true
    }

    private fun answer(allowed: Boolean) {
        val waiting = asking.toList()
        asking.clear()
        waiting.forEach { it.success(allowed) }
    }

    private fun allowed(context: Context?): Boolean =
        context?.checkSelfPermission(Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * One camera view: the live picture in a TextureView, which Flutter draws
     * in its place on the Dart side, and the frames ZXing reads.
     *
     * It is its own LifecycleOwner for CameraX: started while the app is on
     * screen (ProcessLifecycleOwner), stopped while it isn't, and destroyed,
     * which turns the camera off for good, once it has read its code or the
     * Dart side takes it away.
     */
    private inner class CameraView(
        private val context: Context,
        private val id: Int,
        private val channel: MethodChannel,
        private val animated: Boolean,
    ) : PlatformView, LifecycleOwner {
        private val texture = TextureView(context)
        private val registry = LifecycleRegistry(this)
        override val lifecycle: Lifecycle
            get() = registry

        private val main = Handler(Looper.getMainLooper())
        private val onMain = context.mainExecutor

        /** ZXing reads one frame at a time here, off the main thread. */
        private val reading: ExecutorService = Executors.newSingleThreadExecutor()

        /** Reads the frames. Only used on [reading]. */
        private val reader =
            MultiFormatReader().apply {
                setHints(
                    mapOf(
                        DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
                        DecodeHintType.CHARACTER_SET to "UTF-8",
                        // A code shown light on dark, as in a dark theme.
                        DecodeHintType.ALSO_INVERTED to true,
                    ),
                )
            }

        /**
         * True once a code was read (not for an animated code) or the view
         * was stopped: nothing more is handed over. Also read on [reading].
         */
        @Volatile private var done = false

        /** The part last handed over, while reading an animated code. */
        private var last: String? = null

        private var preview: Preview? = null
        private var analysis: ImageAnalysis? = null

        /** The camera's request for a Surface to draw its picture in, until it has one. */
        private var request: SurfaceRequest? = null
        private var resolution: Size? = null

        /** The SurfaceTexture the camera draws in, until it lets go of it. */
        private var provided: SurfaceTexture? = null

        private val surfaces =
            Preview.SurfaceProvider { request ->
                this.request?.willNotProvideSurface()
                this.request = request
                resolution = request.resolution
                request.setTransformationInfoListener(onMain) { info ->
                    cameraTransform = info.hasCameraTransform()
                    previewRotation = info.rotationDegrees
                    transform()
                }
                provide()
            }

        /** How the picture is turned: see [transform]. */
        private var cameraTransform = true
        private var previewRotation = 0
        private var sensorRotation: (Int) -> Int = { 0 }

        private val app = ProcessLifecycleOwner.get().lifecycle
        private val follow = LifecycleEventObserver { _, _ -> follow() }

        private val displays = context.getSystemService(DisplayManager::class.java)
        private val turned =
            object : DisplayManager.DisplayListener {
                override fun onDisplayAdded(displayId: Int) {}

                override fun onDisplayRemoved(displayId: Int) {}

                override fun onDisplayChanged(displayId: Int) {
                    texture.display?.let { preview?.targetRotation = it.rotation }
                    transform()
                }
            }

        init {
            views[id] = this
            registry.currentState = Lifecycle.State.CREATED
            texture.surfaceTextureListener =
                object : TextureView.SurfaceTextureListener {
                    override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) {
                        val preview = preview
                        if (provided != null && request == null && preview != null && !done) {
                            // A new SurfaceTexture after the TextureView was
                            // taken off the screen and put back: the camera
                            // is asked for a new request to draw in it.
                            preview.setSurfaceProvider(onMain, surfaces)
                        } else {
                            provide()
                        }
                    }

                    override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) =
                        transform()

                    // Kept until the camera has let go of it (see provide).
                    override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean =
                        provided !== st

                    override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
                }
            texture.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> transform() }
            displays?.registerDisplayListener(turned, main)
            val providing = ProcessCameraProvider.getInstance(context)
            providing.addListener(
                {
                    if (done) return@addListener
                    val provider =
                        try {
                            providing.get()
                        } catch (e: Exception) {
                            return@addListener
                        }
                    start(provider)
                },
                onMain,
            )
        }

        override fun getView(): View = texture

        override fun dispose() = stop()

        /**
         * The back camera, or on a device with none the front one: the
         * picture into the TextureView, the frames to ZXing. Nothing when
         * there is no camera to use: not allowed, or none at all.
         */
        private fun start(provider: ProcessCameraProvider) {
            if (!allowed(context)) return
            val selector =
                listOf(CameraSelector.DEFAULT_BACK_CAMERA, CameraSelector.DEFAULT_FRONT_CAMERA)
                    .firstOrNull {
                        try {
                            provider.hasCamera(it)
                        } catch (e: Exception) {
                            false
                        }
                    } ?: return
            val preview = Preview.Builder().build()
            this.preview = preview
            preview.setSurfaceProvider(onMain, surfaces)
            // Big enough for a dense animated code that doesn't fill the
            // frame, small enough for ZXing to keep up.
            val analysis =
                ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setResolutionSelector(
                        ResolutionSelector.Builder()
                            .setResolutionStrategy(
                                ResolutionStrategy(
                                    Size(1280, 720),
                                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                                ),
                            )
                            .build(),
                    )
                    .build()
            analysis.setAnalyzer(reading, ::read)
            this.analysis = analysis
            try {
                val camera = provider.bindToLifecycle(this, selector, preview, analysis)
                sensorRotation = camera.cameraInfo::getSensorRotationDegrees
            } catch (e: Exception) {
                // The camera can't be used now, by the kind of error only;
                // the view stays dark, as on iPhone.
                return
            }
            app.addObserver(follow)
        }

        /** Started while the app is on screen. */
        private fun follow() {
            if (done) return
            registry.currentState = maxOf(app.currentState, Lifecycle.State.CREATED)
        }

        /** Hands the TextureView's Surface to the camera once both are there. */
        private fun provide() {
            val request = request ?: return
            val st = texture.surfaceTexture ?: return
            if (done) {
                request.willNotProvideSurface()
                this.request = null
                return
            }
            this.request = null
            st.setDefaultBufferSize(request.resolution.width, request.resolution.height)
            val surface = Surface(st)
            provided = st
            request.provideSurface(surface, onMain) {
                surface.release()
                if (provided === st) provided = null
                // The TextureView went first, and left the SurfaceTexture to
                // be let go of here.
                if (texture.surfaceTexture !== st) st.release()
            }
            transform()
        }

        /**
         * Fills the view with the picture, cut to fit, turned the way the
         * screen is (as CameraX's own PreviewView does for a TextureView).
         * When the camera writes into the Surface itself, the TextureView
         * already turns the picture upright for the device held upright, and
         * only the screen's turn is left; otherwise CameraX says by how much.
         */
        private fun transform() {
            val resolution = resolution ?: return
            val w = texture.width.toFloat()
            val h = texture.height.toFloat()
            if (w == 0f || h == 0f) return
            val display = texture.display?.rotation ?: Surface.ROTATION_0
            val screen =
                when (display) {
                    Surface.ROTATION_90 -> 90
                    Surface.ROTATION_180 -> 180
                    Surface.ROTATION_270 -> 270
                    else -> 0
                }
            val turn: Int
            val upright: Int
            if (cameraTransform) {
                turn = -screen
                upright = sensorRotation(display)
            } else {
                turn = previewRotation
                upright = previewRotation
            }
            // The picture's shape once upright on the screen.
            val pw: Float
            val ph: Float
            if (upright % 180 == 0) {
                pw = resolution.width.toFloat()
                ph = resolution.height.toFloat()
            } else {
                pw = resolution.height.toFloat()
                ph = resolution.width.toFloat()
            }
            val scale = maxOf(w / pw, h / ph)
            val shown =
                RectF(0f, 0f, pw * scale, ph * scale).apply {
                    offset((w - width()) / 2, (h - height()) / 2)
                }
            val normal = RectF(-1f, -1f, 1f, 1f)
            val matrix = Matrix()
            matrix.setRectToRect(RectF(0f, 0f, w, h), normal, Matrix.ScaleToFit.FILL)
            matrix.postRotate(turn.toFloat())
            matrix.postConcat(
                Matrix().apply { setRectToRect(normal, shown, Matrix.ScaleToFit.FILL) },
            )
            texture.setTransform(matrix)
        }

        /** Looks for a QR code in the frame's brightness, on [reading]. */
        private fun read(image: ImageProxy) {
            image.use {
                if (done) return
                val plane = it.planes[0]
                val buffer = plane.buffer
                val bytes = ByteArray(buffer.remaining())
                buffer.get(bytes)
                val source =
                    PlanarYUVLuminanceSource(
                        bytes,
                        plane.rowStride,
                        it.height,
                        0,
                        0,
                        it.width,
                        it.height,
                        false,
                    )
                val text =
                    try {
                        reader.decodeWithState(BinaryBitmap(HybridBinarizer(source))).text
                    } catch (e: ReaderException) {
                        null
                    } catch (e: RuntimeException) {
                        // ZXing can fail this way on a frame it can't make
                        // sense of. The next frame is tried as usual.
                        null
                    } finally {
                        reader.reset()
                    }
                if (text != null) main.post { found(text) }
            }
        }

        /** The first code read goes to the Dart side, or for an animated code each new part. */
        private fun found(text: String) {
            if (done) return
            if (animated) {
                if (text == last) return
                last = text
            } else {
                // One code per view: the camera stops at once.
                stop()
            }
            channel.invokeMethod("code", mapOf("view" to id, "text" to text))
        }

        /** Turns the camera off and lets go of it. Nothing more is read. */
        fun stop() {
            if (done) return
            done = true
            last = null
            views.remove(id)
            app.removeObserver(follow)
            displays?.unregisterDisplayListener(turned)
            request?.willNotProvideSurface()
            request = null
            // No frame is handed to the reader any more, which then ends.
            analysis?.clearAnalyzer()
            // CameraX lets go of this view's camera and use cases.
            registry.currentState = Lifecycle.State.DESTROYED
            reading.shutdown()
        }
    }
}
