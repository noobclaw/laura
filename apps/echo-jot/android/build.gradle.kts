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
    project.evaluationDependsOn(":app")
}

// Plugin libraries that still declare an old compileSdk (whisper_ggml pins 34)
// fail AAR-metadata checks against ffmpeg_kit_flutter_new_min, which needs 35+.
// Lift every library module to the app's level; the plugin sources are fine
// with it.
subprojects {
    fun liftCompileSdk() {
        extensions.findByType<com.android.build.gradle.LibraryExtension>()?.apply {
            if ((compileSdk ?: 0) < 36) compileSdk = 36
        }
    }
    // evaluationDependsOn(":app") above already evaluated some modules, and
    // afterEvaluate throws on an evaluated project — apply directly then.
    if (state.executed) liftCompileSdk() else afterEvaluate { liftCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
