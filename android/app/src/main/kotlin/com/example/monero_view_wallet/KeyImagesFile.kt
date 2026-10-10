package com.example.monero_view_wallet

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Brings the key images file the Monero GUI exported into the app: chosen
 * with Android's file picker, or opened with this app or shared to it from
 * another app, such as Files, a cloud drive or email. lib/pick_file.dart is
 * the other end of the channel, as for ios/Runner/KeyImagesFile.swift.
 *
 * Android hands the app only a link to the file. The app reads it once, into
 * a folder of its own under no_backup/KeyImages, which Android never backs up
 * and no other app can read, and deletes that copy once it is imported or set
 * aside. Copies an earlier launch left behind are deleted at launch. Nothing
 * here reads what the file holds or logs its name.
 */
class KeyImagesFile private constructor(
    private val context: Context,
    private val channel: MethodChannel,
    private val incoming: File,
) : MethodChannel.MethodCallHandler {

    companion object {
        /**
         * maxKeyImagesFile in lib/wallet.dart: far bigger than any wallet's
         * key images file.
         */
        private const val MAX_SIZE = 64L * 1024 * 1024

        /** The file picker's answer, among the activity's results. */
        private const val PICK = 0x4b49

        fun register(messenger: BinaryMessenger, context: Context): KeyImagesFile {
            val incoming = context.noBackupFilesDir.resolve("KeyImages")
            // A new launch has nothing waiting to be imported.
            incoming.deleteRecursively()
            val channel = MethodChannel(messenger, "monero_view_wallet/key_images_file")
            val instance = KeyImagesFile(context.applicationContext, channel, incoming)
            channel.setMethodCallHandler(instance)
            return instance
        }
    }

    // Copies off the main thread, one at a time, so the newest file opened
    // with the app is the last one handed to the Dart side.
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** The activity showing the app, which shows the file picker. */
    private var activity: Activity? = null

    /** Answers the Dart side's "pick" once the file picker closes. */
    private var picked: MethodChannel.Result? = null

    /**
     * Copies of files opened with the app that the Dart side hasn't taken
     * yet: the one that started the app arrives before the Dart side is
     * listening.
     */
    private val received = mutableListOf<String>()
    private var dartListening = false

    fun attach(activity: Activity) {
        this.activity = activity
    }

    fun detach(activity: Activity) {
        if (this.activity === activity) this.activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> pick(result)
            "take" -> {
                dartListening = true
                result.success(received.toList())
                received.clear()
            }
            else -> result.notImplemented()
        }
    }

    // The file picker

    private fun pick(result: MethodChannel.Result) {
        val activity = activity
        if (picked != null || activity == null) {
            result.error("unavailable", "Can't show the file picker now", null)
            return
        }
        // The GUI's file has no extension of its own, so any file can be
        // chosen.
        val intent =
            Intent(Intent.ACTION_OPEN_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType("*/*")
        try {
            activity.startActivityForResult(intent, PICK)
            picked = result
        } catch (e: ActivityNotFoundException) {
            result.error("unavailable", "No file picker", null)
        }
    }

    /**
     * MainActivity hands on each of its activity results here: the picker's
     * answers "pick" with the path of the app's copy, or null if nothing was
     * chosen.
     */
    fun picked(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK) return
        val result = picked ?: return
        picked = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        worker.execute {
            val path = keep(uri)
            main.post { result.success(path) }
        }
    }

    // Files opened with the app

    /**
     * Keeps a copy of the file in [intent], if it opens one with the app
     * ("Open with") or shares one to it, for the Dart side.
     */
    fun receive(intent: Intent) {
        val uri =
            try {
                when (intent.action) {
                    Intent.ACTION_VIEW -> intent.data
                    Intent.ACTION_SEND -> stream(intent)
                    else -> null
                }
            } catch (e: Exception) {
                // An intent another app made up that can't be read.
                null
            } ?: return
        worker.execute {
            val path = keep(uri) ?: return@execute
            main.post {
                received.add(path)
                if (dartListening) channel.invokeMethod("received", null)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun stream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 34) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    // The app's copies

    /**
     * Copies the file at [uri] into a new folder under [incoming] and returns
     * the copy's path there, or null if it can't be read. Only a link another
     * app shares (content://) is read, never a file path, which could point
     * into the app's own folders.
     */
    private fun keep(uri: Uri): String? {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return null
        val folder = incoming.resolve(UUID.randomUUID().toString())
        return try {
            check(folder.mkdirs())
            val kept = folder.resolve(name(uri))
            val input = context.contentResolver.openInputStream(uri) ?: error("unreadable")
            input.use { from -> kept.outputStream().use { to -> copy(from, to) } }
            kept.path
        } catch (e: Exception) {
            folder.deleteRecursively()
            null
        }
    }

    /**
     * The file's name, as the app that has it shows it, for the Import key
     * images screen. Only the name: nothing in it can lead out of the copy's
     * own folder.
     */
    private fun name(uri: Uri): String {
        val shown =
            try {
                context.contentResolver
                    .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { if (it.moveToFirst()) it.getString(0) else null }
            } catch (e: Exception) {
                null
            }
        val name = shown?.substringAfterLast('/')?.filter { it >= ' ' }?.take(100)
        return if (name.isNullOrBlank() || name == "." || name == "..") "key images" else name
    }

    /**
     * Copies at most one byte more than a key images file can hold. A bigger
     * file is cut short there, so it never fills the phone, and the import
     * still turns it away as too big (looksLikeKeyImagesFile in
     * lib/wallet.dart).
     */
    private fun copy(from: InputStream, to: OutputStream) {
        val buffer = ByteArray(64 * 1024)
        var left = MAX_SIZE + 1
        while (left > 0) {
            val read = from.read(buffer, 0, minOf(buffer.size.toLong(), left).toInt())
            if (read < 0) break
            to.write(buffer, 0, read)
            left -= read
        }
    }
}
