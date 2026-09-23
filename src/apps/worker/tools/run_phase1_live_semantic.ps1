# Phase 1 live semantic acceptance (device-native Qwen2.5 1.5B).
#
# Reuses an already-installed debug APK only when using flutter drive with a
# test-built binary. For integration_test, prefer:
#   flutter test integration_test/phase1_live_semantic_test.dart -d emulator-5554 ...
# First run may take a long time while Gradle packages the ~1.5 GB bundled model.

param(
  [string]$Device = "emulator-5554",
  [string]$BackendUrl = "http://172.20.34.71:8081",
  [string]$InstalledApk = "..\..\..\artifacts\worker-installed-debug.apk",
  [string]$DeviceSourcePath = "/sdcard/Edgemint/phase1/source.txt",
  [string]$HostSourcePath = ""
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$env:NO_PROXY = "127.0.0.1,localhost"
. ..\..\..\tools\flutter_env.ps1

$apk = Resolve-Path $InstalledApk
$defines = @(
  "--dart-define=PHASE1_LIVE_INFERENCE=true",
  "--dart-define=WORKER_USE_BACKEND_ARTIFACT=false",
  "--dart-define=WORKER_VERBOSE_TASK_LOGS=true",
  "--dart-define=WORKER_VERBOSE_TASK_CONTENT=true",
  "--dart-define=EDGEMINT_WORKER_BASE_URL=$BackendUrl"
)

Write-Host "==> L1 frozen-partials reduce-only"
flutter test integration_test/phase1_live_semantic_test.dart `
  -d $Device `
  --plain-name "L1 frozen partials" `
  @defines

if ($HostSourcePath -ne "") {
  $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
  & $adb -s $Device shell mkdir -p /sdcard/Edgemint/phase1 | Out-Null
  Write-Host "==> Push verified source to device"
  & $adb -s $Device push $HostSourcePath $DeviceSourcePath
  Write-Host "==> L7 full-source map/reduce"
  flutter test integration_test/phase1_live_semantic_test.dart `
    -d $Device `
    --use-application-binary=$apk `
    --plain-name "L7 full-source" `
    --dart-define=PHASE1_FULL_SOURCE_PATH=$DeviceSourcePath `
    @defines
} else {
  Write-Host "Skipping L7 (pass -HostSourcePath to a verified 13,769-char source file)"
}
