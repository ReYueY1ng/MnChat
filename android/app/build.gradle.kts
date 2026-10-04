// Gradle Kotlin DSL 里 `java` 会被同名的 Java 插件扩展遮蔽，`java.util.Properties`
// 会被解析成 `java` 扩展上的 `util` 而编译失败，因此这里显式 import。
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名走 android/key.properties（不入库，见 android/key.properties.template）。
// 文件不存在时回退到 debug key，保证本地 `flutter run --release` 仍能跑通；
// 但 CI 与正式分发必须提供 key.properties，否则拿到的就是 debug 签名包。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "me.yuey1ng.mnchat"
    compileSdk = flutter.compileSdkVersion

    // AGP 9 推荐并会自动下载的 NDK 版本；CI 与普通构建都用它。
    // 本机若只装了别的 NDK，用 -Pmnchat.ndkVersion=<版本> 覆盖即可，
    // 避免把机器相关的版本硬写进仓库。
    ndkVersion = (project.findProperty("mnchat.ndkVersion") as String?)
        ?: "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "me.yuey1ng.mnchat"
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
        // Termux can only produce arm64-v8a (no x86_64 host toolchain support).
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
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
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // 没有 key.properties 时的兜底：仅供本地 `flutter run --release`，
                // 不要分发这种包（任何人都能用公开的 debug key 伪造升级包）。
                logger.warn(
                    "release 签名缺少 android/key.properties，" +
                        "本次产物使用 debug key，切勿分发。"
                )
                signingConfigs.getByName("debug")
            }
            // Disable shrinking/minification - avoids JVM crashes on Termux and
            // Termux aapt2 cannot handle resource optimization.
            isMinifyEnabled = false
            isShrinkResources = false
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
