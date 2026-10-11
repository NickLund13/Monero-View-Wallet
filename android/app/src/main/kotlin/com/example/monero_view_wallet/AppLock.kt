package com.example.monero_view_wallet

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The app's lock on Android (lib/lock.dart): the phone's fingerprint or face,
 * or its screen lock, through Android's own BiometricPrompt, and a cover over
 * the app while it is out of sight. The app only learns whether a check
 * passed; the fingerprint, face and screen lock stay with Android. It answers
 * on the same channel as the iPhone's (ios/Runner/AppDelegate.swift).
 *
 * Only a fingerprint or face that Android counts as strong (Class 3) is
 * offered. A phone with only a weaker one unlocks the app with its screen
 * lock.
 */
class AppLock private constructor(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        private const val STRONG = BiometricManager.Authenticators.BIOMETRIC_STRONG
        private const val SCREEN_LOCK = BiometricManager.Authenticators.DEVICE_CREDENTIAL

        fun register(messenger: BinaryMessenger, context: Context): AppLock {
            val lock = AppLock(context.applicationContext)
            MethodChannel(messenger, "monero_view_wallet/lock").setMethodCallHandler(lock)
            return lock
        }
    }

    private val main = Handler(Looper.getMainLooper())

    /** The activity showing the app, and whether it is in front. */
    private var activity: Activity? = null
    private var resumed = false

    /**
     * Hides the app once it is out of sight, and when it is shown again,
     * until the Dart side has drawn it as it is now: the lock screen, if the
     * app locked. Until then Android would show the app as it was when it
     * went away, balance and all.
     */
    private var cover: View? = null

    /**
     * MainActivity calls this as each activity starts. Recents never shows a
     * picture of the app, locked or not: Android 13 and later leave the
     * picture out, and before that only a secure window does, which also
     * keeps the app out of screenshots. With [covered], the app is covered
     * from the start: the Dart side was already running for an activity
     * before this one, and may lock before it shows anything.
     */
    fun attach(activity: Activity, covered: Boolean) {
        this.activity = activity
        resumed = false
        cover = null
        if (Build.VERSION.SDK_INT >= 33) {
            activity.setRecentsScreenshotEnabled(false)
        } else {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        if (covered) cover(activity)
    }

    fun detach(activity: Activity) {
        if (this.activity !== activity) return
        this.activity = null
        resumed = false
        cover = null
    }

    fun resumed(activity: Activity) {
        if (this.activity !== activity) return
        resumed = true
        // If the Dart side never asks for the cover to come off, it comes off
        // by itself.
        val shown = cover ?: return
        main.postDelayed({ if (resumed && cover === shown) uncover() }, 2000)
    }

    fun paused(activity: Activity) {
        if (this.activity === activity) resumed = false
    }

    /** Covers the app with its background color, and nothing on it. */
    fun cover(activity: Activity) {
        if (this.activity !== activity || cover != null) return
        val view = View(activity)
        view.setBackgroundColor(activity.getColor(R.color.launch_background))
        // Taps meant for what it hides go nowhere.
        view.isClickable = true
        activity.addContentView(
            view,
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT),
        )
        cover = view
    }

    private fun uncover() {
        val view = cover ?: return
        (view.parent as? ViewGroup)?.removeView(view)
        cover = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "kind" -> result.success(kind())
            "ask" ->
                ask(
                    reason = call.argument<String>("reason") ?: "Unlock your wallet",
                    screenLock = call.argument<Boolean>("passcode") ?: true,
                    result = result,
                )
            "uncover" -> {
                // Only while the app is in front: one that went away again
                // since keeps its cover.
                if (resumed) uncover()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Whether the phone has a screen lock: a PIN, pattern or password. If
     * Android can't say, as if it had, so the app stays locked.
     */
    private fun hasScreenLock(): Boolean =
        context.getSystemService(KeyguardManager::class.java)?.isDeviceSecure ?: true

    /** Whether a strong fingerprint or face is set up and can be used now. */
    private fun hasStrongBiometric(): Boolean =
        context.getSystemService(BiometricManager::class.java)?.canAuthenticate(STRONG) ==
            BiometricManager.BIOMETRIC_SUCCESS

    /**
     * "fingerprint", "face", or "biometric" for a phone that has both, when
     * one can be used; "screenLock" when only the screen lock can; and
     * "noScreenLock" when the phone has no screen lock, so the app can't lock.
     */
    private fun kind(): String {
        if (!hasScreenLock()) return "noScreenLock"
        if (!hasStrongBiometric()) return "screenLock"
        val features = context.packageManager
        val fingerprint = features.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)
        val face = features.hasSystemFeature(PackageManager.FEATURE_FACE)
        val iris = features.hasSystemFeature(PackageManager.FEATURE_IRIS)
        return when {
            fingerprint && !face && !iris -> "fingerprint"
            face && !fingerprint && !iris -> "face"
            else -> "biometric"
        }
    }

    /**
     * The fingerprint or face, or with [screenLock] the screen lock, which
     * Android may start with the fingerprint or face. Answers with a
     * CheckResult name.
     */
    private fun ask(reason: String, screenLock: Boolean, result: MethodChannel.Result) {
        val activity = activity
        if (activity == null) {
            result.error("unavailable", "Can't ask now", null)
            return
        }
        if (!hasScreenLock()) {
            result.success("noPasscode")
            return
        }
        if (!screenLock && !hasStrongBiometric()) {
            result.success("unavailable")
            return
        }
        var answered = false
        fun answer(value: String) {
            if (answered) return
            answered = true
            result.success(value)
        }
        val executor = activity.mainExecutor
        val builder =
            BiometricPrompt.Builder(activity)
                .setTitle(reason)
                .setAllowedAuthenticators(if (screenLock) STRONG or SCREEN_LOCK else STRONG)
                .setConfirmationRequired(false)
        if (!screenLock) {
            // No "Use screen lock" on the fingerprint prompt: the lock screen
            // has its own.
            builder.setNegativeButton("Cancel", executor) { _, _ -> answer("cancelled") }
        }
        val callback =
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) =
                    answer("ok")

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) =
                    answer(answerFor(errorCode))

                // A try that didn't match: the prompt stays up for another.
            }
        try {
            builder.build().authenticate(CancellationSignal(), executor, callback)
        } catch (e: Exception) {
            answer("failed")
        }
    }

    private fun answerFor(errorCode: Int): String =
        when (errorCode) {
            BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED,
            BiometricPrompt.BIOMETRIC_ERROR_CANCELED,
            BiometricPrompt.BIOMETRIC_ERROR_TIMEOUT -> "cancelled"
            BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT,
            BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT_PERMANENT -> "lockedOut"
            BiometricPrompt.BIOMETRIC_ERROR_NO_BIOMETRICS,
            BiometricPrompt.BIOMETRIC_ERROR_HW_NOT_PRESENT,
            BiometricPrompt.BIOMETRIC_ERROR_HW_UNAVAILABLE -> "unavailable"
            // Only a phone without a screen lock lets the app in without one.
            BiometricPrompt.BIOMETRIC_ERROR_NO_DEVICE_CREDENTIAL ->
                if (hasScreenLock()) "failed" else "noPasscode"
            else -> "failed"
        }
}
