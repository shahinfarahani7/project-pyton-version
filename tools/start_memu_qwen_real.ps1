# MEmu: attempt REAL Qwen3 (not dev-mock). Requires arm64 native lib support in the emulator.
# Standard x86 MEmu cannot run LiteRT-LM - enable ARM native libs in MEmu settings first.
#
# Usage (repo root):
#   powershell -ExecutionPolicy Bypass -File tools\start_memu_qwen_real.ps1
param(
    [string]$MemuRoot = 'D:\Program Files\Microvirt\MEmu',
    [string[]]$EmulatorPorts = @('21503', '16384', '21513', '7555', '5555'),
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

Write-Host '=========================================='
Write-Host ' MEmu + real Qwen3 (experimental)'
Write-Host '=========================================='
Write-Host ''
Write-Host 'Before continuing in MEmu:' -ForegroundColor Yellow
Write-Host '  1. Multi-MEmu: new instance Android 9+ 64-bit recommended'
Write-Host '  2. MEmu Settings: choose ARM native library for apps (v9.2+)'
Write-Host '  3. Allocate 4GB+ RAM to the instance'
Write-Host ''

& powershell -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\start_worker_dev.ps1') -SkipPortal | Out-Host

$adb = Join-Path $MemuRoot 'adb.exe'
if (-not (Test-Path $adb)) {
    throw "adb not found at $adb"
}

$device = $null
foreach ($port in $EmulatorPorts) {
    & $adb connect "127.0.0.1:$port" 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    $line = & $adb devices | Select-String 'device$' | Select-Object -First 1
    if ($line) {
        $device = $line.ToString().Split()[0]
        break
    }
}
if (-not $device) {
    throw 'No MEmu device - start MEmu first'
}

Write-Host ''
Write-Host "Device: $device"
Write-Host "Primary ABI: $(& $adb -s $device shell getprop ro.product.cpu.abi)"
Write-Host "ABI list:    $(& $adb -s $device shell getprop ro.product.cpu.abilist)"
Write-Host ''

& $adb -s $device reverse tcp:8081 tcp:8081
& $adb -s $device reverse tcp:8080 tcp:8080

Write-Host 'Pushing Qwen3 model (~586 MB)...'
$modelPath = Join-Path $Root 'dist\models\Qwen3-0.6B.litertlm'
$pushArgs = @{
    MemuRoot = $MemuRoot
    DeviceId = $device
}
if (Test-Path $modelPath) {
    $pushArgs['SkipDownload'] = $true
}
& (Join-Path $Root 'tools\push_qwen_model_to_emulator.ps1') @pushArgs

$apkCandidates = @(
    (Join-Path $Root 'dist\android-worker\app-release.apk'),
    (Join-Path $Root 'src\apps\worker\build\app\outputs\flutter-apk\app-release.apk')
)

$apk = $apkCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $SkipBuild -or -not $apk) {
    Write-Host ''
    Write-Host 'Building worker APK with WORKER_FORCE_REAL_INFERENCE=true ...'
    & powershell -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\build_worker_apk.ps1') `
        -WorkerBaseUrl 'http://127.0.0.1:8081' `
        -ForceRealInference
    $apk = Join-Path $Root 'dist\android-worker\app-release.apk'
}

if (-not (Test-Path $apk)) {
    throw "APK not found at $apk - build failed or use without -SkipBuild"
}

Write-Host "Installing $apk ..."
& $adb -s $device install -r --abi arm64-v8a $apk 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host 'arm64-v8a install failed - trying default install...' -ForegroundColor Yellow
    & $adb -s $device install -r $apk
}

Write-Host ''
Write-Host '==========================================' -ForegroundColor Green
Write-Host ' On MEmu worker app:'
Write-Host '  - Backend: Connected'
Write-Host '  - Prepare Qwen3: wait for Ready (NOT dev mock)'
Write-Host '  - If model fails to load: this MEmu instance cannot run LiteRT'
Write-Host ' Portal: http://localhost:5173 - Text summarize - Poll and run'
Write-Host '=========================================='
