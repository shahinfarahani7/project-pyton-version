# Verify portal task status and/or run a full dev E2E loop (portal -> worker-gateway -> portal).
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File tools\verify_worker_e2e.ps1 -VerifyTaskId tsk_dev_01b29532
#   powershell -ExecutionPolicy Bypass -File tools\verify_worker_e2e.ps1 -RunLoop
#   powershell -ExecutionPolicy Bypass -File tools\verify_worker_e2e.ps1 -RunLoop -WaitForWorker -WaitSeconds 120
#
param(
    [string]$VerifyTaskId = '',
    [switch]$RunLoop,
    [switch]$WaitForWorker,
    [string]$TaskType = 'document.ocr',
    [int]$WaitSeconds = 90,
    [string]$ApiGateway = 'http://127.0.0.1:8080',
    [string]$WorkerGateway = 'http://127.0.0.1:8081',
    [string]$WorkspaceId = '00000000-0000-0000-0000-00000000000b',
    [string]$PrincipalId = '00000000-0000-0000-0000-00000000000a'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$TempDir = Join-Path $Root '.tmp_e2e'
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
$CookieJar = Join-Path $TempDir 'cookies.txt'
$BodyFile = Join-Path $TempDir 'body.json'
$ResponseFile = Join-Path $TempDir 'response.json'

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host ">> $Message" -ForegroundColor Cyan
}

function Invoke-CurlJson {
    param(
        [string]$Method = 'GET',
        [string]$Url,
        [hashtable]$Headers = @{},
        [object]$Body = $null,
        [switch]$UseCookies,
        [switch]$SaveCookies,
        [switch]$Allow204
    )
    $args = @('-s', '-S', '-w', "`n%{http_code}", '-X', $Method, $Url)
    if ($SaveCookies) { $args += @('-c', $CookieJar) }
    if ($UseCookies) { $args += @('-b', $CookieJar) }
    foreach ($key in $Headers.Keys) {
        $args += @('-H', "${key}: $($Headers[$key])")
    }
    if ($null -ne $Body) {
        ($Body | ConvertTo-Json -Compress -Depth 8) | Set-Content -Path $BodyFile -Encoding ascii
        $args += @('-H', 'Content-Type: application/json', '--data-binary', "@$BodyFile")
    }
    $raw = & curl.exe @args
    if ($LASTEXITCODE -ne 0) {
        throw "curl failed for $Method $Url"
    }
    $lines = $raw -split "`n"
    $status = [int]$lines[-1]
    $payload = ($lines[0..($lines.Length - 2)] -join "`n").Trim()
    if ($status -eq 204 -and $Allow204) {
        return @{ Status = $status; Json = $null; Raw = '' }
    }
    if ($status -lt 200 -or $status -ge 300) {
        throw "HTTP $status for $Method $Url`n$payload"
    }
    if ([string]::IsNullOrWhiteSpace($payload)) {
        return @{ Status = $status; Json = $null; Raw = '' }
    }
    return @{ Status = $status; Json = ($payload | ConvertFrom-Json); Raw = $payload }
}

function Connect-PortalSession {
    Write-Step 'Portal login (dev session)'
    $login = Invoke-CurlJson -Method POST -Url "$ApiGateway/auth/sessions" -SaveCookies -Body @{
        principalId = $PrincipalId
        workspaceId = $WorkspaceId
        permissions = @('customer.tasks:read', 'customer.tasks:write')
    }
    Write-Host "   session $($login.Json.sessionPublicId)"
}

function Get-PortalTask([string]$TaskId) {
    $tasks = Invoke-CurlJson -UseCookies -Url "$ApiGateway/v1/workspaces/$WorkspaceId/tasks"
    return ($tasks.Json.items | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1)
}

function Show-Task([object]$Task, [string]$Label) {
    if (-not $Task) {
        Write-Host "   $Label not found" -ForegroundColor Yellow
        return $false
    }
    Write-Host "   $Label"
    Write-Host "     id:              $($Task.id)"
    Write-Host "     taskType:        $($Task.taskType)"
    Write-Host "     executionStatus: $($Task.executionStatus)"
    Write-Host "     lifecycleStatus: $($Task.lifecycleStatus)"
    $preview = if ($Task.resultPreview) { $Task.resultPreview } else { '(none)' }
    Write-Host "     resultPreview:   $preview"
    return $true
}

function Test-TaskCompleted([object]$Task, [string]$ExpectSnippet = 'INVOICE') {
    if (-not $Task) { return $false }
    $ok = ($Task.executionStatus -eq 'completed') -and ($Task.lifecycleStatus -eq 'succeeded')
    if ($ExpectSnippet -and $Task.resultPreview) {
        $ok = $ok -and ($Task.resultPreview -like "*$ExpectSnippet*")
    }
    return $ok
}

function New-PortalTask {
    Write-Step "Create portal task ($TaskType)"
    $created = Invoke-CurlJson -Method POST -UseCookies -Url "$ApiGateway/v1/workspaces/$WorkspaceId/tasks" -Body @{
        taskType = $TaskType
    }
    $taskId = $created.Json.id
    Write-Host "   created $taskId (assignmentId=$($created.Json.assignmentId))"
    return $taskId
}

function Invoke-WorkerHttpSimulation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetTaskId
    )
    Write-Step 'Simulate worker HTTP flow (assignments -> input -> complete -> output)'
    $token = 'dev-e2e-token'
    Invoke-CurlJson -Method POST -Url "$ApiGateway/internal/dev/sync-worker-queue" | Out-Null

    $processed = @()
    $attempts = 0
    while ($attempts -lt 20) {
        $attempts += 1
        $next = Invoke-CurlJson -Url "$WorkerGateway/assignments:next" -Headers @{
            Authorization = "Bearer $token"
            'Idempotency-Key' = "poll-$attempts-$TargetTaskId"
        } -Allow204
        if ($next.Status -eq 204 -or -not $next.Json) {
            if ($processed -contains $TargetTaskId) { break }
            throw "No assignment available for $TargetTaskId (processed: $($processed -join ', '))"
        }

        $assignment = $next.Json
        $taskId = [string]$assignment.taskId
        $assignmentId = [string]$assignment.assignmentId
        Write-Host "   polled $taskId ($($assignment.taskType))"

        $manifest = Invoke-CurlJson -Url "$ApiGateway/v1/dev/worker/tasks/$taskId/input"
        Write-Host "   input manifest: $($manifest.Json.documentTitle)"

        $idem = $assignment.attemptId
        foreach ($suffix in @('started', 'progress', 'checkpoint', 'complete')) {
            $route = "$WorkerGateway/assignments/${assignmentId}:$suffix"
            Invoke-CurlJson -Method POST -Url $route -Headers @{
                Authorization = "Bearer $token"
                'Idempotency-Key' = "$suffix-$idem"
            } -Body @{
                leaseToken = $assignment.leaseToken
                fenceToken = $assignment.fenceToken
                sequence = 1000
                stage = 'infer'
                progressBps = 10000
                resultSha256 = 'deadbeef'
                outputArtifactId = "art_$idem"
                metrics = @{ backend = 'e2e-script' }
                signature = 'e2e-signature'
            } | Out-Null
        }

        $mockResult = @"
Processed $taskId ($($assignment.taskType)) via verify_worker_e2e.ps1
INVOICE #INV-2026-0847
EdgeMint Demo Supplies Ltd.
TOTAL: 99.16 EUR
Reference: PO-EM-2026-441
"@.Trim()

        Invoke-CurlJson -Method POST -Url "$ApiGateway/v1/dev/worker/tasks/$taskId/output" -Body @{
            resultText = $mockResult
            metrics = @{
                taskType = $assignment.taskType
                taskId = $taskId
                source = 'verify_worker_e2e.ps1'
            }
        } | Out-Null
        $processed += $taskId
        Write-Host "   completed $taskId"
        if ($taskId -eq $TargetTaskId) {
            break
        }
    }

    if ($processed -notcontains $TargetTaskId) {
        throw "Target task $TargetTaskId was not processed (got: $($processed -join ', '))"
    }
    Write-Host '   worker simulation finished'
    return $TargetTaskId
}

function Wait-ForPortalCompletion([string]$TaskId) {
    Write-Step "Waiting up to ${WaitSeconds}s for worker app to complete $TaskId"
    Write-Host '   On MEmu: open worker app -> Poll & run next task'
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        $task = Get-PortalTask -TaskId $TaskId
        if ($task -and $task.executionStatus -eq 'completed') {
            return $task
        }
        Write-Host "   ... still $($task.executionStatus)"
    }
    return Get-PortalTask -TaskId $TaskId
}

if (-not $VerifyTaskId -and -not $RunLoop) {
    $VerifyTaskId = 'tsk_dev_01b29532'
}

Write-Host '== EdgeMint worker E2E verify =='
Write-Host "api-gateway:    $ApiGateway"
Write-Host "worker-gateway: $WorkerGateway"

Connect-PortalSession

if ($VerifyTaskId) {
    Write-Step "Verify portal task $VerifyTaskId"
    $task = Get-PortalTask -TaskId $VerifyTaskId
    Show-Task -Task $task -Label 'portal task' | Out-Null
    if (Test-TaskCompleted -Task $task) {
        Write-Host ''
        Write-Host 'PASS: portal shows completed with result preview' -ForegroundColor Green
    }
    else {
        Write-Host ''
        Write-Host 'WARN: task not completed yet (or missing result preview)' -ForegroundColor Yellow
    }
}

if ($RunLoop) {
    $newTaskId = New-PortalTask
    if ($WaitForWorker) {
        Invoke-CurlJson -Method POST -Url "$ApiGateway/internal/dev/sync-worker-queue" | Out-Null
        $final = Wait-ForPortalCompletion -TaskId $newTaskId
    }
    else {
        $finishedId = Invoke-WorkerHttpSimulation -TargetTaskId $newTaskId
        $final = Get-PortalTask -TaskId $finishedId
    }

    Write-Step 'Verify new task in portal'
    Show-Task -Task $final -Label 'new task' | Out-Null
    if (Test-TaskCompleted -Task $final) {
        Write-Host ''
        Write-Host "PASS: E2E loop completed for $($final.id)" -ForegroundColor Green
        exit 0
    }
    Write-Host ''
    Write-Host 'FAIL: new task did not reach completed/succeeded' -ForegroundColor Red
    exit 1
}
