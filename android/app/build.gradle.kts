import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Release Signing Configuration ──────────────────────────────────────
// Reads signing credentials from android/key.properties (not committed to VCS).
// In CI, key.properties is auto-generated from GitHub Secrets.
// Release builds MUST use the release keystore — no fallback to debug signing.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.digitalplanetx.firstpro"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "com.digitalplanetx.firstpro"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Signing credentials come exclusively from key.properties.
            // If the file is missing, the release build will fail with a clear error
            // rather than silently falling back to debug signing.
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Production signing — uses the release keystore exclusively.
            // No fallback to debug signing: if key.properties is absent,
            // the build intentionally fails so the issue is caught early.
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
