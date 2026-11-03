import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Read release credentials from android/key.properties (ignored by Git).
val releaseKeyProperties = Properties()
val releaseKeyFile = rootProject.file("key.properties")
if (releaseKeyFile.isFile) {
    releaseKeyFile.inputStream().use { releaseKeyProperties.load(it) }
}
val releaseKeyFields = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseKey = releaseKeyFields.all { !releaseKeyProperties.getProperty(it).isNullOrBlank() }

// Fail production release tasks rather than silently shipping a debug-signed bundle.
if (gradle.startParameter.taskNames.any { it.contains("ProductionRelease", ignoreCase = true) } && !hasReleaseKey) {
    throw GradleException("Missing Android release signing credentials. Set android/key.properties before building productionRelease.")
}

android {
    namespace = "com.example.catering_pro"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.catering_pro"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "environment"
    productFlavors {
        create("production") {
            dimension = "environment"
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_display_name", "Caterer Pro STAGING")
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = releaseKeyProperties.getProperty("keyAlias")
                keyPassword = releaseKeyProperties.getProperty("keyPassword")
                storeFile = file(releaseKeyProperties.getProperty("storeFile"))
                storePassword = releaseKeyProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Do not sign release variants with the development debug key.
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else null
        }
    }
}

flutter {
    source = "../.."
}

// Guard against quietly falling back to the root production google-services.json.
// Staging compilation is blocked until the *suffixed* app has been registered.
val verifyStagingFirebaseConfig by tasks.registering {
    doLast {
        val file = project.file("src/staging/google-services.json")
        if (!file.isFile) {
            throw GradleException("Missing android/app/src/staging/google-services.json. Register com.example.catering_pro.staging in caterer-pro-staging before building.")
        }
        val contents = file.readText()
        if (!contents.contains("\"project_id\": \"caterer-pro-staging\"") ||
            !contents.contains("\"package_name\": \"com.example.catering_pro.staging\"")) {
            throw GradleException("Staging google-services.json must belong to caterer-pro-staging / com.example.catering_pro.staging")
        }
    }
}
tasks.configureEach {
    if (name.startsWith("processStaging") && name.endsWith("GoogleServices")) {
        dependsOn(verifyStagingFirebaseConfig)
    }
}
