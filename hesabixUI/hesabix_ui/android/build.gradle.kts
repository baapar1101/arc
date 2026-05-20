val hesabixGradleMirror: String =
    providers.gradleProperty("hesabix.gradle.mirror")
        .orElse("https://gradle.mirror.hesabix.ir")
        .get()
        .trimEnd('/')

// مخازن: اول آینهٔ داخلی؛ در صورت ۴۰۲/۵۰۲ Runflare، Maven Central و google به‌عنوان fallback.
allprojects {
    repositories {
        maven { url = uri("${hesabixGradleMirror}/android/maven2/") }
        maven { url = uri("${hesabixGradleMirror}/maven2/") }
        maven { url = uri("${hesabixGradleMirror}/gradle-plugins/") }
        mavenCentral()
        google()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    afterEvaluate {
        if (project.hasProperty("android")) {
            repositories {
                maven { url = uri("${hesabixGradleMirror}/android/maven2/") }
                maven { url = uri("${hesabixGradleMirror}/maven2/") }
                maven { url = uri("${hesabixGradleMirror}/gradle-plugins/") }
                mavenCentral()
                google()
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")

    buildscript {
        repositories {
            maven { url = uri("${hesabixGradleMirror}/android/maven2/") }
            maven { url = uri("${hesabixGradleMirror}/maven2/") }
            maven { url = uri("${hesabixGradleMirror}/gradle-plugins/") }
            mavenCentral()
            google()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
