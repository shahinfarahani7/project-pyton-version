# Opens Windows Firewall for EdgeMint LAN dev ports.
# Run PowerShell as Administrator:
#   powershell -ExecutionPolicy Bypass -File tools\open_lan_firewall.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent

$rules = @(
    @{ Name = 'EdgeMint api-gateway 8080'; Port = 8080 },
    @{ Name = 'EdgeMint worker-gateway 8081'; Port = 8081 },
    @{ Name = 'EdgeMint customer-portal 5173'; Port = 5173 },
    @{ Name = 'EdgeMint marketing-site 5174'; Port = 5174 }
)

foreach ($rule in $rules) {
    $existing = netsh advfirewall firewall show rule name="$($rule.Name)" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK (exists): $($rule.Name)"
        continue
    }
    netsh advfirewall firewall add rule name="$($rule.Name)" dir=in action=allow protocol=TCP localport=$($rule.Port)
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Added: $($rule.Name) TCP $($rule.Port)"
    } else {
        Write-Host "FAILED: $($rule.Name) — run as Administrator" -ForegroundColor Red
    }
}

$lanIp = (
    Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -notlike '127.*' -and
        $_.PrefixOrigin -ne 'WellKnown' -and
        $_.InterfaceAlias -notlike '*WSL*' -and
        $_.InterfaceAlias -notlike '*Default Switch*' -and
        $_.InterfaceAlias -notlike '*vEthernet*'
    } |
    Select-Object -First 1 -ExpandProperty IPAddress
)

Write-Host ''
Write-Host "Test from another PC on the same LAN (IP: $lanIp):"
Write-Host "  curl http://${lanIp}:8080/health/live"
Write-Host "  curl http://${lanIp}:8081/health/live"
Write-Host "  curl http://${lanIp}:5173/"
