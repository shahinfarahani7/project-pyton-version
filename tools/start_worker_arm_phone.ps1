# Real ARM phone + Qwen3 text task E2E (USB adb reverse).
# Usage (repo root):
#   powershell -ExecutionPolicy Bypass -File tools\start_worker_arm_phone.ps1
#   powershell -ExecutionPolicy Bypass -File tools\start_worker_arm_phone.ps1 -SkipModelPush
param(
    [switch]$SkipModelPush,
    [switch]$SkipPortal,
    [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host ">> $Message" -ForegroundColor Cyan
}

function Test-Health([string]$Url) {
    $code = curl.exe -s -o NUL -w '%{http_code}' --max-time 4 $Url
    return $code -eq '200'
}

function Resolve-PhoneDevice([string]$Adb) {
    if ($Device) {
        return $Device
    }
    $lines = @(& $adb devices | Select-String 'device$')
    foreach ($line in $lines) {
        $id = $line.ToString().Split()[0]
        if ($id -notmatch '^127\.0\.0\.1:') {
            return $id
        }
    }
    return $null
}

Write-Host '=========================================='
Write-Host ' EdgeMint — ARM phone + real Qwen3 (text)'
Write-Host '=========================================='

Write-Step '1/5 Backend (Docker)'
& powershell -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\start_worker_dev.ps1') -SkipPortal | Out-Host
if (-not ((Test-Health 'http://127.0.0.1:8081/health/live') -and (Test-Health 'http://127.0.0.1:8080/health/live'))) {
    throw 'Backend not healthy on :8080 / :8081'
}
Write-Host '   Backend OK (8080 + 8081)'

Write-Step '2/5 adb — USB phone (not MEmu)'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) {
    $memuAdb = 'D:\Program Files\Microvirt\MEmu\adb.exe'
    if (Test-Path $memuAdb) { $adb = $memuAdb }
}
if (-not (Test-Path $adb)) {
    throw 'adb not found — install Android platform-tools'
}

$phone = Resolve-PhoneDevice $adb
if (-not $phone) {
    Write-Host ''
    Write-Host 'No USB phone found. On the phone:' -ForegroundColor Yellow
    Write-Host '  Settings → Developer options → USB debugging ON'
    Write-Host '  Connect USB → allow debugging prompt'
    Write-Host '  Then run: adb devices'
    throw 'Connect an ARM64 Android phone via USB and rerun.'
}

Write-Host "   Phone: $phone"
& $adb -s $phone reverse tcp:8081 tcp:8081
& $adb -s $phone reverse tcp:8080 tcp:8080
Write-Host '   adb reverse: 8081 (worker-gateway), 8080 (api-gateway)'
& $adb -s $phone reverse --list

$probe8081 = & $adb -s $phone shell "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8081/health/live" 2>&1
Write-Host "   Device probe :8081 → $probe8081"

Write-Step '3/6 Qwen3 model sideload (~586 MB, one-time)'
if ($SkipModelPush) {
    Write-Host '   Skipped (-SkipModelPush)'
} else {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\push_qwen_model_to_emulator.ps1') -DeviceId $phone
}

Write-Step '4/6 PaddleOCR model sideload'
if ($SkipModelPush) {
    Write-Host '   Skipped (-SkipModelPush)'
} else {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\push_paddleocr_models_to_device.ps1') -DeviceId $phone
}

Write-Step '5/6 Worker APK'
$apkCandidates = @(
    (Join-Path $Root 'dist\android-worker\app-release-usb.apk'),
    (Join-Path $Root 'dist\android-worker\app-release.apk'),
    (Join-Path $Root 'src\apps\worker\build\app\outputs\flutter-apk\app-release.apk')
)
$apk = $apkCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($apk) {
    Write-Host "   Installing $apk ..."
    & $adb -s $phone install -r $apk
} else {
    Write-Host '   No APK found — build first:' -ForegroundColor Yellow
    Write-Host '   cd src\apps\worker'
    Write-Host '   flutter build apk --release --dart-define=EDGEMINT_WORKER_BASE_URL=http://127.0.0.1:8081'
    Write-Host "   adb -s $phone install -r build\app\outputs\flutter-apk\app-release.apk"
}

if (-not $SkipPortal) {
    Write-Step '6/6 Customer portal'
    $portalRunning = Test-Health 'http://127.0.0.1:5173/'
    if ($portalRunning) {
        Write-Host '   Portal already running: http://localhost:5173'
    } else {
        Write-Host '   Start portal in another terminal:'
        Write-Host '   cd src\apps\customer-portal'
        Write-Host '   npm.cmd run dev -- --host 0.0.0.0 --port 5173'
    }
}

Write-Host ''
Write-Host '==========================================' -ForegroundColor Green
Write-Host ' Next steps on PHONE (real Qwen3):'
Write-Host '  1. Open EdgeMint Worker'
Write-Host '  2. Backend should show Connected (127.0.0.1:8081)'
Write-Host '  3. Home → Prepare Qwen3 (import sideloaded model if needed)'
Write-Host '     Status must NOT say "dev mock" — real ARM64 inference'
Write-Host '  4. Portal → New task → Text summarize (paste your text)'
Write-Host '  5. Worker → Poll & run'
Write-Host '  6. Portal → Tasks → Result shows real model output'
Write-Host '=========================================='
