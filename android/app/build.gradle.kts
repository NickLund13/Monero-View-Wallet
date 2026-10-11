plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.monero_view_wallet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // A placeholder, like the iPhone build's bundle id: it becomes the
        // app's real id once the app is registered on Google Play.
        applicationId = "com.example.monero_view_wallet"
        // Android 11: the first whose own BiometricPrompt can ask for the
        // fingerprint or face and fall back to the screen lock
        // (setAllowedAuthenticators), so the lock needs no support library.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            // Installed as files in the app's native library folder, the
            // only place Android runs a program from: the Tor Project's tor
            // ships as libtor.so (tool/fetch_tor.sh) and the app starts it
            // from there (MainActivity.kt). Stored compressed in the APK, so
            // the 16 KB alignment that matters is each library's own.
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // Signed with the debug key until the app has a Google Play
            // signing key, so `flutter run --release` works. Nothing built
            // this way is published.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Each version is pinned, and Gradle checks every file it downloads against
// gradle/verification-metadata.xml. docs/third-party-code.md lists what
// these bring into the app.
dependencies {
    // The camera for Scan wallet QR and Key images by QR (QrCamera.kt):
    // AndroidX's camera library, which talks only to the camera. Not Google's
    // ML Kit scanner, which needs Google Play services and sends usage data
    // to Google.
    implementation("androidx.camera:camera-camera2:1.6.2")
    implementation("androidx.camera:camera-lifecycle:1.6.2")
    // Turns the camera off while the app isn't on screen (QrCamera.kt).
    implementation("androidx.lifecycle:lifecycle-process:2.7.0")
    // Reads the QR codes in the camera's frames, on the phone.
    implementation("com.google.zxing:core:3.5.4")
}
