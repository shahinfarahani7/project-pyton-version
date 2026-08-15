# Deprecated wrapper — use start_worker_dev.ps1
$Root = Split-Path $PSScriptRoot -Parent
& (Join-Path $Root 'tools\start_worker_dev.ps1') -SkipPortal @args
