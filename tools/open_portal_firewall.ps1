# Opens Windows Firewall for the Vite customer portal (port 5173) on the LAN.
# Run in PowerShell as Administrator:
#   powershell -ExecutionPolicy Bypass -File tools\open_portal_firewall.ps1

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'open_lan_firewall.ps1')
