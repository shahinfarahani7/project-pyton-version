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

function Wait-BackendHealth {
    param([int]$TimeoutSeconds = 120)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ((Test-GatewayHealth) -and ((curl.exe -s -o NUL -w '%{http_code}' --max-time 4 http://127.0.0.1:8080/health/live) -eq '200')) {
            return $true
        }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Test-AdbDeviceHttpCode {
    param(
        [string]$Adb,
        [string]$Device,
        [string]$Url
    )
    $probes = @(
        "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 $Url",
        "wget -q -O /dev/null --server-response $Url 2>&1 | awk '/HTTP\// { code = `$2 } END { print code }'",
        "toybox wget -q -O /dev/null --server-response $Url 2>&1 | awk '/HTTP\// { code = `$2 } END { print code }'"
    )
    foreach ($probe in $probes) {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $raw = (& $Adb -s $Device shell $probe 2>&1 | Out-String).Trim()
        } finally {
            $ErrorActionPreference = $prev
        }
        if ($raw -match '^\d{3}$') { return $raw }
    }
    return $null
}

function Test-AdbDeviceTcp {
    param(
        [string]$Adb,
        [string]$Device,
        [int]$Port
    )
    $probes = @(
        "nc -z -w 3 127.0.0.1 $Port",
        "busybox nc -z -w 3 127.0.0.1 $Port",
        "toybox nc -z -w 3 127.0.0.1 $Port"
    )
    foreach ($probe in $probes) {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $Adb -s $Device shell $probe 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { return $true }
        } finally {
            $ErrorActionPreference = $prev
        }
    }
    return $false
}

function Test-AdbReverseRules {
    param(
        [string]$Adb,
        [string]$Device,
        [int[]]$Ports
    )
    $list = (& $Adb -s $Device reverse --list 2>&1 | Out-String)
    foreach ($port in $Ports) {
        if ($list -notmatch "tcp:$port\s+tcp:$port") { return $false }
    }
    return $true
}

function Apply-DevHotPatches {
    # Image tags lag repo source; sync the full Python package instead of cherry-picking files.
    $edgemintSrc = Join-Path $Root 'src/backend/edgemint'
    if (-not (Test-Path $edgemintSrc)) {
        throw "Missing $edgemintSrc"
    }
    docker cp $edgemintSrc edgemint-worker-registry-1:/app/src/backend/ 2>$null | Out-Null
    docker cp $edgemintSrc edgemint-api-gateway-1:/app/src/backend/ 2>$null | Out-Null
    docker cp (Join-Path $edgemintSrc 'services/worker_gateway.py') edgemint-worker-gateway-1:/app/src/backend/edgemint/services/worker_gateway.py 2>$null | Out-Null
    docker cp (Join-Path $edgemintSrc 'services/model_registry.py') edgemint-model-registry-1:/app/src/backend/edgemint/services/model_registry.py 2>$null | Out-Null
    Invoke-Quiet {
        docker exec -u 0 edgemint-api-gateway-1 python -m pip install --root-user-action=ignore --no-cache-dir python-multipart==0.0.20 2>$null | Out-Null
    }
    docker restart edgemint-worker-gateway-1 edgemint-worker-registry-1 edgemint-api-gateway-1 edgemint-model-registry-1 2>$null | Out-Null
    if (-not (Wait-BackendHealth -TimeoutSeconds 90)) {
        Write-Host '   WARN: backend slow to recover; continuing if worker-gateway is healthy.'
    }
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

$assignCode = curl.exe -s -o NUL -w '%{http_code}' --max-time 15 -H 'Authorization: Bearer dev-token' http://127.0.0.1:8081/assignments:next
if ($assignCode -eq '404') {
    Write-Host '   Applying dev hot-patches (assignments route)...'
    Apply-DevHotPatches
    Start-Sleep -Seconds 5
    $assignCode = curl.exe -s -o NUL -w '%{http_code}' --max-time 15 -H 'Authorization: Bearer dev-token' http://127.0.0.1:8081/assignments:next
}
Write-Host "   assignments:next probe = $assignCode (200/204 = OK, 000 = registry still starting)"

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

$deviceCode = Test-AdbDeviceHttpCode -Adb $adb -Device $device -Url 'http://127.0.0.1:8081/health/live'
$apiCode = Test-AdbDeviceHttpCode -Adb $adb -Device $device -Url 'http://127.0.0.1:8080/health/live'
if ($deviceCode) {
    Write-Host "   device probe 127.0.0.1:8081 = $deviceCode"
    Write-Host "   device probe 127.0.0.1:8080 = $apiCode"
    if ($deviceCode -ne '200' -or ($apiCode -and $apiCode -ne '200')) {
        throw 'adb reverse failed — emulator must reach PC on 8080 (portal API) and 8081 (worker gateway).'
    }
} else {
    Write-Host '   device has no curl/wget - using TCP + reverse-list checks'
    if (-not (Test-AdbReverseRules -Adb $adb -Device $device -Ports @(8080, 8081))) {
        throw 'adb reverse rules missing for tcp:8080 and tcp:8081.'
    }
    $gwTcp = Test-AdbDeviceTcp -Adb $adb -Device $device -Port 8081
    $apiTcp = Test-AdbDeviceTcp -Adb $adb -Device $device -Port 8080
    Write-Host "   device TCP 127.0.0.1:8081 = $(if ($gwTcp) { 'open' } else { 'closed' })"
    Write-Host "   device TCP 127.0.0.1:8080 = $(if ($apiTcp) { 'open' } else { 'closed' })"
    if (-not $gwTcp -or -not $apiTcp) {
        Write-Host '   WARN: could not verify HTTP from device; reverse rules are set - continue if worker uses LAN IP.'
    }
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
        $lanIp = (
            Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object {
                $_.IPAddress -notlike '127.*' -and
                $_.PrefixOrigin -ne 'WellKnown' -and
                $_.InterfaceAlias -notlike '*WSL*' -and
                $_.InterfaceAlias -notlike '*Default Switch*'
            } |
            Select-Object -First 1 -ExpandProperty IPAddress
        )
        Write-Host "   Portal starting: http://localhost:5173 (job $($portalJob.Id))"
        if ($lanIp) {
            Write-Host "   LAN access:    http://${lanIp}:5173"
        }
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
Write-Host '   4. Keep availability ON - tasks run automatically'
Write-Host ''
Write-Host ' APK: dist\android-worker\app-release-usb.apk'
Write-Host '=========================================='
