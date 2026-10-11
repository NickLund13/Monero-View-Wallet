package com.example.monero_view_wallet

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.system.Os
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    companion object {
        // The app's one Flutter engine, kept for as long as the process runs,
        // and the app's own native code that answers it.
        private var engine: FlutterEngine? = null
        private lateinit var keyImagesFile: KeyImagesFile
        private lateinit var appLock: AppLock
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Android sets no HOME for an app. The wallet library keeps its ring
        // database under HOME, and the app keeps the wallet next to it
        // (keepOnDevice in lib/main.dart): the app's own folder that Android
        // never backs up. Set before Flutter starts the app's Dart code.
        Os.setenv("HOME", noBackupFilesDir.path, true)
        // The Tor Project's tor, which ships as libtor.so: Android runs a
        // program only from the app's native library folder, where it puts
        // the libraries when the app is installed (build.gradle.kts). The
        // app's Dart code starts it from there (lib/tor.dart).
        Os.setenv("MONERO_VIEW_TOR", "${applicationInfo.nativeLibraryDir}/libtor.so", true)
        val running = engine != null
        super.onCreate(savedInstanceState)
        keyImagesFile.attach(this)
        appLock.attach(this, covered = running)
        // A file this activity was started with, once: Android starts a new
        // activity with the same intent after it ended the app in the
        // background, and when the app is opened again from Recents.
        if (savedInstanceState == null &&
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0
        ) {
            keyImagesFile.receive(intent)
        }
    }

    // Android makes a new activity when the theme or wallpaper changes, and on
    // Android 11 after Back. Each new activity would otherwise start the app's
    // Dart code afresh in the same process, while the wallet the old one
    // opened stays open, and the wallet library won't open a wallet twice. So
    // every activity shows the same engine, and the Dart code runs once.
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        engine
            ?: FlutterEngine(context.applicationContext).also {
                val messenger = it.dartExecutor.binaryMessenger
                KeystoreSecrets.register(messenger, context.noBackupFilesDir.resolve("secrets"))
                keyImagesFile = KeyImagesFile.register(messenger, context)
                appLock = AppLock.register(messenger, context)
                it.plugins.add(QrCamera())
                engine = it
            }

    override fun shouldDestroyEngineWithHost() = false

    // A file opened with the app, or shared to it, while it runs. The
    // manifest's singleTask keeps it to this one activity, rather than a
    // second one in the other app's task.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        keyImagesFile.receive(intent)
    }

    // Where Android's file picker answers.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        keyImagesFile.picked(requestCode, resultCode, data)
    }

    override fun onResume() {
        appLock.resumed(this)
        super.onResume()
    }

    override fun onPause() {
        appLock.paused(this)
        super.onPause()
    }

    override fun onStop() {
        super.onStop()
        appLock.cover(this)
    }

    override fun onDestroy() {
        keyImagesFile.detach(this)
        appLock.detach(this)
        super.onDestroy()
    }
}
