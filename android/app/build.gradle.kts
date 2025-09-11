import java.util.Properties
import java.io.File
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.tuempresa.base_app" // Ajusta si tu paquete es diferente
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true 
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_11.toString() }

    defaultConfig {
        applicationId = "com.tuempresa.base_app" // NO cambiar si ya publicaste
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // --- Firma para release usando key.properties ---
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
                println("⚠️ WARNING: key.properties no encontrado; se usará debug keystore.")
            }
        }
    }

buildTypes {
    getByName("debug") {
        isMinifyEnabled = false
        isShrinkResources = false
    }
    // Flutter usa "profile"; a veces hereda config que activa shrink
    maybeCreate("profile").apply {
        // si no existe, lo crea; si existe, lo modifica
        initWith(getByName("debug"))
        isMinifyEnabled = false
        isShrinkResources = false
        signingConfig = signingConfigs.getByName("release")
    }
    getByName("release") {
        signingConfig = signingConfigs.getByName("release")
        // Si no quieres optimizar todavía, pon ambos en false.
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
    }
}

    // Excluir licencias duplicadas (buena práctica)
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

flutter {
    source = "../.."
}
dependencies {
    implementation("com.android.billingclient:billing-ktx:6.2.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
