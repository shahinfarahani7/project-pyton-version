# Opens Windows Firewall for the Vite customer portal (port 5173) on the LAN.
# Run in PowerShell as Administrator:
#   powershell -ExecutionPolicy Bypass -File tools\open_portal_firewall.ps1

$ErrorActionPreference = 'Stop'
$ruleName = 'EdgeMint customer portal 5173'

$existing = netsh advfirewall firewall show rule name="$ruleName" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Firewall rule already exists: $ruleName"
} else {
    netsh advfirewall firewall add rule name="$ruleName" dir=in action=allow protocol=TCP localport=5173 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Added firewall rule: $ruleName"
    } else {
        Write-Host "WARN: Could not add firewall rule (run this script as Administrator)." -ForegroundColor Yellow
    }
}

$lanIp = (
    Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -notlike '127.*' -and
        $_.PrefixOrigin -ne 'WellKnown' -and
        $_.InterfaceAlias -notlike '*WSL*' -and
        $_.InterfaceAlias -notlike '*Default Switch*'
    } |
    Select-Object -First 1 -ExpandProperty IPAddress
)

Write-Host ''
Write-Host 'Portal URLs:'
Write-Host "  This PC:     http://127.0.0.1:5173"
if ($lanIp) {
    Write-Host "  Other PCs:   http://${lanIp}:5173"
}
Write-Host ''
Write-Host 'From another machine on the same LAN, open the "Other PCs" URL in a browser.'
