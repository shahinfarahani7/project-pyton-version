# One-time per machine: Gradle init mirror + Flutter SDK gradle settings (blocked Google Maven).
param(
    [string]$FlutterRoot = $(if ($env:FLUTTER_ROOT) { $env:FLUTTER_ROOT } else { 'C:\Users\Admin\flutter' })
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$gradleHome = Join-Path $env:LOCALAPPDATA 'EdgeMint\gradle-home'
$initDir = Join-Path $gradleHome 'init.d'
New-Item -ItemType Directory -Force -Path $initDir | Out-Null
Copy-Item -Force (Join-Path $Root 'tools\gradle\edgemint-mirror.init.gradle') (Join-Path $initDir 'edgemint-mirror.init.gradle')

$flutterGradleSettings = Join-Path $FlutterRoot 'packages\flutter_tools\gradle\settings.gradle.kts'
$flutterSettingsTemplate = Join-Path $Root 'tools\gradle\flutter_tools-settings.gradle.kts'
if (-not (Test-Path $flutterSettingsTemplate)) {
    throw "Missing $flutterSettingsTemplate"
}
if (Test-Path $flutterGradleSettings) {
    Copy-Item -Force $flutterSettingsTemplate $flutterGradleSettings
    Write-Host "Patched: $flutterGradleSettings"
} else {
    Write-Host "WARN: Flutter gradle settings not found at $flutterGradleSettings"
}

$env:GRADLE_USER_HOME = $gradleHome
Write-Host "GRADLE_USER_HOME=$gradleHome"
Write-Host "Before flutter build/run, run:"
Write-Host "  `$env:GRADLE_USER_HOME = '$gradleHome'"
Write-Host "  . .\tools\flutter_env.ps1"
