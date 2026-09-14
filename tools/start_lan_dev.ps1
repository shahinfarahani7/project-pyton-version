# One command: Docker backend + dev hot-patch + portal (+ optional marketing) for LAN access.
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File tools\start_lan_dev.ps1
param(
    [switch]$SkipPortal,
    [switch]$IncludeMarketing,
    [switch]$SkipFirewall
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

function Get-LanIp {
    (
        Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -notlike '127.*' -and
            $_.PrefixOrigin -ne 'WellKnown' -and
            $_.InterfaceAlias -notlike '*WSL*' -and
            $_.InterfaceAlias -notlike '*Default Switch*' -and
            $_.InterfaceAlias -notlike '*vEthernet*'
        } |
        Select-Object -First 1 -ExpandProperty IPAddress
    )
}

function Update-LanDockerEnv {
    param([string]$LanIp)
    if (-not (Test-Path '.env.docker')) { return }
    $lines = Get-Content '.env.docker'
    $lines = $lines | ForEach-Object {
        if ($_ -match '^EDGEMINT_WORKER_API_PUBLIC_BASE_URL=') { "EDGEMINT_WORKER_API_PUBLIC_BASE_URL=http://${LanIp}:8081"; return }
        if ($_ -match '^EDGEMINT_DEV_API_PUBLIC_URL=') { "EDGEMINT_DEV_API_PUBLIC_URL=http://${LanIp}:8080"; return }
        if ($_ -match '^EDGEMINT_WORKER_PUBLIC_URL=') { "EDGEMINT_WORKER_PUBLIC_URL=http://${LanIp}:8081"; return }
        $_
    }
    $lines | Set-Content '.env.docker'
    Write-Host "   .env.docker LAN URLs -> $LanIp"
}

function Test-FirewallRuleExists {
    param([string]$Name)
    netsh advfirewall firewall show rule name="$Name" 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Wait-Docker {
    $deadline = (Get-Date).AddMinutes(4)
    while ((Get-Date) -lt $deadline) {
        docker info 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Test-HttpCode {
    param([string]$Url, [int]$TimeoutSec = 5)
    curl.exe --noproxy "*" -s -o NUL -w '%{http_code}' --max-time $TimeoutSec $Url
}

function Wait-BackendHealth {
    param([int]$TimeoutSeconds = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $gw = Test-HttpCode 'http://127.0.0.1:8081/health/live'
        $api = Test-HttpCode 'http://127.0.0.1:8080/health/live'
        if ($gw -eq '200' -and $api -eq '200') { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Apply-DevHotPatches {
    $dev = Join-Path $Root 'src\backend\edgemint\dev'
    $svc = Join-Path $Root 'src\backend\edgemint\services'
    if (-not (Test-Path $dev)) { throw "Missing $dev" }

    docker cp $dev edgemint-api-gateway-1:/app/src/backend/edgemint/ 2>$null | Out-Null
    docker cp $dev edgemint-worker-registry-1:/app/src/backend/edgemint/ 2>$null | Out-Null
    docker cp $dev edgemint-model-registry-1:/app/src/backend/edgemint/ 2>$null | Out-Null
    docker cp (Join-Path $svc 'api_gateway.py') edgemint-api-gateway-1:/app/src/backend/edgemint/services/api_gateway.py 2>$null | Out-Null
    docker cp (Join-Path $svc 'worker_registry.py') edgemint-worker-registry-1:/app/src/backend/edgemint/services/worker_registry.py 2>$null | Out-Null
    docker cp (Join-Path $svc 'worker_gateway.py') edgemint-worker-gateway-1:/app/src/backend/edgemint/services/worker_gateway.py 2>$null | Out-Null
    docker cp (Join-Path $svc 'model_registry.py') edgemint-model-registry-1:/app/src/backend/edgemint/services/model_registry.py 2>$null | Out-Null
    docker restart edgemint-api-gateway-1 edgemint-worker-registry-1 edgemint-worker-gateway-1 edgemint-model-registry-1 2>$null | Out-Null
    if (-not (Wait-BackendHealth -TimeoutSeconds 120)) {
        Write-Host '   WARN: backend slow to recover after hot-patch.'
    }
}

function Ensure-FirewallRule {
    param([string]$Name, [int]$Port)
    if ($SkipFirewall) { return }
    $existing = netsh advfirewall firewall show rule name="$Name" 2>$null
    if ($LASTEXITCODE -eq 0) { return }
    netsh advfirewall firewall add rule name="$Name" dir=in action=allow protocol=TCP localport=$Port 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   firewall: opened TCP $Port ($Name)"
    } else {
        Write-Host "   WARN: could not add firewall rule for port $Port (run as Administrator)" -ForegroundColor Yellow
    }
}

function Start-PortalDev {
    $code = Test-HttpCode 'http://127.0.0.1:5173/' 2
    if ($code -eq '200') {
        Write-Host '   Portal already running on :5173'
        return
    }
    $marker = Join-Path $env:TEMP 'edgemint-portal-dev.pid'
    if (Test-Path $marker) {
        $oldPid = Get-Content $marker -ErrorAction SilentlyContinue
        if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
            Write-Host "   Portal process already running (pid $oldPid)"
            return
        }
    }
    $portalScript = Join-Path $Root 'tools\start_portal_dev.ps1'
    $proc = Start-Process powershell -PassThru -WindowStyle Minimized -ArgumentList @(
        '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', $portalScript
    )
    Set-Content -Path $marker -Value $proc.Id
    Start-Sleep -Seconds 12
    $code = Test-HttpCode 'http://127.0.0.1:5173/' 5
    if ($code -ne '200') {
        Write-Host "   WARN: portal not ready yet (HTTP $code). Check minimized PowerShell window." -ForegroundColor Yellow
    } else {
        Write-Host "   Portal started (pid $($proc.Id), minimized window)"
    }
}

function Start-MarketingSite {
    $code = Test-HttpCode 'http://127.0.0.1:5174/' 2
    if ($code -eq '200') {
        Write-Host '   Marketing site already running on :5174'
        return $null
    }
    $job = Get-Job -Name 'edgemint-marketing' -ErrorAction SilentlyContinue
    if ($job) {
        Write-Host "   Marketing job already exists (id $($job.Id))"
        return $job
    }
    $marketingJob = Start-Job -Name 'edgemint-marketing' -ScriptBlock {
        param($RootPath)
        Set-Location $RootPath
        python tools\serve_marketing_site.py --port 5174 --bind 0.0.0.0 2>&1
    } -ArgumentList $Root
    Start-Sleep -Seconds 4
    Write-Host "   Marketing site started (job $($marketingJob.Id))"
    return $marketingJob
}

Write-Host '=========================================='
Write-Host ' EdgeMint LAN dev - one-shot startup'
Write-Host '=========================================='

Write-Step '1/5 Docker'
if (-not (Wait-Docker)) {
    $dockerExe = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerExe) {
        Write-Host '   Starting Docker Desktop...'
        Start-Process $dockerExe
        if (-not (Wait-Docker)) {
            throw 'Docker is not running. Open Docker Desktop, wait until Ready, then rerun.'
        }
    } else {
        throw 'Docker Desktop not found.'
    }
}
Write-Host '   Docker OK'

$lanIp = Get-LanIp
if (-not $lanIp) { $lanIp = '127.0.0.1' }
Update-LanDockerEnv -LanIp $lanIp

Invoke-Quiet { powershell -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\setup_gradle_mirror.ps1') 2>$null | Out-Null }

Write-Step '2/5 Backend (Docker Compose)'
if (-not (Test-Path '.env.docker')) {
    if (Test-Path '.env.docker.example') {
        Copy-Item '.env.docker.example' '.env.docker'
    } else {
        throw 'Missing .env.docker'
    }
}
Invoke-Quiet { py -3.13 tools/generate_compose_backend.py 2>$null | Out-Null }
Invoke-Quiet { docker compose --env-file .env.docker -f compose.yaml -f compose.backend.yaml up -d 2>&1 | Out-Null }

if (-not (Wait-BackendHealth)) {
    throw 'Backend did not become healthy on 8080/8081'
}
Write-Host '   Backend OK (8080 + 8081)'

Write-Step '3/5 Dev hot-patch (task queue + portal API)'
$assignCode = curl.exe --noproxy "*" -s -o NUL -w '%{http_code}' --max-time 10 -H 'Authorization: Bearer dev-token' http://127.0.0.1:8081/assignments:next
if ($assignCode -eq '404') {
    Write-Host '   Applying dev hot-patches...'
    Apply-DevHotPatches
    Start-Sleep -Seconds 5
    $assignCode = curl.exe --noproxy "*" -s -o NUL -w '%{http_code}' --max-time 10 -H 'Authorization: Bearer dev-token' http://127.0.0.1:8081/assignments:next
}
Write-Host "   assignments:next = $assignCode (200/204 = OK)"

Write-Step '4/5 Firewall (LAN access from other devices)'
Ensure-FirewallRule -Name 'EdgeMint api-gateway 8080' -Port 8080
Ensure-FirewallRule -Name 'EdgeMint worker-gateway 8081' -Port 8081
Ensure-FirewallRule -Name 'EdgeMint customer-portal 5173' -Port 5173
if ($IncludeMarketing) {
    Ensure-FirewallRule -Name 'EdgeMint marketing-site 5174' -Port 5174
}

Write-Step '5/5 Frontends'
if (-not $SkipPortal) {
    Start-PortalDev | Out-Null
} else {
    Write-Host '   Skipped portal (-SkipPortal)'
}
if ($IncludeMarketing) {
    Start-MarketingSite | Out-Null
}

$lan8080 = Test-HttpCode "http://${lanIp}:8080/health/live"
$lan8081 = Test-HttpCode "http://${lanIp}:8081/health/live"
$lan5173 = if ($SkipPortal) { 'skip' } else { Test-HttpCode "http://${lanIp}:5173/" 2 }

Write-Host ''
Write-Host '=========================================='
Write-Host " LAN IP: $lanIp"
Write-Host '=========================================='
Write-Host " API (portal/tasks):     http://${lanIp}:8080   (health $lan8080)"
Write-Host " Worker gateway:         http://${lanIp}:8081   (health $lan8081)"
if (-not $SkipPortal) {
    Write-Host " Customer portal:        http://${lanIp}:5173   (HTTP $lan5173)"
}
if ($IncludeMarketing) {
    Write-Host " Marketing site:         http://${lanIp}:5174"
}
Write-Host ''
Write-Host " Remote worker app URL:  http://${lanIp}:8081"
Write-Host " Remote browser portal:  http://${lanIp}:5173  (Dev login)"
$missingFirewall = @(
    'EdgeMint api-gateway 8080',
    'EdgeMint worker-gateway 8081',
    'EdgeMint customer-portal 5173'
) | Where-Object { -not (Test-FirewallRuleExists $_) }

Write-Host ''
if ($missingFirewall.Count -gt 0) {
    Write-Host ' FIREWALL: ports blocked for remote PCs. Run as Administrator:' -ForegroundColor Yellow
    Write-Host '   powershell -ExecutionPolicy Bypass -File tools\open_lan_firewall.ps1' -ForegroundColor Yellow
}
Write-Host ''
Write-Host ' Remote portal: Dev login required before bottom menu appears.'
Write-Host ''
Write-Host ' Re-run anytime:'
Write-Host '   powershell -ExecutionPolicy Bypass -File tools\start_lan_dev.ps1'
Write-Host '=========================================='
