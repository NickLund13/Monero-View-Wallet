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
