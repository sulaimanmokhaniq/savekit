plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Embedded yt-dlp (Python), FFmpeg and aria2c for fully on-device extraction.
val youtubedlAndroidVersion = "0.18.1"

android {
    namespace = "com.savekit.app"
    // Some plugins need a newer API level than the Flutter default.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.savekit.app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            // ABIs shipped by both Flutter and youtubedl-android.
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    packaging {
        jniLibs {
            // The bundled Python, FFmpeg and aria2c binaries are shipped as .so files and
            // must be extracted to nativeLibraryDir so they can be executed.
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // Signed with the debug keys until a release keystore is configured.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("io.github.junkfood02.youtubedl-android:library:$youtubedlAndroidVersion")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:$youtubedlAndroidVersion")
    implementation("io.github.junkfood02.youtubedl-android:aria2c:$youtubedlAndroidVersion")
}

flutter {
    source = "../.."
}
