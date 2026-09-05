import java.net.URL
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// CI writes android/key.properties + the keystore from repo secrets.
// Absent locally → release falls back to debug signing so `flutter run --release` still works.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// ---------------------------------------------------------------------------
// ncnn (Tencent, BSD-3) prebuilt for Android with Vulkan. Downloaded once per
// build directory from the pinned GitHub release so a clean CI checkout builds
// without any committed binaries. The archive holds arm64-v8a / armeabi-v7a /
// x86_64 (and more) as static libs + CMake config; src/main/cpp/CMakeLists.txt
// picks the ABI it is compiling for.
// ---------------------------------------------------------------------------
val ncnnVersion = "20260526"
val ncnnArchive = "ncnn-$ncnnVersion-android-vulkan"
val ncnnUrl = "https://github.com/Tencent/ncnn/releases/download/$ncnnVersion/$ncnnArchive.zip"
val ncnnDir = layout.buildDirectory.dir("ncnn").get().asFile
val ncnnRoot = File(ncnnDir, ncnnArchive)

val fetchNcnn by tasks.registering {
    description = "Download the prebuilt ncnn Android package used by the native upscaler."
    outputs.dir(ncnnRoot)
    outputs.upToDateWhen { File(ncnnRoot, "arm64-v8a/lib/libncnn.a").exists() }
    doLast {
        if (File(ncnnRoot, "arm64-v8a/lib/libncnn.a").exists()) return@doLast
        ncnnDir.mkdirs()
        val zip = File(ncnnDir, "$ncnnArchive.zip")
        if (!zip.exists() || zip.length() < 1_000_000) {
            logger.lifecycle("Downloading $ncnnUrl")
            val tmp = File(zip.path + ".part")
            URL(ncnnUrl).openStream().use { input -> tmp.outputStream().use { input.copyTo(it) } }
            if (!tmp.renameTo(zip)) throw GradleException("could not move ncnn archive into place")
        }
        logger.lifecycle("Extracting ${zip.name}")
        copy {
            from(zipTree(zip))
            into(ncnnDir)
        }
        if (!File(ncnnRoot, "arm64-v8a/lib/libncnn.a").exists()) {
            throw GradleException("ncnn archive layout unexpected: ${ncnnRoot.path}")
        }
    }
}

// The CMake configure/build tasks are created lazily per ABI/variant; hook
// every one of them (and preBuild for good measure) onto the download.
tasks.named("preBuild") { dependsOn(fetchNcnn) }
tasks.configureEach {
    if (name.startsWith("configureCMake") || name.startsWith("buildCMake") ||
        name.contains("externalNativeBuild", ignoreCase = true)) {
        dependsOn(fetchNcnn)
    }
}

android {
    namespace = "com.noobclaw.photolift"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.noobclaw.photolift"
        // Android 10: ImageDecoder target-size decoding, MediaStore
        // RELATIVE_PATH / IS_PENDING inserts without a storage permission, and
        // a Vulkan driver on effectively every device. Older phones would need
        // WRITE_EXTERNAL_STORAGE and could not run the model anyway.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DNCNN_ROOT=${ncnnRoot.absolutePath}",
                    "-DANDROID_STL=c++_static",
                )
            }
        }
        ndk {
            // Matches what Flutter ships (android-arm, android-arm64, android-x64);
            // x86_64 keeps the CI emulator smoke test on a real native build.
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    if (keystoreProperties.isNotEmpty()) {
        signingConfigs {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Keeps the JNI entry points and the progress callback that the
            // native layer resolves by name (see proguard-rules.pro).
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
