# USB path: phone reaches PC backend via adb reverse (no LAN/Wi-Fi needed).
# 1. Enable USB debugging on the phone and connect by cable.
# 2. Run this script on the PC.
# 3. Install dist/android-worker/app-release-usb.apk (127.0.0.1 backend URL).

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'

if (-not (Test-Path $adb)) {
    throw "adb not found at $adb — install Android platform-tools."
}

$devices = & $adb devices | Select-String 'device$'
if (-not $devices) {
    throw 'No adb device found. Enable USB debugging and accept the RSA prompt on the phone.'
}

& $adb reverse tcp:8081 tcp:8081
Write-Host 'adb reverse tcp:8081 tcp:8081 — OK'
Write-Host ''
Write-Host 'On the phone browser, open: http://127.0.0.1:8081/health/live'
Write-Host 'Expected: quick JSON health response (not a spinning loader).'
Write-Host ''
Write-Host 'Install APK: dist\android-worker\app-release-usb.apk'
Write-Host 'Then tap Download Qwen3 0.6B in the worker app.'
