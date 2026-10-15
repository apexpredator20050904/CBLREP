import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Reads android/app/google-services.json into Android resources for Firebase.
    id("com.google.gms.google-services")
}

// ── Release signing ────────────────────────────────────────────────────────
// Credentials live in android/key.properties (git-ignored) next to the
// keystore it names. When the file is absent — CI without secrets, or a fresh
// clone — the build falls back to the debug key so `flutter build apk` still
// succeeds for local smoke tests; only Play Store / distribution uploads need
// the real key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "ph.cblrep.app"
    // file_picker (chat attachments) pulls in flutter_plugin_android_lifecycle,
    // whose AAR requires compiling against Android API 36+. Pinned explicitly
    // rather than inheriting Flutter's lower default so the plugin graph builds.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uses java.time APIs; desugaring back-ports
        // them for older Android versions (see coreLibraryDesugaring below).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ph.cblrep.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Google Maps API key resolution order: -PMAPS_API_KEY=… (CI),
        // local.properties `mapsApiKey=…`, then an empty dev fallback.
        val mapsKey = (project.findProperty("MAPS_API_KEY")
            ?: project.rootProject.file("local.properties").useLines { lines ->
                lines.firstOrNull { it.startsWith("mapsApiKey=") }?.substringAfter('=')
            }) as String?
        manifestPlaceholders["mapsApiKey"] = mapsKey ?: ""
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Real release key when key.properties is present; debug key
            // otherwise so a clone without secrets still builds.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
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

flutter {
    source = "../.."
}

dependencies {
    // Required by flutter_local_notifications (java.time back-port).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
