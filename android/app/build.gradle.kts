plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.sidepatio.android"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.sidepatio.android"
        // 30 (Android 11) is LiteRT-LM's floor, so on-device inference can be
        // added later without dropping devices that installed an earlier build.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            // x86_64 for the emulator on a Windows/Linux host.
            ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        }
        release {
            ndk { abiFilters += listOf("arm64-v8a") }
            // TODO(release): a real signing config before any APK is published.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

configurations.all {
    // sherpa_onnx ships libonnxruntime.so (ORT 1.28.2) and onnxruntime_v2's
    // onnxruntime-android AAR ships another (1.23.2) at the same path, which
    // fails the merge. onnxruntime_v2 has no Java/Kotlin code: it opens the
    // library over FFI and asks for C API 15, which the newer ORT serves, so
    // the AAR is dropped and sherpa's copy serves both.
    exclude(group = "com.microsoft.onnxruntime", module = "onnxruntime-android")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
