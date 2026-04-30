// نمونه برای ~/.gradle/init.gradle.kts — رونوشت به مسیر فوق یا ادغام
// آینهٔ چندمسیره: https://gradle.mirror.hesabix.ir؛ فقط Maven Central با mvn: maven.mirror + config/maven/settings-hesabix-mirror.xml

import org.gradle.api.artifacts.repositories.MavenArtifactRepository
import org.gradle.api.artifacts.dsl.RepositoryHandler

fun RepositoryHandler.enableMirror() {
    all {
        if (this is MavenArtifactRepository) {
            val originalUrl = this.url.toString().removeSuffix("/")
            urlMappings[originalUrl]?.let { mirrorUrl ->
                println("Repository[$originalUrl] -> $mirrorUrl")
                setUrl(uri(mirrorUrl))
            }
        }
    }
}

val base = "https://gradle.mirror.hesabix.ir"
val urlMappings = mapOf(
    "https://repo.maven.apache.org/maven2" to "$base/maven2/",
    "https://dl.google.com/dl/android/maven2" to "$base/android/maven2/",
    "https://plugins.gradle.org/m2" to "$base/gradle-plugins/"
)

gradle.allprojects {
    buildscript {
        repositories.enableMirror()
    }
    repositories.enableMirror()
}

gradle.settingsEvaluated {
    pluginManagement.repositories.enableMirror()
    dependencyResolutionManagement.repositories.enableMirror()
}
