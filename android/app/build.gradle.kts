import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// 1. 加载 key.properties (Kotlin 语法)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.yuchen.birdid"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    // 2. 签名配置 (Kotlin 语法)
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    defaultConfig {
        applicationId = "com.yuchen.birdid"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            // 3. 应用签名
            signingConfig = signingConfigs.getByName("release")
            
            // 下面这些是 release 默认配置，保留即可
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

// 自动上传 APK 到 Azure Blob Storage
tasks.register("uploadToAzure", Exec::class) {
    group = "upload"
    description = "Upload APK to Azure Blob Storage"
    
    val apkDir = file("$buildDir/outputs/flutter-apk")
    val apkFile = fileTree(apkDir) {
        include("*.apk")
    }.singleFile
    
    doFirst {
        println("📤 准备上传: ${apkFile.absolutePath}")
    }
    
    commandLine("bash", "../upload_to_azure.sh", apkFile.absolutePath)
}

// 构建 release APK 后自动上传
tasks.named("assembleRelease") {
    finalizedBy("uploadToAzure")
}