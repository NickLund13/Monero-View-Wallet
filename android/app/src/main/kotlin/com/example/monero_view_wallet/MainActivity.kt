package com.example.monero_view_wallet

import android.content.Context
import android.os.Bundle
import android.system.Os
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    companion object {
        // The app's one Flutter engine, kept for as long as the process runs.
        private var engine: FlutterEngine? = null
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
        super.onCreate(savedInstanceState)
    }

    // Android makes a new activity when the theme or wallpaper changes, and on
    // Android 11 after Back. Each new activity would otherwise start the app's
    // Dart code afresh in the same process, while the wallet the old one
    // opened stays open, and the wallet library won't open a wallet twice. So
    // every activity shows the same engine, and the Dart code runs once.
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        engine
            ?: FlutterEngine(context.applicationContext).also {
                KeystoreSecrets.register(
                    it.dartExecutor.binaryMessenger,
                    context.noBackupFilesDir.resolve("secrets"),
                )
                it.plugins.add(QrCamera())
                engine = it
            }

    override fun shouldDestroyEngineWithHost() = false
}
