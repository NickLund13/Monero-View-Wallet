package com.example.monero_view_wallet

import android.os.Bundle
import android.system.Os
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android sets no HOME for an app. The wallet library keeps its ring
        // database under HOME, and the app keeps the wallet next to it
        // (keepOnDevice in lib/main.dart): the app's own folder that Android
        // never backs up. Set before Flutter starts the app's Dart code.
        Os.setenv("HOME", noBackupFilesDir.path, true)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        KeystoreSecrets.register(
            flutterEngine.dartExecutor.binaryMessenger,
            noBackupFilesDir.resolve("secrets"),
        )
    }
}
