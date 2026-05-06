import java.io.File
import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("keystore.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

fun loadSdkDirFromLocalProperties(): File? {
    val lp = rootProject.file("local.properties")
    if (!lp.exists()) return null
    val p = Properties()
    lp.inputStream().use { p.load(it) }
    val dir = p.getProperty("sdk.dir") ?: return null
    return File(dir)
}

fun listCompleteNdkVersions(sdk: File): List<String> {
    val ndkRoot = File(sdk, "ndk")
    if (!ndkRoot.isDirectory) return emptyList()
    return ndkRoot.listFiles()?.filter { child ->
        child.isDirectory && File(child, "source.properties").isFile
    }?.map { it.name } ?: emptyList()
}

fun compareNdkLabels(a: String, b: String): Int {
    val pa = a.split(".").map { it.toIntOrNull() ?: 0 }
    val pb = b.split(".").map { it.toIntOrNull() ?: 0 }
    val n = maxOf(pa.size, pb.size)
    for (i in 0 until n) {
        val da = pa.getOrElse(i) { 0 }
        val db = pb.getOrElse(i) { 0 }
        if (da != db) return da.compareTo(db)
    }
    return 0
}

fun pickNewestNdk(versions: List<String>): String? {
    if (versions.isEmpty()) return null
    return versions.reduce { acc, v -> if (compareNdkLabels(v, acc) > 0) v else acc }
}

val preferredNdk: String =
    (project.findProperty("android.ndkVersion") as String?)?.takeIf { it.isNotBlank() }
        ?: "26.1.10909125"

val resolvedNdkVersion: String = run {
    val sdk = loadSdkDirFromLocalProperties()
    if (sdk != null) {
        val pinnedDir = File(File(sdk, "ndk"), preferredNdk)
        if (File(pinnedDir, "source.properties").isFile) {
            return@run preferredNdk
        }
        val complete = listCompleteNdkVersions(sdk)
        val best = pickNewestNdk(complete)
        if (best != null) {
            logger.lifecycle(
                "Hesabix: preferred NDK '$preferredNdk' not under Sdk/ndk (or incomplete); " +
                    "using newest local kit with source.properties: $best",
            )
            return@run best
        }
    }
    throw GradleException(
        "No usable Android NDK: '$preferredNdk' is not installed and no folder under " +
            "${sdk?.let { File(it, "ndk").absolutePath } ?: "(sdk.dir missing)"} contains source.properties. " +
            "Install when online (e.g. sdkmanager \"ndk;$preferredNdk\") or sync Sdk/ndk from another PC. " +
            "Incomplete ndk/* folders (no source.properties) are ignored.",
    )
}

android {
    namespace = "ir.hsxn.hesabix_ui"
    compileSdk = 36
    // Prefer android/gradle.properties (android.ndkVersion); if missing/offline, use newest *complete* local NDK.
    ndkVersion = resolvedNdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "ir.hsxn.hesabix_ui"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"]!!)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
