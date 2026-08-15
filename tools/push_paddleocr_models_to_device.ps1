# Push PP-OCRv5 mobile ONNX artifacts to Android device/emulator (PC sideload; no Git binaries).
param(
    [string]$MemuRoot = 'D:\Program Files\Microvirt\MEmu',
    [string]$ModelDir = 'dist/models/paddleocr',
    [string]$DeviceId = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$artifacts = @(
    'ppocrv5_mobile_det.onnx',
    'ppocrv5_mobile_rec_arabic.onnx',
    'ppocrv5_arabic_dict.txt'
)

New-Item -ItemType Directory -Force -Path $ModelDir | Out-Null
foreach ($name in $artifacts) {
    $local = Join-Path $ModelDir $name
    if (-not (Test-Path $local)) {
        Write-Host "Missing $local"
        Write-Host 'Download/export PP-OCRv5 Arabic/Persian ONNX artifacts to dist/models/paddleocr/ first.'
        Write-Host 'See src/apps/worker/README.md (PaddleOCR sideload section).'
        exit 1
    }
}

$deviceDir = '/sdcard/Edgemint/models/paddleocr'
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
if (-not $device) {
    throw 'No emulator/device connected'
}

Write-Host "Device: $device"
& $adb -s $device shell "mkdir -p $deviceDir /data/local/tmp/paddleocr" | Out-Null
foreach ($name in $artifacts) {
    $local = Join-Path $ModelDir $name
    & $adb -s $device push $local "$deviceDir/$name"
    & $adb -s $device push $local "/data/local/tmp/paddleocr/$name"
}
Write-Host ''
Write-Host 'Done. EdgeMint Worker imports OCR models from:'
Write-Host "  $deviceDir"
Write-Host 'Run an OCR pipeline task (document.ocr) after models are present.'
