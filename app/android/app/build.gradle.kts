plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localRuntime = layout.projectDirectory.dir("../runtime-bundle")
val hasLocalRuntime = localRuntime.file("assets/tokenworks/runtime/manifest.json").asFile.isFile

android {
    namespace = "io.github.yyyy530.tokenworks_go"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.yyyy530.tokenworks_go"
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

    if (hasLocalRuntime) {
        sourceSets.named("main") {
            assets.srcDir(localRuntime.dir("assets"))
            jniLibs.srcDir(localRuntime.dir("jniLibs"))
        }
        packaging.jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols += setOf(
                "**/libproot.so", "**/libproot-loader.so", "**/libtalloc.so", "**/libandroid-shmem.so",
            )
        }
        androidResources.noCompress += "xz"
    }
}

dependencies {
    implementation("org.apache.commons:commons-compress:1.27.1")
    implementation("org.tukaani:xz:1.10")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
