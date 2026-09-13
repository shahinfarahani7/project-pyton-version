# EdgeMint Flutter/pub mirror configuration for restricted networks.
# Usage (from repo root or worker app):
#   . .\tools\flutter_env.ps1
#   flutter pub get

$flutterBin = if ($env:FLUTTER_ROOT) { Join-Path $env:FLUTTER_ROOT "bin" } else { "C:\Users\Admin\flutter\bin" }
if (Test-Path $flutterBin) {
    $parts = @($flutterBin) + ($env:Path -split ';' | Where-Object { $_ -and ($_ -ne $flutterBin) })
    $env:Path = $parts -join ';'
}

function Resolve-GitProxy {
    param([string]$Key)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $value = (git config --get $Key 2>$null)
        if ($value) { return $value.Trim() }
    } finally {
        $ErrorActionPreference = $prev
    }
    return $null
}

function Ensure-ProxyEnv {
    if ($env:HTTP_PROXY -or $env:HTTPS_PROXY) { return }

    $proxy = Resolve-GitProxy 'https.proxy'
    if (-not $proxy) { $proxy = Resolve-GitProxy 'http.proxy' }
    if ($proxy) {
        $env:HTTP_PROXY = $proxy
        $env:HTTPS_PROXY = $proxy
        Write-Host "Flutter env: using proxy from git config ($proxy)"
    }
}

Ensure-ProxyEnv

if ($env:EDGEMINT_PRESERVE_PUB_URL -eq '1' -and $env:PUB_HOSTED_URL -and $env:FLUTTER_STORAGE_BASE_URL) {
    Write-Host "Flutter env: PUB_HOSTED_URL=$env:PUB_HOSTED_URL (preserved)"
    Write-Host "Flutter env: FLUTTER_STORAGE_BASE_URL=$env:FLUTTER_STORAGE_BASE_URL (preserved)"
} elseif ($env:HTTP_PROXY -or $env:HTTPS_PROXY) {
    # pub.dev needs proxy on this network; do not call flutter without sourcing this script first.
    $env:PUB_HOSTED_URL = "https://pub.dev"
    $env:FLUTTER_STORAGE_BASE_URL = "https://storage.googleapis.com"
    Write-Host "Flutter env: PUB_HOSTED_URL=$env:PUB_HOSTED_URL (via proxy)"
    Write-Host "Flutter env: FLUTTER_STORAGE_BASE_URL=$env:FLUTTER_STORAGE_BASE_URL"
} elseif (-not $env:PUB_HOSTED_URL -or -not $env:FLUTTER_STORAGE_BASE_URL) {
    $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
    $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
    Write-Host "Flutter env: PUB_HOSTED_URL=$env:PUB_HOSTED_URL (no proxy detected)"
    Write-Host "Flutter env: FLUTTER_STORAGE_BASE_URL=$env:FLUTTER_STORAGE_BASE_URL"
} else {
    Write-Host "Flutter env: PUB_HOSTED_URL=$env:PUB_HOSTED_URL (custom, no proxy)"
    Write-Host "Flutter env: FLUTTER_STORAGE_BASE_URL=$env:FLUTTER_STORAGE_BASE_URL"
}

$gradleHome = Join-Path $env:LOCALAPPDATA 'EdgeMint\gradle-home'
if (Test-Path (Join-Path $gradleHome 'init.d\edgemint-mirror.init.gradle')) {
    $env:GRADLE_USER_HOME = $gradleHome
    Write-Host "Flutter env: GRADLE_USER_HOME=$gradleHome"
} else {
    Write-Host "Flutter env: run tools\setup_gradle_mirror.ps1 once if Gradle cannot resolve Android deps"
}

Write-Host "Flutter bin: $flutterBin"
