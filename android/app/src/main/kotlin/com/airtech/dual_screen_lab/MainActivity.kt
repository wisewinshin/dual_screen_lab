package com.airtech.dual_screen_lab

import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextClock
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.window.area.WindowAreaCapability
import androidx.window.area.WindowAreaController
import androidx.window.area.WindowAreaInfo
import androidx.window.area.WindowAreaPresentationSessionCallback
import androidx.window.area.WindowAreaSessionPresenter
import androidx.window.core.ExperimentalWindowApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import java.util.concurrent.Executor

@OptIn(ExperimentalWindowApi::class)
class MainActivity : FlutterActivity(), WindowAreaPresentationSessionCallback {
    companion object {
        private const val CHANNEL_NAME = "dual_screen_lab/window_area"
        private const val TAG = "FoldMoodClock"
    }

    private lateinit var windowAreaController: WindowAreaController
    private lateinit var displayExecutor: Executor
    private var windowAreaInfo: WindowAreaInfo? = null
    private var windowAreaSession: WindowAreaSessionPresenter? = null
    private var methodChannel: MethodChannel? = null
    private var capabilityStatus =
        WindowAreaCapability.Status.WINDOW_AREA_STATUS_UNSUPPORTED

    private val presentOperation =
        WindowAreaCapability.Operation.OPERATION_PRESENT_ON_AREA

    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.attributes = window.attributes.apply { screenBrightness = 1f }
        WindowCompat.getInsetsController(window, window.decorView)
            .hide(WindowInsetsCompat.Type.systemBars())

        displayExecutor = ContextCompat.getMainExecutor(this)
        windowAreaController = WindowAreaController.getOrCreate()
        observeDualScreenCapability()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> result.success(currentStatusName())
                    "start" -> startDualScreen(result)
                    "stop" -> {
                        windowAreaSession?.close()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun observeDualScreenCapability() {
        lifecycleScope.launch(Dispatchers.Main) {
            lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                windowAreaController.windowAreaInfos
                    .map { areas ->
                        areas.firstOrNull {
                            it.type == WindowAreaInfo.Type.TYPE_REAR_FACING
                        }
                    }
                    .onEach { info -> windowAreaInfo = info }
                    .map { info ->
                        info?.getCapability(presentOperation)?.status
                            ?: WindowAreaCapability.Status.WINDOW_AREA_STATUS_UNSUPPORTED
                    }
                    .distinctUntilChanged()
                    .collect { status ->
                        capabilityStatus = status
                        notifyFlutter()
                    }
            }
        }
    }

    private fun startDualScreen(result: MethodChannel.Result) {
        if (windowAreaSession != null) {
            result.success(null)
            return
        }

        val info = windowAreaInfo
        if (info == null ||
            capabilityStatus != WindowAreaCapability.Status.WINDOW_AREA_STATUS_AVAILABLE
        ) {
            result.error(
                "DUAL_SCREEN_UNAVAILABLE",
                if (capabilityStatus ==
                    WindowAreaCapability.Status.WINDOW_AREA_STATUS_UNSUPPORTED
                ) {
                    "이 기기는 Android 듀얼 스크린 모드를 지원하지 않습니다."
                } else {
                    "현재 자세에서는 듀얼 스크린을 시작할 수 없습니다. 폴드를 /\\ 모양으로 세워보세요."
                },
                null,
            )
            return
        }

        try {
            windowAreaController.presentContentOnWindowArea(
                token = info.token,
                activity = this,
                executor = displayExecutor,
                windowAreaPresentationSessionCallback = this,
            )
            result.success(null)
        } catch (error: Throwable) {
            Log.e(TAG, "Unable to start dual-screen presentation", error)
            result.error(
                "DUAL_SCREEN_FAILED",
                error.localizedMessage ?: "듀얼 스크린을 시작하지 못했습니다.",
                null,
            )
        }
    }

    override fun onSessionStarted(session: WindowAreaSessionPresenter) {
        windowAreaSession = session
        session.setContentView(createClockView(session.context))
        notifyFlutter()
    }

    override fun onSessionEnded(t: Throwable?) {
        if (t != null) Log.e(TAG, "Dual-screen session ended with an error", t)
        windowAreaSession = null
        notifyFlutter()
    }

    override fun onContainerVisibilityChanged(isVisible: Boolean) {
        Log.d(TAG, "Cover display visible: $isVisible")
    }

    private fun createClockView(context: android.content.Context): FrameLayout {
        val root = FrameLayout(context).apply {
            setBackgroundColor(Color.BLACK)
            keepScreenOn = true
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        val content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(context, 24), dp(context, 24), dp(context, 24), dp(context, 24))
        }

        content.addView(TextClock(context).apply {
            format24Hour = "HH:mm:ss"
            format12Hour = "hh:mm:ss"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 88f)
            gravity = Gravity.CENTER
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            letterSpacing = 0.04f
        })

        content.addView(TextClock(context).apply {
            format24Hour = "M월 d일 EEEE"
            format12Hour = "M월 d일 EEEE"
            setTextColor(Color.argb(180, 255, 255, 255))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            gravity = Gravity.CENTER
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(context, 8) })

        root.addView(content)
        root.addOnLayoutChangeListener { _, left, top, right, bottom, _, _, _, _ ->
            val width = right - left
            val height = bottom - top
            if (width <= 0 || height <= 0) return@addOnLayoutChangeListener

            val portraitSurface = height > width
            content.rotation = if (portraitSurface) -90f else 0f
            val desiredWidth = if (portraitSurface) height else width
            val desiredHeight = if (portraitSurface) width else height
            val params = content.layoutParams as? FrameLayout.LayoutParams
            if (params == null ||
                params.width != desiredWidth ||
                params.height != desiredHeight
            ) {
                content.layoutParams = FrameLayout.LayoutParams(
                    desiredWidth,
                    desiredHeight,
                    Gravity.CENTER,
                )
            }
        }

        return root
    }

    private fun currentStatusName(): String = when {
        windowAreaSession != null -> "active"
        capabilityStatus == WindowAreaCapability.Status.WINDOW_AREA_STATUS_AVAILABLE ->
            "available"
        capabilityStatus == WindowAreaCapability.Status.WINDOW_AREA_STATUS_UNAVAILABLE ->
            "unavailable"
        capabilityStatus == WindowAreaCapability.Status.WINDOW_AREA_STATUS_ACTIVE ->
            "active"
        else -> "unsupported"
    }

    private fun notifyFlutter() {
        methodChannel?.invokeMethod("statusChanged", currentStatusName())
    }

    private fun dp(context: android.content.Context, value: Int): Int =
        (value * context.resources.displayMetrics.density).toInt()
}
