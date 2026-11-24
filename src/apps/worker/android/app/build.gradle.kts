plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.edgemint.edgemint_worker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion


    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.edgemint.edgemint_worker"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Single OTA APK (FibonAi.apk): phones need arm64 only. LiteRT-LM /
        // Gemma 4 already require arm64-v8a. Fat multi-ABI APKs were ~318 MB.
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }

    androidResources {
        noCompress += listOf("litertlm", "safetensors", "task", "bin", "tflite")
    }

    // abiFilters does not always strip third-party AAR / Native Assets .so files.
    packaging {
        jniLibs {
            excludes += listOf(
                "lib/x86/**",
                "lib/x86_64/**",
                "lib/armeabi-v7a/**",
                // Production PreferredBackend is CPU-only; drop NPU/GPU companions.
                "**/libQnn*.so",
                "**/libLiteRtDispatch_Qualcomm.so",
                "**/libLiteRtGpu*.so",
                "**/libLiteRtOpenCl*.so",
                "**/libLiteRtWebGpu*.so",
                "**/libLiteRtTopK*.so",
            )
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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

dependencies {
    testImplementation("junit:junit:4.12")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.19.2")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
    implementation("com.google.android.play:app-update:2.1.0")
}
