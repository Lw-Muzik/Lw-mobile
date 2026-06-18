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

    // Some Flutter plugins (e.g. bonsoir_android 5.1.6) hard-pin an older
    // compileSdk (33) that their androidx dependencies now reject (they require
    // 34+). Force every Android subproject up to at least 34; the app already
    // targets 36, so this only bumps the offending plugins. Registered here,
    // before the evaluationDependsOn below triggers evaluation, so the
    // afterEvaluate hook is still valid.
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            val android = ext as com.android.build.gradle.BaseExtension
            val current = android.compileSdkVersion?.removePrefix("android-")?.toIntOrNull()
            if (current == null || current < 34) {
                android.compileSdkVersion(36)
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
