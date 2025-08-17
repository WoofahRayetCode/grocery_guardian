import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.woofahrayetcode.groceryguardian"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.woofahrayetcode.groceryguardian"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
    targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    // Default app icon reference (overridden by flavors below)
    manifestPlaceholders["appIconRef"] = "@mipmap/ic_launcher"
    // Default AdMob App ID (Google test App ID) to avoid runtime crash when ads SDK is present
    manifestPlaceholders["admobAppId"] = "ca-app-pub-3940256099942544~3347511713"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    flavorDimensions += listOf("dist")
    productFlavors {
        create("play") {
            dimension = "dist"
            // Distinct appId for side-by-side installs from OSS/dev
            applicationId = "com.woofahrayetcode.groceryguardian.play"
            resValue("string", "app_name", "Grocery Guardian")
            // Use the common launcher icon to avoid maintaining duplicate PNGs
            manifestPlaceholders["appIconRef"] = "@mipmap/ic_launcher"
            // Optionally override admobAppId here with a real App ID when ready
        }
        create("oss") {
            dimension = "dist"
            applicationId = "com.woofahrayetcode.groceryguardian.oss"
            resValue("string", "app_name", "Grocery Guardian OSS")
            manifestPlaceholders["appIconRef"] = "@mipmap/ic_launcher"
        }
    }
}

flutter {
    source = "../.."
}

java {
    toolchain {
    // Use JDK 21 toolchain (AGP/Gradle can run on 21) while compiling with source/target 17
    languageVersion.set(JavaLanguageVersion.of(21))
    }
}

// --- Dynamic versioning: compile date/time ---
// We compute a UTC timestamp once at configuration time and use it for all variants in this build.
// - Release: versionName = YYYY.MM.DD (compile date), versionCode = YYYYMMDD (int)
// - Debug:   versionName = YYYY.MM.DD HH:mm:ss UTC (exact compile time), versionCode = YYYYMMDD
val buildInstant: ZonedDateTime = ZonedDateTime.now(ZoneId.of("UTC"))
val dateFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy.MM.dd")
val timeFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy.MM.dd HH:mm:ss 'UTC'")
val versionCodeFromDate: Int = buildInstant.format(DateTimeFormatter.ofPattern("yyyyMMdd")).toInt()
val releaseVersionName: String = buildInstant.format(dateFormatter)
val debugVersionName: String = buildInstant.format(timeFormatter)

androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.outputs.forEach { output ->
            output.versionCode.set(versionCodeFromDate)
            output.versionName.set(releaseVersionName)
        }
    }
    onVariants(selector().withBuildType("debug")) { variant ->
        variant.outputs.forEach { output ->
            output.versionCode.set(versionCodeFromDate)
            output.versionName.set(debugVersionName)
        }
    }
}
