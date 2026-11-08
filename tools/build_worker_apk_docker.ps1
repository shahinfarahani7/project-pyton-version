# Builds the worker APK inside a Linux container.
# The proxy is taken from the host Git configuration and stored only in the
# Windows and Docker client settings. It is not written into the image.
param(
    [string]$OutputDir = 'dist/android-worker',
    [string]$WorkerBaseUrl = 'http://172.20.34.71:8081'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent

function Get-HostProxyUrl {
    $configured = git config --get http.proxy
    if (-not $configured) {
        $configured = git config --get https.proxy
    }
    if (-not $configured) {
        throw 'Set the proxy on this machine first, for example: git config --global https.proxy http://proxy-host:3128'
    }
    if ($configured -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        $configured = "http://$configured"
    }
    $uri = [Uri]$configured
    if ($uri.Scheme -eq 'https') {
        # This proxy accepts HTTP CONNECT. An https scheme makes clients
        # open TLS directly to the proxy and the handshake fails.
        $builder = New-Object System.UriBuilder $uri
        $builder.Scheme = 'http'
        $configured = $builder.Uri.GetComponents(
            [System.UriComponents]::SchemeAndServer,
            [System.UriFormat]::SafeUnescaped
        )
    }
    return $configured.Trim()
}

function Set-UserProxyEnvironment([string]$ProxyUrl) {
    foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy')) {
        [Environment]::SetEnvironmentVariable($name, $ProxyUrl, 'User')
        Set-Item -Path "Env:$name" -Value $ProxyUrl
    }
    $bypass = 'localhost,127.0.0.1'
    foreach ($name in @('NO_PROXY', 'no_proxy')) {
        [Environment]::SetEnvironmentVariable($name, $bypass, 'User')
        Set-Item -Path "Env:$name" -Value $bypass
    }
}

function Set-WindowsProxy([string]$ProxyUrl) {
    $uri = [Uri]$ProxyUrl
    $server = if ($uri.Port -gt 0) { "$($uri.Host):$($uri.Port)" } else { $uri.Host }
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    Set-ItemProperty -Path $key -Name ProxyEnable -Value 1
    Set-ItemProperty -Path $key -Name ProxyServer -Value $server
    Set-ItemProperty -Path $key -Name ProxyOverride -Value 'localhost;127.0.0.1;<local>'
}

function Set-DockerClientProxy([string]$ProxyUrl) {
    $configPath = Join-Path $env:USERPROFILE '.docker\config.json'
    $config = [ordered]@{}
    if (Test-Path $configPath) {
        $existing = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        foreach ($property in $existing.PSObject.Properties) {
            $config[$property.Name] = $property.Value
        }
    }
    $config['proxies'] = [pscustomobject]@{
        default = [pscustomobject]@{
            httpProxy = $ProxyUrl
            httpsProxy = $ProxyUrl
            noProxy = 'localhost,127.0.0.1,host.docker.internal'
        }
    }
    $json = $config | ConvertTo-Json -Depth 8
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($configPath, $json + [Environment]::NewLine, $utf8)
}

function Set-DockerDesktopProxy([string]$ProxyUrl) {
    $settingsPath = Join-Path $env:APPDATA 'Docker\settings-store.json'
    if (-not (Test-Path $settingsPath)) {
        return
    }
    $settings = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
    foreach ($entry in @(
            @{ Name = 'ProxyHTTPMode'; Value = 'manual' },
            @{ Name = 'OverrideProxyHTTP'; Value = $ProxyUrl },
            @{ Name = 'OverrideProxyHTTPS'; Value = $ProxyUrl },
            @{ Name = 'OverrideProxyExclude'; Value = 'localhost,127.0.0.1,host.docker.internal' }
        )) {
        $settings | Add-Member -MemberType NoteProperty -Name $entry.Name -Value $entry.Value -Force
    }
    $json = $settings | ConvertTo-Json -Depth 8
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($settingsPath, $json + [Environment]::NewLine, $utf8)
}

function Ensure-HostProxyForwarder([string]$ProxyUrl) {
    $uri = [Uri]$ProxyUrl
    $listenPort = 3128
    $existing = netsh interface portproxy show v4tov4
    $already = $existing | Select-String -Pattern "3128\s+$($uri.Host)\s+$($uri.Port)"
    if ($already) {
        return
    }
    $arguments = @(
        'interface', 'portproxy', 'add', 'v4tov4',
        'listenaddress=0.0.0.0', "listenport=$listenPort",
        "connectaddress=$($uri.Host)", "connectport=$($uri.Port)"
    )
    Start-Process -FilePath netsh -ArgumentList $arguments -Verb RunAs -Wait
}

$proxyUrl = Get-HostProxyUrl
Set-WindowsProxy $proxyUrl
Ensure-HostProxyForwarder $proxyUrl
$wslHost = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.InterfaceAlias -match 'vEthernet \(WSL' } |
    Select-Object -First 1 -ExpandProperty IPAddress
if (-not $wslHost) {
    throw 'Docker could not find the WSL host address to reach the machine proxy.'
}
$containerProxy = "http://${wslHost}:3128"
Set-DockerClientProxy $containerProxy
Set-DockerDesktopProxy $containerProxy
Write-Host "Host proxy stays on this machine. Docker reaches it through the host forwarder."

$keystore = Join-Path $env:USERPROFILE '.android\debug.keystore'
if (-not (Test-Path $keystore)) {
    throw "Debug keystore not found: $keystore"
}

$destination = Join-Path $Root $OutputDir
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$exportDir = Join-Path $env:TEMP ("edgemint-worker-apk-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $exportDir | Out-Null

try {
    docker buildx build `
        -f (Join-Path $Root 'src\apps\worker\docker\Dockerfile') `
        --secret "id=android_debug_keystore,src=$keystore" `
        --build-arg "EDGEMINT_WORKER_BASE_URL=$WorkerBaseUrl" `
        --target export `
        --output "type=local,dest=$exportDir" `
        (Join-Path $Root 'src\apps\worker')
    if ($LASTEXITCODE -ne 0) {
        throw "docker buildx build failed with exit code $LASTEXITCODE"
    }
    $built = Join-Path $exportDir 'app-release.apk'
    if (-not (Test-Path $built)) {
        throw "Container build finished without $built"
    }
    $destApk = Join-Path $destination 'app-release.apk'
    Copy-Item -Force $built $destApk
    Write-Host "APK_READY: $destApk"
} finally {
    if (Test-Path $exportDir) {
        Remove-Item -Recurse -Force $exportDir
    }
}
