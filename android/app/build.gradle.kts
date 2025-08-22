plugins {
    id("com.android.application")
    id("kotlin-android")
    // El plugin de Flutter debe ir después de los de Android y Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

android {
    namespace = "com.tuempresa.base_app" // ← deja tu namespace/paquete
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // ApplicationId definitivo. Si ya publicaste, NO lo cambies después.
        applicationId = "com.tuempresa.base_app"
        minSdk = 23                  // Sube/baja si alguna lib lo requiere. (21 suele valer)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // --- Firma de release leyendo android/key.properties ---
    signingConfigs {
        create("release") {
            val keystoreProps = Properties()
            val keystoreFile = rootProject.file("key.properties")
            if (keystoreFile.exists()) {
                keystoreProps.load(FileInputStream(keystoreFile))
                storeFile = file(keystoreProps["storeFile"] as String)
                storePassword = keystoreProps["storePassword"] as String?
                keyAlias = keystoreProps["keyAlias"] as String?
                keyPassword = keystoreProps["keyPassword"] as String?
            } else {
                println("WARNING: key.properties no encontrado; se usará debug keystore si ejecutas local.")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            // sin cambios
        }
        getByName("release") {
            // Firma de release (si no existe key.properties, Gradle fallará al firmar)
            signingConfig = signingConfigs.getByName("release")

            // Optimización para Play
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // (Opcional) Empaquetado determinista
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

flutter {
    source = "../.."
}
