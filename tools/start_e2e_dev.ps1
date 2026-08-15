# Local E2E: customer portal + backend + Android emulator worker app.
param(
    [switch]$SkipFlutter,
    [string]$WorkerBaseUrl = 'http://10.0.2.2:8081',
    [string]$PortalDevApi = 'http://127.0.0.1:8080'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

function Invoke-External {
    param([scriptblock]$Command)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # Native tools (docker) write progress to stderr; do not treat that as terminating.
        & $Command 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "command failed with exit code $LASTEXITCODE"
        }
    } finally {
        $ErrorActionPreference = $prev
    }
}

Write-Host '== EdgeMint local E2E stack =='

# Infra + backend (reuse existing images; rebuild worker-registry when network allows)
Invoke-External { docker compose --env-file .env.docker -f compose.yaml -f compose.backend.yaml up -d postgresql minio mailpit }
Start-Sleep -Seconds 3
Invoke-External { docker compose --env-file .env.docker -f compose.yaml up postgresql-init postgresql-seed }
Invoke-External { docker compose --env-file .env.docker -f compose.yaml -f compose.backend.yaml up -d }

Write-Host 'Hot-patching dev APIs (assignments + model artifact proxy)...'
Invoke-External { docker cp "src/backend/edgemint/dev/worker_assignments.py" edgemint-worker-registry-1:/app/src/backend/edgemint/dev/worker_assignments.py }
Invoke-External { docker cp "src/backend/edgemint/dev/fixtures.py" edgemint-worker-registry-1:/app/src/backend/edgemint/dev/fixtures.py }
Invoke-External { docker cp "src/backend/edgemint/dev/fixtures.py" edgemint-api-gateway-1:/app/src/backend/edgemint/dev/fixtures.py }
Invoke-External { docker cp "src/backend/edgemint/dev/worker_assignments.py" edgemint-api-gateway-1:/app/src/backend/edgemint/dev/worker_assignments.py }
Invoke-External { docker cp "src/backend/edgemint/dev/model_artifact_proxy.py" edgemint-model-registry-1:/app/src/backend/edgemint/dev/model_artifact_proxy.py }
Invoke-External { docker cp "src/backend/edgemint/services/worker_registry.py" edgemint-worker-registry-1:/app/src/backend/edgemint/services/worker_registry.py }
Invoke-External { docker cp "src/backend/edgemint/services/model_registry.py" edgemint-model-registry-1:/app/src/backend/edgemint/services/model_registry.py }
Invoke-External { docker cp "src/backend/edgemint/services/worker_gateway.py" edgemint-worker-gateway-1:/app/src/backend/edgemint/services/worker_gateway.py }
Invoke-External { docker restart edgemint-worker-registry-1 edgemint-worker-gateway-1 edgemint-api-gateway-1 edgemint-model-registry-1 }
Start-Sleep -Seconds 8

Write-Host 'Rebuilding worker-registry (dev assignment API)...'
$buildOk = $true
try {
    Invoke-External { docker compose --env-file .env.docker -f compose.yaml -f compose.backend.yaml build worker-registry worker-gateway }
} catch {
    $buildOk = $false
}
if (-not $buildOk) {
    Write-Host 'Docker build unavailable — hot-patching running containers...'
    Invoke-External { docker cp "src/backend/edgemint/dev/worker_assignments.py" edgemint-worker-registry-1:/app/src/backend/edgemint/dev/worker_assignments.py }
    Invoke-External { docker cp "src/backend/edgemint/dev/fixtures.py" edgemint-worker-registry-1:/app/src/backend/edgemint/dev/fixtures.py }
    Invoke-External { docker cp "src/backend/edgemint/dev/fixtures.py" edgemint-api-gateway-1:/app/src/backend/edgemint/dev/fixtures.py }
    Invoke-External { docker cp "src/backend/edgemint/dev/worker_assignments.py" edgemint-api-gateway-1:/app/src/backend/edgemint/dev/worker_assignments.py }
    Invoke-External { docker cp "src/backend/edgemint/dev/model_artifact_proxy.py" edgemint-model-registry-1:/app/src/backend/edgemint/dev/model_artifact_proxy.py }
    Invoke-External { docker cp "src/backend/edgemint/services/worker_registry.py" edgemint-worker-registry-1:/app/src/backend/edgemint/services/worker_registry.py }
    Invoke-External { docker cp "src/backend/edgemint/services/model_registry.py" edgemint-model-registry-1:/app/src/backend/edgemint/services/model_registry.py }
    Invoke-External { docker cp "src/backend/edgemint/services/worker_gateway.py" edgemint-worker-gateway-1:/app/src/backend/edgemint/services/worker_gateway.py }
    Invoke-External { docker restart edgemint-worker-registry-1 edgemint-worker-gateway-1 edgemint-api-gateway-1 edgemint-model-registry-1 }
    Start-Sleep -Seconds 8
}
Invoke-External { docker compose --env-file .env.docker -f compose.yaml -f compose.backend.yaml up -d worker-registry worker-gateway }

$health8080 = curl.exe -s -o NUL -w '%{http_code}' http://127.0.0.1:8080/health/live
$health8081 = curl.exe -s -o NUL -w '%{http_code}' http://127.0.0.1:8081/health/live
Write-Host "api-gateway health: $health8080"
Write-Host "worker-gateway health: $health8081"

$assignCode = curl.exe -s -o NUL -w '%{http_code}' -H 'Authorization: Bearer dev-token' http://127.0.0.1:8081/assignments:next
Write-Host "worker assignments:next probe: $assignCode (200=queued task, 204=empty queue)"
Write-Host 'Set HUGGINGFACE_TOKEN in .env.docker for server-side Gemma downloads (mobile app does not need it).'

Write-Host 'Starting customer portal (Vite dev)...'
$portalJob = Start-Job -ScriptBlock {
    param($Root, $PortalDevApi)
    Set-Location (Join-Path $Root 'src\apps\customer-portal')
    $env:VITE_DEV_API_PROXY = $PortalDevApi
    npm run dev -- --host 0.0.0.0 --port 5173 2>&1
} -ArgumentList $Root, $PortalDevApi

Start-Sleep -Seconds 5
Write-Host ''
Write-Host 'Customer portal: http://localhost:5173'
Write-Host '  Dev login: open /login and use Dev workspace buttons'
Write-Host '  Create task: Tasks -> New Task'
Write-Host ''
Write-Host "Mobile worker URL (emulator): $WorkerBaseUrl"
Write-Host '  Android emulator host loopback = 10.0.2.2'
Write-Host ''

if (-not $SkipFlutter) {
    . (Join-Path $Root 'tools\flutter_env.ps1')
    $adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if (Test-Path $adb) {
        $device = (& $adb devices | Select-String 'device$' | Select-Object -First 1).ToString().Split()[0]
        if ($device) {
            & $adb -s $device reverse tcp:8080 tcp:8080
            & $adb -s $device reverse tcp:8081 tcp:8081
            Write-Host "adb reverse tcp:8080/tcp:8081 -> device $device"
            $WorkerBaseUrl = 'http://127.0.0.1:8081'
        }
        & $adb devices
    }
    Set-Location (Join-Path $Root 'src\apps\worker')
    flutter run --dart-define=EDGEMINT_WORKER_BASE_URL=$WorkerBaseUrl -d $device
}

Write-Host "Portal dev server job id: $($portalJob.Id) (Stop-Job / Remove-Job to stop)"
