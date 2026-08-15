# Download Qwen3 once on the PC, then sideload to MEmu/LDPlayer (no in-app download).
param(
    [string]$MemuRoot = 'D:\Program Files\Microvirt\MEmu',
    [string]$ModelDir = 'dist/models',
    [string]$BackendUrl = 'http://127.0.0.1:8081',
    [string]$DeviceId = '',
    [switch]$SkipDownload
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$modelFile = 'Qwen3-0.6B.litertlm'
$localPath = Join-Path $ModelDir $modelFile
$deviceDir = '/sdcard/Edgemint/models'
$devicePath = "$deviceDir/$modelFile"

New-Item -ItemType Directory -Force -Path (Split-Path $localPath) | Out-Null

if (-not $SkipDownload -and -not (Test-Path $localPath)) {
    Write-Host "Downloading $modelFile (~586 MB) ..."
    $url = "$BackendUrl/models/mdv_qwen3_0_6b/files/$modelFile"
    $code = curl.exe -s -o NUL -w '%{http_code}' --max-time 8 $url
    if ($code -eq '200') {
        curl.exe -L --fail -o $localPath $url
    } else {
        Write-Host "Backend proxy unavailable ($code) - trying Hugging Face ..."
        $hf = 'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/' + $modelFile
        curl.exe -L --fail -o $localPath $hf
    }
    Write-Host "Saved: $localPath"
} elseif (Test-Path $localPath) {
    Write-Host "Using cached model: $localPath"
} else {
    throw "Model not found at $localPath (run without -SkipDownload)"
}

$adbCandidates = @(
    (Join-Path $MemuRoot 'adb.exe'),
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')
)
$adb = $adbCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $adb) {
    throw 'adb not found - open MEmu or install Android platform-tools'
}

$device = if ($DeviceId) {
    $DeviceId
} else {
    (& $adb devices | Select-String 'device$' | Select-Object -First 1).ToString().Split()[0]
}
if (-not $device) {
    foreach ($port in @('21503', '16384', '21513', '7555', '5555')) {
        & $adb connect "127.0.0.1:$port" 2>&1 | Out-Null
        $device = (& $adb devices | Select-String 'device$' | Select-Object -First 1).ToString().Split()[0]
        if ($device) { break }
    }
}
# Prefer USB phone over emulator when multiple devices listed.
$all = @(& $adb devices | Select-String 'device$' | ForEach-Object { $_.ToString().Split()[0] })
if (-not $DeviceId) {
    $usb = $all | Where-Object { $_ -notmatch '^127\.0\.0\.1:' } | Select-Object -First 1
    if ($usb) { $device = $usb }
}
if (-not $device) {
    throw 'No emulator/device connected'
}

Write-Host "Device: $device"
& $adb -s $device shell "mkdir -p $deviceDir" | Out-Null
& $adb -s $device push $localPath $devicePath
& $adb -s $device push $localPath "/data/local/tmp/$modelFile"
& $adb -s $device shell "chmod 644 $devicePath /data/local/tmp/$modelFile" 2>$null
Write-Host ''
Write-Host 'Done. Open EdgeMint Worker - the app imports from:'
Write-Host "  $devicePath"
Write-Host 'No in-app download needed. Model persists across app restarts.'
