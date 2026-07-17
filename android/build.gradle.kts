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

// Plugins disagree on JVM level (home_widget hardcodes Java/Kotlin 1.8; glance needs ≥11).
// Override AFTER each plugin's own android{} block. Skip :app (already finalized).
subprojects {
    fun Project.forceJvm17AfterPluginScripts() {
        if (plugins.hasPlugin("com.android.application")) {
            // :app sets VERSION_17 itself; reassignment can be finalized already.
            return
        }
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.compileOptions?.apply {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    // evaluationDependsOn(":app") may evaluate some projects early — don't call afterEvaluate then.
    if (state.executed) {
        forceJvm17AfterPluginScripts()
    } else {
        afterEvaluate { forceJvm17AfterPluginScripts() }
    }
}

// home_widget uses "glance-appwidget:1.+" which can resolve to alpha builds
// requiring compileSdk 37 + AGP 9.1. Pin a stable release compatible with SDK 36.
subprojects {
    configurations.configureEach {
        resolutionStrategy {
            force("androidx.glance:glance-appwidget:1.1.1")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}