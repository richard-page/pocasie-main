import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// --- Release signing: načítaj android/key.properties ---
val keystore = Properties()
val kpFile = rootProject.file("key.properties")
val hasKeystoreProperties = kpFile.exists()
if (hasKeystoreProperties) {
    FileInputStream(kpFile).use { keystore.load(it) }
}
val storeFilePath = keystore.getProperty("storeFile")
val hasStoreFile = !storeFilePath.isNullOrBlank() && rootProject.file(storeFilePath).exists()
val canSignRelease = hasKeystoreProperties && hasStoreFile
val isReleaseTaskRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("release", ignoreCase = true)
}

android {
    namespace = "sk.menopocasie.app"
    compileSdk = 36                 // ↑ aktualizované podľa pluginov
    ndkVersion = "27.0.12077973"    // ↑ aktualizované podľa pluginov

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "sk.menopocasie.app"
        minSdk = flutter.minSdkVersion                 // Flutter pluginy už nepodporujú <21
        targetSdk = 36
        versionCode = 177
        versionName = "2026.177"
        multiDexEnabled = true
    }

    if (canSignRelease) {
        signingConfigs {
            create("release") {
                keyAlias = keystore.getProperty("keyAlias")
                keyPassword = keystore.getProperty("keyPassword")
                storeFile = rootProject.file(keystore.getProperty("storeFile"))
                storePassword = keystore.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (canSignRelease) {
                signingConfig = signingConfigs.getByName("release")
            } else if (isReleaseTaskRequested) {
                throw GradleException(
                    "Release signing is not configured. Create android/key.properties and keystore file. " +
                        "You can copy android/key.properties.example and update values."
                )
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
        getByName("debug") {
            // debug podpis ponechaný
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}