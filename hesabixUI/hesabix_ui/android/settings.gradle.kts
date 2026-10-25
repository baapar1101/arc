pluginManagement {
    val hesabixGradleMirror: String = run {
        val p = java.util.Properties()
        val gradleProps = file("gradle.properties")
        if (gradleProps.isFile) {
            gradleProps.inputStream().use { p.load(it) }
        }
        p.getProperty("hesabix.gradle.mirror", "https://gradle.mirror.hesabix.ir").trimEnd('/')
    }

    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.myket.ir/") }
        maven { url = uri("${hesabixGradleMirror}/") }
        maven { url = uri("${hesabixGradleMirror}/android/maven2/") }
        maven { url = uri("${hesabixGradleMirror}/maven2/") }
        maven { url = uri("${hesabixGradleMirror}/gradle-plugins/") }
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    resolutionStrategy {
        eachPlugin {
            when (requested.id.id) {
                "com.android.application" ->
                    useModule("com.android.tools.build:gradle:${requested.version}")
                "org.jetbrains.kotlin.android" ->
                    useModule("org.jetbrains.kotlin:kotlin-gradle-plugin:${requested.version}")
            }
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
