# One-time per machine: Gradle init mirror + Flutter SDK gradle patch (blocked Google Maven).
param(
    [string]$FlutterRoot = 'C:\Users\Admin\flutter'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$gradleHome = Join-Path $env:LOCALAPPDATA 'EdgeMint\gradle-home'
$initDir = Join-Path $gradleHome 'init.d'
New-Item -ItemType Directory -Force -Path $initDir | Out-Null
Copy-Item -Force (Join-Path $Root 'tools\gradle\edgemint-mirror.init.gradle') (Join-Path $initDir 'edgemint-mirror.init.gradle')

$flutterGradleSettings = Join-Path $FlutterRoot 'packages\flutter_tools\gradle\settings.gradle.kts'
if (Test-Path $flutterGradleSettings) {
    @'
// EdgeMint: keep empty so root android/settings.gradle.kts owns pluginManagement mirrors.
'@ | Set-Content -Path $flutterGradleSettings -Encoding utf8
    Write-Host "Patched: $flutterGradleSettings"
}

Write-Host "GRADLE_USER_HOME=$gradleHome"
Write-Host "Before flutter build, run:"
Write-Host "  `$env:GRADLE_USER_HOME = '$gradleHome'"
