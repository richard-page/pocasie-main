import java.util.Properties
import java.io.FileInputStream
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val playUploadSha1 = rootProject.file("play_upload_sha1.txt").readLines()
    .map { it.trim() }
    .lastOrNull { it.isNotEmpty() && !it.startsWith("#") }
    ?: "B9:C2:3E:69:E6:D7:05:3F:C8:10:18:13:1C:94:C5:8B:7A:5A:78:28"

val keystore = Properties()
var signingPropsFile: File? = null

// 1) android/key.properties + upload-keystore.jks v android/
// 2) %USERPROFILE%/.menopocasie/android/signing.properties
val projectSigningProps = rootProject.file("key.properties")
val userSigningProps =
    File(System.getProperty("user.home"), ".menopocasie/android/signing.properties")

when {
    projectSigningProps.exists() -> {
        signingPropsFile = projectSigningProps
        FileInputStream(projectSigningProps).use { keystore.load(it) }
    }
    userSigningProps.exists() -> {
        signingPropsFile = userSigningProps
        FileInputStream(userSigningProps).use { keystore.load(it) }
    }
}

fun resolveSigningStoreFile(path: String?): File? {
    if (!path.isNullOrBlank()) {
        val direct = File(path)
        if (direct.isAbsolute && direct.exists()) return direct
        if (direct.exists()) return direct
        signingPropsFile?.parentFile?.let { parent ->
            val nextToProps = File(parent, path)
            if (nextToProps.exists()) return nextToProps
        }
        val fromAndroidRoot = rootProject.file(path)
        if (fromAndroidRoot.exists()) return fromAndroidRoot
    }
    return rootProject.file("upload-keystore.jks").takeIf { it.exists() }
}

fun certificateSha1(certBytes: ByteArray): String =
    MessageDigest.getInstance("SHA-1")
        .digest(certBytes)
        .joinToString(":") { "%02X".format(it) }

fun uploadKeystoreSha1(storeFile: File, storePassword: String, keyAlias: String): String? {
    return try {
        val ks = KeyStore.getInstance(KeyStore.getDefaultType())
        FileInputStream(storeFile).use { ks.load(it, storePassword.toCharArray()) }
        val cert = ks.getCertificate(keyAlias) ?: return null
        certificateSha1(cert.encoded)
    } catch (_: Exception) {
        null
    }
}

val signingStoreFile = resolveSigningStoreFile(keystore.getProperty("storeFile"))
val signingAlias = keystore.getProperty("keyAlias") ?: "upload"
val signingStorePassword = keystore.getProperty("storePassword")
val hasSigningConfig =
    signingStoreFile != null &&
        !signingStorePassword.isNullOrBlank()

var releaseSigningSha1: String? = null
var canUseUploadKeystore = false
var playShaMatches = false

if (hasSigningConfig) {
    releaseSigningSha1 = uploadKeystoreSha1(
        signingStoreFile!!,
        signingStorePassword!!,
        signingAlias,
    )
    canUseUploadKeystore = releaseSigningSha1 != null
    playShaMatches = releaseSigningSha1?.equals(playUploadSha1, ignoreCase = true) == true
}

val isBundleRelease = gradle.startParameter.taskNames.any { name ->
    name.contains("bundle", ignoreCase = true) && name.contains("Release", ignoreCase = true)
}

if (isBundleRelease) {
    when {
        canUseUploadKeystore && playShaMatches ->
            logger.lifecycle("Play upload podpis OK (SHA-1 $releaseSigningSha1)")
        canUseUploadKeystore && !playShaMatches ->
            logger.warn(
                "AAB bude podpisany, ale SHA-1 ($releaseSigningSha1) nesedi s Play ($playUploadSha1). " +
                    "Na Play nahraj az po importe spravneho .jks."
            )
        else -> {
            logger.warn(
                "AAB bude podpisany DEBUG klucenom - Google Play ho ODMIETNE. " +
                    "Polož android/upload-keystore.jks + android/key.properties " +
                    "alebo spusti android\\import_signing.ps1"
            )
        }
    }
}

android {
    namespace = "sk.menopocasie.app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "sk.menopocasie.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = 198
        versionName = "2026.198"
        multiDexEnabled = true
    }

    if (canUseUploadKeystore) {
        signingConfigs {
            create("release") {
                keyAlias = signingAlias
                keyPassword = keystore.getProperty("keyPassword") ?: signingStorePassword
                storeFile = signingStoreFile
                storePassword = signingStorePassword
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = if (canUseUploadKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
        getByName("debug") {
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
