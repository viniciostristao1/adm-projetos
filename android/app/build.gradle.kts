plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase — processa o google-services.json (login com Google).
    id("com.google.gms.google-services")
}

import java.io.FileInputStream
import java.util.Properties

android {
    namespace = "com.admprojetos.adm_projetos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.admprojetos.adm_projetos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // ProGuard: mantém as classes do ML Kit (OCR) no release —
            // sem isso o R8 quebra o build.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            val kp = rootProject.file("key.properties")
            if (kp.exists()) {
                // Assinatura FIXA (upload-keystore.jks) -> permite atualizar o app
                // por cima sem conflito de assinatura. key.properties e o keystore
                // NAO ficam no git (secrets + .gitignore).
                val props = Properties()
                FileInputStream(kp).use { props.load(it) }
                signingConfig = signingConfigs.create("release") {
                    keyAlias = props["keyAlias"] as String
                    keyPassword = props["keyPassword"] as String
                    storePassword = props["storePassword"] as String
                    storeFile = rootProject.file("app/upload-keystore.jks")
                }
            } else {
                // Sem keystore local (ex.: dev), usa a chave de debug.
                signingConfig = signingConfigs.getByName("debug")
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
