import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use { signingProperties.load(it) }
}

fun signingValue(name: String): String? =
    System.getenv("ANDROID_${name.uppercase()}")?.takeIf { it.isNotBlank() }
        ?: signingProperties.getProperty(name)?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("STORE_FILE")
val releaseStorePassword = signingValue("STORE_PASSWORD")
val releaseKeyAlias = signingValue("KEY_ALIAS")
val releaseKeyPassword = signingValue("KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }
val allowDebugSigning =
    System.getenv("ALLOW_DEBUG_SIGNING")?.equals("true", ignoreCase = true) == true
        || project.findProperty("allowDebugSigning")?.toString()?.equals("true", ignoreCase = true) == true
        || project.findProperty("ALLOW_DEBUG_SIGNING")?.toString()?.equals("true", ignoreCase = true) == true

// QA 143: a profile/release APK without APP_API_BASE_URL installs fine and
// then only says "Chưa liên lạc được máy chủ". Stop the build instead.
// Flutter passes --dart-define values base64-encoded in -Pdart-defines.
val dartDefines = project.findProperty("dart-defines")?.toString().orEmpty()
    .split(",")
    .filter { it.isNotBlank() }
    .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
val hasApiBaseUrl = dartDefines.any {
    it.startsWith("APP_API_BASE_URL=") && it.substringAfter("=").isNotBlank()
}
val allowMissingApiUrl =
    project.findProperty("allowMissingApiUrl")?.toString()?.equals("true", ignoreCase = true) == true
if (gradle.startParameter.taskNames.any {
        it.contains("Release", ignoreCase = true) || it.contains("Profile", ignoreCase = true)
    } && !hasApiBaseUrl && !allowMissingApiUrl) {
    throw GradleException(
        "APP_API_BASE_URL is not set. Build with " +
            "--dart-define=APP_API_BASE_URL=https://<api-host> " +
            "(or -PallowMissingApiUrl=true for a build that sets the server in the app)."
    )
}

if (gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) } &&
    !hasReleaseSigning && !allowDebugSigning) {
    throw GradleException(
        "Release signing is not configured. Set ANDROID_STORE_FILE, " +
            "ANDROID_STORE_PASSWORD, ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD. " +
            "For an explicitly debug-signed QA artifact only, set ALLOW_DEBUG_SIGNING=true."
    )
}

android {
    namespace = "com.bes.vinbatery"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.bes.vinbatery"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.create("release") {
                    storeFile = file(releaseStoreFile!!)
                    storePassword = releaseStorePassword
                    keyAlias = releaseKeyAlias
                    keyPassword = releaseKeyPassword
                }
            } else if (allowDebugSigning) {
                signingConfigs.getByName("debug")
            } else {
                // A debug build can configure this project without silently
                // producing a debug-signed release artifact.
                null
            }
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
