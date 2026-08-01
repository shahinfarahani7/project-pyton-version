# Opens Windows Firewall for worker-gateway (port 8081) so phones on the LAN can reach the backend.
# Run in PowerShell as Administrator:
#   powershell -ExecutionPolicy Bypass -File tools\open_worker_gateway_firewall.ps1

$ErrorActionPreference = 'Stop'
$ruleName = 'EdgeMint worker-gateway 8081'

$existing = netsh advfirewall firewall show rule name="$ruleName" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Firewall rule already exists: $ruleName"
} else {
    netsh advfirewall firewall add rule name="$ruleName" dir=in action=allow protocol=TCP localport=8081
    Write-Host "Added firewall rule: $ruleName"
}

Write-Host ''
Write-Host 'Test from this PC:'
Write-Host '  curl http://172.20.34.71:8081/health/live'
Write-Host ''
Write-Host 'Test from phone browser (same Wi-Fi/LAN):'
Write-Host '  http://172.20.34.71:8081/health/live'
Write-Host 'Expected: HTTP 200 or a small JSON health response.'
