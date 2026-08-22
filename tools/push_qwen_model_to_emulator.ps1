# Download Qwen3 once on the PC, then sideload to device (no in-app download).
param(
    [string]$MemuRoot = 'D:\Program Files\Microvirt\MEmu',
    [string]$ModelDir = 'dist/models',
    [string]$BackendUrl = 'http://127.0.0.1:8081',
    [string]$DeviceId = '',
    [switch]$SkipDownload,
    [switch]$ForceDownload
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$modelFile = 'Qwen3-0.6B.litertlm'
$localPath = Join-Path $ModelDir $modelFile
$deviceDir = '/sdcard/Edgemint/models'
$devicePath = "$deviceDir/$modelFile"
# Full artifact is ~586 MB; reject truncated downloads (e.g. partial curl).
$MinQwenBytes = 550MB

New-Item -ItemType Directory -Force -Path (Split-Path $localPath) | Out-Null

function Test-QwenModelComplete {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        return $false
    }
    $size = (Get-Item $Path).Length
    if ($size -lt $MinQwenBytes) {
        Write-Host "Incomplete Qwen model at $Path ($([math]::Round($size / 1MB, 1)) MB, need >= $([math]::Round($MinQwenBytes / 1MB)) MB)" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Invoke-QwenDownload {
    if (Test-Path $localPath) {
        Remove-Item $localPath -Force
    }
    Write-Host "Downloading $modelFile (~586 MB) ..."
    $url = "$BackendUrl/models/mdv_qwen3_0_6b/files/$modelFile"
    $code = curl.exe -s -o NUL -w '%{http_code}' --max-time 8 $url
    if ($code -eq '200') {
        curl.exe -L --fail --retry 3 --retry-delay 5 -o $localPath $url
    } else {
        Write-Host "Backend proxy unavailable ($code) - trying Hugging Face ..."
        $hf = 'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/' + $modelFile
        curl.exe -L --fail --retry 3 --retry-delay 5 -o $localPath $hf
    }
    if (-not (Test-QwenModelComplete -Path $localPath)) {
        $size = if (Test-Path $localPath) { (Get-Item $localPath).Length } else { 0 }
        throw "Qwen download incomplete ($size bytes). Check network/backend and retry."
    }
    $mb = [math]::Round((Get-Item $localPath).Length / 1MB, 1)
    Write-Host "Saved: $localPath ($mb MB)"
}

if ($ForceDownload) {
    Invoke-QwenDownload
} elseif (-not $SkipDownload) {
    if (Test-QwenModelComplete -Path $localPath) {
        $mb = [math]::Round((Get-Item $localPath).Length / 1MB, 1)
        Write-Host "Using cached model: $localPath ($mb MB)"
    } else {
        if (Test-Path $localPath) {
            Remove-Item $localPath -Force
        }
        Invoke-QwenDownload
    }
} elseif (-not (Test-QwenModelComplete -Path $localPath)) {
    throw "Model not found or incomplete at $localPath (run without -SkipDownload or use -ForceDownload)"
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
