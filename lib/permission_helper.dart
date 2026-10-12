plugins {
id("com.android.application")
id("kotlin-android")
id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = org.jetbrains.kotlin.konan.properties.Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
localPropertiesFile.inputStream().use { localProperties.load(it) }
}

val flutterVersionCode = localProperties.getProperty("flutter.versionCode")?.toIntOrNull() ?: 1
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0"

android {
namespace = "com.example.personass"
compileSdk = 34
ndkVersion = "25.1.8937393"

compileOptions {
sourceCompatibility = JavaVersion.VERSION_1_8
targetCompatibility = JavaVersion.VERSION_1_8
}

kotlinOptions {
jvmTarget = "1.8"
}

sourceSets {
getByName("main").java.srcDirs("src/main/kotlin")
}

defaultConfig {
applicationId = "com.example.personass"
minSdk = 21
targetSdk = 34
versionCode = flutterVersionCode
versionName = flutterVersionName
multiDexEnabled = true
}

buildTypes {
release {
signingConfig = signingConfigs.getByName("debug")
isMinifyEnabled = false
isShrinkResources = false
}
}
}

flutter {
source = "../.."
}

dependencies {
implementation("androidx.multidex:multidex:2.0.1")
}