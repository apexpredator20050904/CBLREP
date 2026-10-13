import com.android.build.api.variant.LibraryAndroidComponentsExtension

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

// Force every Android subproject up to compileSdk 36 so the whole plugin graph
// builds: flutter_plugin_android_lifecycle requires API 36+, but some plugins
// (e.g. file_picker) ship compiled against 34. The hook is registered when the
// library plugin is applied, and finalizeDsl runs after each subproject's own
// script has executed (file_picker hardcodes `compileSdk 34`) but before AGP 9
// finalizes the property. A plain afterEvaluate cannot even be registered here
// because Gradle 9 eagerly evaluates subprojects first, and
// gradle.projectsEvaluated is already "too late to set compileSdk".

subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<LibraryAndroidComponentsExtension>("androidComponents") {
            finalizeDsl { dsl ->
                dsl.compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
