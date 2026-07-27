# EdgeMint Flutter mirror configuration for environments where pub.dev is blocked.
# Usage: . .\tools\flutter_env.ps1

$flutterBin = if ($env:FLUTTER_ROOT) { Join-Path $env:FLUTTER_ROOT "bin" } else { "C:\Users\Admin\flutter\bin" }
if (Test-Path $flutterBin) {
    $parts = @($flutterBin) + ($env:Path -split ';' | Where-Object { $_ -and ($_ -ne $flutterBin) })
    $env:Path = $parts -join ';'
}

$env:PUB_HOSTED_URL = "https://pub.myket.ir"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"

Write-Host "Flutter env: PUB_HOSTED_URL=$env:PUB_HOSTED_URL"
Write-Host "Flutter bin: $flutterBin"
