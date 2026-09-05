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
                throw GradleException(
                    "Thiếu Android release signing. Cấu hình app/android/key.properties " +
                        "hoặc ANDROID_STORE_FILE/ANDROID_STORE_PASSWORD/ANDROID_KEY_ALIAS/ANDROID_KEY_PASSWORD. " +
                        "Chỉ dùng ALLOW_DEBUG_SIGNING=true cho build local tạm thời."
                )
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
