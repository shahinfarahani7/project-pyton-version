# One command: Docker backend + MEmu/LDPlayer adb reverse + health checks (+ optional portal).
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File tools\start_worker_dev.ps1
param(
    [switch]$SkipPortal,
    [string]$MemuRoot = 'D:\Program Files\Microvirt\MEmu',
    [string[]]$EmulatorPorts = @('21503', '16384', '21513', '7555', '5555')
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

function Invoke-Quiet([scriptblock]$Block) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Block } finally { $ErrorActionPreference = $prev }
}

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host ">> $Message" -ForegroundColor Cyan
}

function Wait-Docker {
    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $deadline) {
        docker info 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Test-GatewayHealth {
    $code = curl.exe -s -o NUL -w '%{http_code}' --max-time 4 http://127.0.0.1:8081/health/live
    return $code -eq '200'
}

function Apply-DevHotPatches {
    $pairs = @(
        @('src/backend/edgemint/services/worker_gateway.py', 'edgemint-worker-gateway-1', '/app/src/backend/edgemint/services/worker_gateway.py'),
        @('src/backend/edgemint/dev/worker_assignments.py', 'edgemint-worker-registry-1', '/app/src/backend/edgemint/dev/worker_assignments.py'),
        @('src/backend/edgemint/services/worker_registry.py', 'edgemint-worker-registry-1', '/app/src/backend/edgemint/services/worker_registry.py'),
        @('src/backend/edgemint/dev/dev_worker_api.py', 'edgemint-api-gateway-1', '/app/src/backend/edgemint/dev/dev_worker_api.py'),
        @('src/backend/edgemint/dev/portal_api.py', 'edgemint-api-gateway-1', '/app/src/backend/edgemint/dev/portal_api.py'),
        @('src/backend/edgemint/dev/worker_task_inputs.py', 'edgemint-api-gateway-1', '/app/src/backend/edgemint/dev/worker_task_inputs.py'),
        @('src/backend/edgemint/dev/fixtures.py', 'edgemint-api-gateway-1', '/app/src/backend/edgemint/dev/fixtures.py'),
        @('src/backend/edgemint/dev/assignment_bridge.py', 'edgemint-api-gateway-1', '/app/src/backend/edgemint/dev/assignment_bridge.py'),
        @('src/backend/edgemint/dev/worker_assignments.py', 'edgemint-api-gateway-1', '/app/src/backend/edgemint/dev/worker_assignments.py'),
        @('src/backend/edgemint/dev/model_artifact_proxy.py', 'edgemint-model-registry-1', '/app/src/backend/edgemint/dev/model_artifact_proxy.py'),
        @('src/backend/edgemint/services/model_registry.py', 'edgemint-model-registry-1', '/app/src/backend/edgemint/services/model_registry.py')
    )
    foreach ($pair in $pairs) {
        $src = Join-Path $Root $pair[0]
        if (-not (Test-Path $src)) { continue }
        docker cp $src "$($pair[1]):$($pair[2])" 2>$null | Out-Null
    }
    docker restart edgemint-worker-gateway-1 edgemint-worker-registry-1 edgemint-api-gateway-1 edgemint-model-registry-1 2>$null | Out-Null
    Start-Sleep -Seconds 8
}

function Resolve-AdbDevice {
    param([string]$Adb)
    $lines = & $adb devices | Select-String 'device$'
    if ($lines) {
        return ($lines | Select-Object -First 1).ToString().Split()[0]
    }
    foreach ($port in $EmulatorPorts) {
        $target = "127.0.0.1:$port"
        Write-Host "   trying adb connect $target ..."
        & $adb connect $target 2>&1 | Out-Null
        Start-Sleep -Seconds 1
        $lines = & $adb devices | Select-String 'device$'
        if ($lines) {
            return ($lines | Select-Object -First 1).ToString().Split()[0]
        }
    }
    return $null
}

Write-Host '=========================================='
Write-Host ' EdgeMint worker dev - one-shot startup'
Write-Host '=========================================='

Write-Step '1/4 Docker'
if (-not (Wait-Docker)) {
    $dockerExe = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerExe) {
        Write-Host '   Starting Docker Desktop...'
        Start-Process $dockerExe
        if (-not (Wait-Docker)) {
            throw 'Docker is not running. Open Docker Desktop manually, wait until Ready, then rerun this script.'
        }
    } else {
        throw 'Docker Desktop not found. Install/start Docker, then rerun.'
    }
}
Write-Host '   Docker OK'

Write-Step '2/4 Backend (worker-gateway :8081)'
if (-not (Test-Path '.env.docker')) {
    if (Test-Path '.env.docker.example') {
        Copy-Item '.env.docker.example' '.env.docker'
    } else {
        throw 'Missing .env.docker'
    }
}
Invoke-Quiet { py -3.13 tools/generate_compose_backend.py 2>$null | Out-Null }
Invoke-Quiet { docker compose --env-file .env.docker -f compose.yaml -f compose.backend.yaml up -d 2>&1 | Out-Null }

$deadline = (Get-Date).AddMinutes(2)
while ((Get-Date) -lt $deadline) {
    if (Test-GatewayHealth) { break }
    Start-Sleep -Seconds 3
}
if (-not (Test-GatewayHealth)) {
    throw 'Backend did not become healthy on http://127.0.0.1:8081/health/live'
}
Write-Host '   PC backend OK (8081)'

$assignCode = curl.exe -s -o NUL -w '%{http_code}' --max-time 4 -H 'Authorization: Bearer dev-token' http://127.0.0.1:8081/assignments:next
if ($assignCode -eq '404') {
    Write-Host '   Applying dev hot-patches (assignments route)...'
    Apply-DevHotPatches
    $assignCode = curl.exe -s -o NUL -w '%{http_code}' --max-time 4 -H 'Authorization: Bearer dev-token' http://127.0.0.1:8081/assignments:next
}
Write-Host "   assignments:next probe = $assignCode"

Write-Step '3/4 MEmu / emulator (adb reverse)'
$adbCandidates = @(
    (Join-Path $MemuRoot 'adb.exe'),
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')
)
$adb = $adbCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $adb) {
    throw "adb not found. Install MEmu or Android platform-tools. Tried: $($adbCandidates -join ', ')"
}
Write-Host "   adb: $adb"

$device = Resolve-AdbDevice -Adb $adb
if (-not $device) {
    throw 'No emulator detected. Open MEmu, enable ADB in settings, then rerun tools/start_worker_dev.ps1'
}

Write-Host "   device: $device"
& $adb -s $device reverse tcp:8081 tcp:8081
& $adb -s $device reverse tcp:8080 tcp:8080
& $adb -s $device reverse --list

$deviceCode = & $adb -s $device shell "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://127.0.0.1:8081/health/live" 2>&1
$apiCode = & $adb -s $device shell "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://127.0.0.1:8080/health/live" 2>&1
Write-Host "   device probe 127.0.0.1:8081 = $deviceCode"
Write-Host "   device probe 127.0.0.1:8080 = $apiCode"
if ($deviceCode -ne '200' -or $apiCode -ne '200') {
    throw 'adb reverse failed — emulator must reach PC on 8080 (portal API) and 8081 (worker gateway).'
}
Write-Host '   emulator -> PC backend OK'

Write-Step '4/4 Customer portal (optional)'
if (-not $SkipPortal) {
    $portalRunning = curl.exe -s -o NUL -w '%{http_code}' --max-time 2 http://127.0.0.1:5173/ 2>$null
    if ($portalRunning -eq '200') {
        Write-Host '   Portal already running: http://localhost:5173'
    } else {
        $portalJob = Start-Job -Name 'edgemint-portal' -ScriptBlock {
            param($RootPath)
            Set-Location (Join-Path $RootPath 'src\apps\customer-portal')
            $env:VITE_DEV_API_PROXY = 'http://127.0.0.1:8080'
            npm run dev -- --host 0.0.0.0 --port 5173 2>&1
        } -ArgumentList $Root
        Start-Sleep -Seconds 6
        Write-Host "   Portal starting: http://localhost:5173 (job $($portalJob.Id))"
    }
} else {
    Write-Host '   Skipped (-SkipPortal)'
}

Write-Host ''
Write-Host '=========================================='
Write-Host ' READY - on emulator:'
Write-Host '   1. Open EdgeMint Worker app'
Write-Host '   2. Tap Sync'
Write-Host '   3. Portal http://localhost:5173 - Dev login - New Task'
Write-Host '   4. Missions - Poll and run next task'
Write-Host ''
Write-Host ' APK: dist\android-worker\app-release-usb.apk'
Write-Host '=========================================='
