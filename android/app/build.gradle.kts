import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.tuempresa.base_app"

    // Deja que Flutter controle esto por ahora.
    // Cuando estés seguro de tener SDK 35 instalado puedes forzar:
    // compileSdk = 35
    compileSdk = flutter.compileSdkVersion

    // ✅ Recomendado: usar NDK r28+ cuando lo instales desde Android Studio.
    // Por ahora puedes dejar este valor, pero cuando veas en el SDK Manager
    // algo tipo "ndk;28.0.xxxxx", cámbialo exactamente a ese string.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.tuempresa.base_app" // NO cambiar si ya publicaste
        minSdk = flutter.minSdkVersion


        // Igual que compileSdk: hoy lo maneja Flutter.
        // Cuando migres a Android 15 puedes fijar targetSdk = 35.
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

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
        maybeCreate("profile").apply {
            initWith(getByName("debug"))
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("release")
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            // Si quieres menos problemas al depurar, puedes desactivar:
            // isMinifyEnabled = false
            // isShrinkResources = false
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }

        // ⚠️ IMPORTANTE: NO toques jniLibs/useLegacyPackaging aquí,
        // deja que Flutter/AGP manejen las libs nativas.
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.android.billingclient:billing-ktx:6.2.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
