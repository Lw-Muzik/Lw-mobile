import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "x.a.zix"
    compileSdk = flutter.compileSdkVersion
    // Pin to NDK r28+, which links native libs with 16 KB page alignment by
    // default (required for Android 15+ / 16 KB-page devices). Leaving this as
    // flutter.ndkVersion can resolve to an older NDK that produces 4 KB-aligned
    // libs.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "x.a.zix"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = 28
        versionName = "1.1.8"
        manifestPlaceholders["appAuthRedirectScheme"] = "x.a.zix"

        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
             signingConfig = signingConfigs.getByName("release")
             isMinifyEnabled = true
             isShrinkResources = false
             proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

// Force transitive native dependencies to versions whose bundled .so files are
// 16 KB page-aligned (Android 15+/16 KB-page devices, Play upload requirement).
// Evidence: the graph was resolving CameraX 1.3.3 and ML Kit barcode 17.2.0,
// both 4 KB-aligned. These pins move them to the aligned releases. DataStore is
// pinned to 1.1.7 because its newer 1.2.x line regressed 16 KB alignment.
configurations.all {
    resolutionStrategy {
        force(
            "androidx.camera:camera-core:1.5.3",
            "androidx.camera:camera-camera2:1.5.3",
            "androidx.camera:camera-lifecycle:1.5.3",
            "androidx.camera:camera-view:1.5.3",
            "com.google.mlkit:barcode-scanning:17.3.0",
            "com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1",
            "androidx.datastore:datastore:1.1.7",
            "androidx.datastore:datastore-core:1.1.7",
            "androidx.datastore:datastore-core-android:1.1.7",
            "androidx.datastore:datastore-preferences:1.1.7",
            "androidx.datastore:datastore-preferences-core:1.1.7",
        )
    }
}

dependencies {
    implementation("com.mpatric:mp3agic:0.9.1")
    implementation("net.jthink:jaudiotagger:3.0.1")
    implementation("androidx.media3:media3-exoplayer:1.4.1")
}

flutter {
    source = "../.."
}
