# Starts the local EdgeMint Docker stack (infra + 21 backend services).
param(
    [switch]$Portals,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ComposeArgs
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$envFile = if ($env:ENV_FILE) { $env:ENV_FILE } else { ".env.docker" }
if (-not (Test-Path $envFile)) {
    if (Test-Path ".env.docker.example") {
        Copy-Item ".env.docker.example" $envFile
        Write-Host "Created $envFile from .env.docker.example"
    } else {
        throw "Missing $envFile and .env.docker.example"
    }
}

py -3.13 tools/generate_compose_backend.py

$compose = @(
    "docker", "compose",
    "--env-file", $envFile,
    "-f", "compose.yaml",
    "-f", "compose.backend.yaml"
)
if ($Portals) {
    $compose += "-f", "compose.portals.yaml"
}
if ($ComposeArgs.Count -eq 0) {
    $ComposeArgs = @('up', '-d', '--build')
}
$allArgs = $compose + $ComposeArgs
Write-Host ('Running: ' + ($allArgs -join ' '))
& $allArgs[0] $allArgs[1..($allArgs.Length - 1)]
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
