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
    }

    packaging {
        jniLibs {
            // The bundled Python, FFmpeg and aria2c binaries are shipped as .so files and
            // must be extracted to nativeLibraryDir so they can be executed.
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        // Release builds are signed with a keystore from the environment when one is given
        // (SAVEKIT_KEYSTORE and friends, e.g. from CI secrets). Otherwise they use the
        // sideload key committed in this repository. Like Android's debug key, that key is
        // public: it only keeps successive builds installable over each other. Use a private
        // keystore before distributing the app through a store.
        create("release") {
            val custom = System.getenv("SAVEKIT_KEYSTORE")
            if (!custom.isNullOrBlank() && file(custom).exists()) {
                storeFile = file(custom)
                storePassword = System.getenv("SAVEKIT_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("SAVEKIT_KEY_ALIAS")
                keyPassword = System.getenv("SAVEKIT_KEY_PASSWORD")
            } else {
                storeFile = file("sideload.jks")
                storePassword = "savekit-sideload"
                keyAlias = "savekit"
                keyPassword = "savekit-sideload"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // The app's size is its bundled native binaries (Python, FFmpeg), which
            // shrinking cannot reduce, and yt-dlp's Java bridge is loaded reflectively.
            // Leaving the code unshrunk keeps the release build identical to the tested one.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            // Same key as release, so a debug build can be installed over a release one.
            signingConfig = signingConfigs.getByName("release")
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
