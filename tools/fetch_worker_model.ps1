# Downloads the dev-bundled Qwen LiteRT artifact into the worker assets folder.
param(
    [string]$OutputDir = "$PSScriptRoot\..\src\apps\worker\assets\models",
    [string]$FileName = "Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task",
    [string]$Url = "https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$dest = Join-Path $OutputDir $FileName
if (Test-Path $dest) {
    Write-Host "Model already present: $dest"
    exit 0
}
Write-Host "Downloading Qwen dev model to $dest ..."
Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing
Write-Host "Done. Size bytes:" (Get-Item $dest).Length
