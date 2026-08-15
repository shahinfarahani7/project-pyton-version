# Connect mobile worker to local backend (Docker worker-gateway on :8081).
param(
    [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

Write-Host '== EdgeMint worker backend connection =='

$health = curl.exe -s -o NUL -w '%{http_code}' --max-time 5 http://127.0.0.1:8081/health/live
Write-Host "PC localhost:8081 health = $health"
if ($health -ne '200') {
    Write-Host 'Starting backend stack...'
    docker compose --env-file .env.docker -f compose.yaml -f compose.backend.yaml up -d worker-gateway worker-registry api-gateway 2>&1 | Out-Host
    Start-Sleep -Seconds 8
    $health = curl.exe -s -o NUL -w '%{http_code}' --max-time 5 http://127.0.0.1:8081/health/live
    Write-Host "PC localhost:8081 health = $health"
}

$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) {
    Write-Host 'adb not found — install Android platform-tools for USB/emulator reverse.'
    exit 0
}

if (-not $Device) {
    $Device = (& $adb devices | Select-String 'device$' | Select-Object -First 1).ToString().Split()[0]
}

if ($Device) {
    Write-Host "Using adb device: $Device"
    & $adb -s $Device reverse tcp:8081 tcp:8081
    & $adb -s $Device reverse tcp:8080 tcp:8080
    & $adb -s $Device reverse --list
    $shell8081 = & $adb -s $Device shell "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8081/health/live" 2>&1
    $shell8080 = & $adb -s $Device shell "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8080/health/live" 2>&1
    Write-Host "Device probe 127.0.0.1:8081 health = $shell8081"
    Write-Host "Device probe 127.0.0.1:8080 health = $shell8080"
    Write-Host ''
    Write-Host 'Install APK: dist\android-worker\app-release.apk (auto-falls back to 127.0.0.1)'
    Write-Host 'In app: tap sync icon or reopen app — Backend should show Connected.'
} else {
    Write-Host 'No adb device. For real phone on Wi-Fi, phone must share LAN with PC (172.20.34.x).'
    Write-Host '172.20.34.71:8081 is often blocked — prefer USB + adb reverse.'
}
