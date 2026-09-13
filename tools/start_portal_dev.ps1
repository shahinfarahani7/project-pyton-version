# Customer portal Vite dev server (LAN accessible on :5173).
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location (Join-Path $Root 'src\apps\customer-portal')
$env:VITE_DEV_API_PROXY = 'http://127.0.0.1:8080'
Write-Host 'EdgeMint customer portal: http://0.0.0.0:5173'
npm run dev
