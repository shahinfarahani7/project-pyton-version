// Patched into FLUTTER_ROOT/packages/flutter_tools/gradle/settings.gradle.kts
// by tools/setup_gradle_mirror.ps1 — required for the :gradle composite build.

dependencyResolutionManagement {
    // PREFER_SETTINGS: allow the app settings.gradle.kts pluginManagement mirrors.
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.myket.ir") }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
