val hesabixGradleMirror: String =
    providers.gradleProperty("hesabix.gradle.mirror")
        .orElse("https://gradle.mirror.hesabix.ir")
        .get()
        .trimEnd('/')

allprojects {
    repositories {
        maven { url = uri("${hesabixGradleMirror}/android/maven2/") }
        maven { url = uri("${hesabixGradleMirror}/maven2/") }
        maven { url = uri("${hesabixGradleMirror}/gradle-plugins/") }
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
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
