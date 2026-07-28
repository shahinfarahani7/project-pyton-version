# Apply development mock data to a local PostgreSQL instance.
param(
    [string]$HostName = "localhost",
    [string]$User = "edgemint",
    [string]$Database = "edgemint",
    [string]$Password = $env:POSTGRES_PASSWORD
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

if (-not $Password) {
    if (Test-Path ".env.docker") {
        Get-Content ".env.docker" | ForEach-Object {
            if ($_ -match '^\s*POSTGRES_PASSWORD=(.+)$') {
                $script:Password = $Matches[1].Trim('"')
            }
        }
    }
}

if (-not $Password) {
    throw "Set POSTGRES_PASSWORD or create .env.docker with POSTGRES_PASSWORD"
}

$seedFile = Join-Path $PWD "database\seed\dev_mock_data.sql"
if (-not (Test-Path $seedFile)) {
    throw "Missing seed file: $seedFile"
}

$env:PGPASSWORD = $Password
docker compose --env-file .env.docker exec -T postgresql `
    psql -X -v ON_ERROR_STOP=1 -U $User -d $Database `
    -f - < $seedFile

Write-Host "DEV_SEED_APPLIED"
