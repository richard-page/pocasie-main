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

// Pluginy s mandatory javac "Note: unchecked" (-nowarn nestačí).
// Pred compile doplní @SuppressWarnings do ich Java zdrojov v pub-cache.
subprojects {
    fun Project.patchPluginJavaUncheckedNotes() {
        if (name != "android_intent_plus" && name != "onesignal_flutter") return
        tasks.withType<JavaCompile>().configureEach {
            doFirst {
                val javaSources = source.filter { it.isFile && it.extension == "java" }
                for (target in javaSources) {
                    val original = target.readText()
                    if (original.contains("@SuppressWarnings(\"unchecked\")") ||
                        original.contains("@SuppressWarnings({\"unchecked\"") ||
                        original.contains("\"unchecked\"")) {
                        continue
                    }
                    val looksUnchecked =
                        original.contains("(Map<") ||
                            original.contains("(ArrayList") ||
                            original.contains("(List<") ||
                            original.contains("(HashMap")
                    if (!looksUnchecked) continue

                    val classMatch = Regex(
                        """(?m)^((?:public\s+|final\s+|abstract\s+)*)(class|interface)\s+""",
                    ).find(original) ?: continue
                    val insertAt = classMatch.range.first
                    val patched =
                        original.substring(0, insertAt) +
                            "@SuppressWarnings({\"unchecked\", \"rawtypes\"})\n" +
                            original.substring(insertAt)
                    target.writeText(patched)
                }
            }
        }
    }
    if (state.executed) {
        patchPluginJavaUncheckedNotes()
    } else {
        afterEvaluate { patchPluginJavaUncheckedNotes() }
    }
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