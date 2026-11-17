import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyPropertiesFile = System.getenv("WEAVER_ANDROID_KEY_PROPERTIES")
    ?.let { file(it) } ?: rootProject.file("key.properties")
val releaseKeyProperties = Properties()
val hasReleaseSigning = releaseKeyPropertiesFile.isFile
if (hasReleaseSigning) {
    releaseKeyPropertiesFile.inputStream().use { releaseKeyProperties.load(it) }
    for (key in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        require(!releaseKeyProperties.getProperty(key).isNullOrBlank()) {
            "Missing Android signing property: $key"
        }
    }
}
// Never silently produce a debug-signed or unsigned release.
gradle.taskGraph.whenReady {
    if (!hasReleaseSigning && allTasks.any {
        it.project == project && it.name.contains("Release", ignoreCase = true)
    }) {
        throw GradleException("Release signing requires android/key.properties or WEAVER_ANDROID_KEY_PROPERTIES")
    }
}

android {
    namespace = "net.dogpoo.weaver"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "net.dogpoo.weaver"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                val keyPath = System.getenv("WEAVER_ANDROID_KEYSTORE")
                    ?: releaseKeyProperties.getProperty("storeFile")
                val keyFile = File(keyPath)
                storeFile = if (keyFile.isAbsolute) keyFile
                    else File(releaseKeyPropertiesFile.parentFile, keyPath)
                storePassword = releaseKeyProperties.getProperty("storePassword")
                keyAlias = releaseKeyProperties.getProperty("keyAlias")
                keyPassword = releaseKeyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
