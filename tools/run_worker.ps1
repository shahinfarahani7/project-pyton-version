# Run EdgeMint worker app with pub/Gradle mirrors and proxy applied.
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\run_worker.ps1
#   powershell -ExecutionPolicy Bypass -File tools\run_worker.ps1 -ModelAsset assets/models/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task
param(
    [string]$WorkerBaseUrl = 'http://172.20.34.71:8081',
    [string]$ModelAsset = '',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$WorkerDir = Join-Path $Root 'src\apps\worker'

. (Join-Path $Root 'tools\flutter_env.ps1')
Set-Location $WorkerDir

flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed with exit code $LASTEXITCODE" }

$dartDefines = @("--dart-define=EDGEMINT_WORKER_BASE_URL=$WorkerBaseUrl")
if ($ModelAsset) {
    $dartDefines += "--dart-define=WORKER_MODEL_ASSET=$ModelAsset"
}

flutter run @dartDefines @FlutterArgs
