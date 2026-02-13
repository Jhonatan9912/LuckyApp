import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory
import com.android.build.api.dsl.ApplicationExtension
import com.android.build.api.dsl.LibraryExtension

plugins {
    id("dev.flutter.flutter-gradle-plugin") apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

/**
 * (Opcional) Reubicar directorios de build para ahorrar I/O.
 * Si no lo necesitas, puedes borrar todo este bloque.
 */
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

/**
 * Asegura que :app se evalúe primero (evita algunos problemas de orden)
 */
subprojects {
    project.evaluationDependsOn(":app")
}

/**
 * Tarea clean
 */
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

/**
 * ✅ Forzar la misma versión de NDK para TODOS los módulos
 * (app + plugins como rive_common)
 */
subprojects {
    plugins.withId("com.android.application") {
        extensions.configure<ApplicationExtension> {
            ndkVersion = "28.2.13676358"
        }
    }

    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension> {
            ndkVersion = "28.2.13676358"
        }
    }
}
