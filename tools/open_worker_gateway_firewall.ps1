# Opens Windows Firewall for worker-gateway (port 8081) so phones on the LAN can reach the backend.
# Run in PowerShell as Administrator:
#   powershell -ExecutionPolicy Bypass -File tools\open_worker_gateway_firewall.ps1

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'open_lan_firewall.ps1')
