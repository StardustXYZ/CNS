import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release key (cns-firma.jks) and its passwords are in android/key.properties, which stays
// on the PC and out of git (see key.properties.example). Without it a release build stops: an
// APK signed with the debug key must not be published by mistake, because the phones that have
// the real version could not update to it. For a test APK that stays on this PC, set the
// environment variable CNS_FIRMA_DI_PROVA=1: it is then signed with the debug key.
val releaseKey = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !releaseKey.getProperty(it).isNullOrBlank() }
val debugSigningAllowed = System.getenv("CNS_FIRMA_DI_PROVA") == "1"

android {
    namespace = "it.stardustxyz.cns"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        applicationId = "it.stardustxyz.cns"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
        }
    }
}

// Only a build of the release APK or bundle is stopped: tests, "flutter run" and debug builds
// do not need the key.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { it.project == project && it.name.matches(Regex("(assemble|bundle|package)Release")) }
    if (buildsRelease && !hasReleaseKey && !debugSigningAllowed) {
        throw GradleException(
            "Manca la chiave di firma: copia key.properties da Desktop/cns-chiavi in android/ (vedi mobile/README.md). " +
                "Un APK firmato con la chiave di prova non va pubblicato: chi ha la versione vera non potrebbe aggiornarlo. " +
                "Per un APK di prova solo per te, imposta CNS_FIRMA_DI_PROVA=1."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}

flutter {
    source = "../.."
}
