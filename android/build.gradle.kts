import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

// Older Agora plugin Gradle metadata defaults to API 31 unless the host
// explicitly supplies the compile SDK. Keep it aligned with current Flutter.
rootProject.extra["compileSdkVersion"] = 36

allprojects {
    repositories {
        google()
        mavenCentral()
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
}
subprojects {
    pluginManager.withPlugin("com.android.library") {
        if (!pluginManager.hasPlugin("org.jetbrains.kotlin.android")) {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
        afterEvaluate {
            val kotlinJvmTarget = when (name) {
                "file_picker" -> JvmTarget.JVM_11
                else -> JvmTarget.JVM_17
            }
            tasks.withType<KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(kotlinJvmTarget)
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
