import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Load signing credentials ───────────────────────────────────────────────────
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) {
        load(FileInputStream(keyPropertiesFile))
    }
}

val keystoreAlias     = keyProperties.getProperty("keyAlias",      "ibraheem abd elhadi")
val keystorePassword  = keyProperties.getProperty("keyPassword",   "kcPY%-mJ=b6;eqL9i9:A")
val storeFileRelative = keyProperties.getProperty("storeFile",     "abd-elhadi-store.jks")
val storePassValue    = keyProperties.getProperty("storePassword", ".%502eJ!lr62z8/e}DhQ")

// Resolve the keystore file relative to android/app/
val keystoreFile = file(storeFileRelative)
val hasKeystore  = keystoreFile.exists()

android {
    namespace = "com.example.elegant_store"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.elegant_store"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    if (hasKeystore) {
        signingConfigs {
            create("release") {
                keyAlias      = keystoreAlias
                keyPassword   = keystorePassword
                storeFile     = keystoreFile
                storePassword = storePassValue
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = if (hasKeystore)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
            isMinifyEnabled   = false
            isShrinkResources = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
