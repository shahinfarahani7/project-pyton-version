# Download PP-OCRv5 Arabic/Persian ONNX artifacts to dist/models/paddleocr/ (GreatV oar-ocr release).
param(
    [string]$ModelDir = 'dist/models/paddleocr',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$releaseBase = 'https://github.com/GreatV/oar-ocr/releases/download/v0.3.0'
$artifacts = @(
    @{
        UrlName  = 'pp-ocrv5_mobile_det.onnx'
        FileName = 'ppocrv5_mobile_det.onnx'
        MinBytes = 4MB
    },
    @{
        UrlName  = 'arabic_pp-ocrv5_mobile_rec.onnx'
        FileName = 'ppocrv5_mobile_rec_arabic.onnx'
        MinBytes = 5MB
    },
    @{
        UrlName  = 'ppocrv5_arabic_dict.txt'
        FileName = 'ppocrv5_arabic_dict.txt'
        MinBytes = 100
    }
)

New-Item -ItemType Directory -Force -Path $ModelDir | Out-Null

function Test-ArtifactComplete {
    param([string]$Path, [long]$MinBytes)
    if (-not (Test-Path $Path)) {
        return $false
    }
    $size = (Get-Item $Path).Length
    return $size -ge $MinBytes
}

foreach ($item in $artifacts) {
    $local = Join-Path $ModelDir $item.FileName
    if (-not $Force -and (Test-ArtifactComplete -Path $local -MinBytes $item.MinBytes)) {
        $mb = [math]::Round((Get-Item $local).Length / 1MB, 2)
        Write-Host "Using cached $($item.FileName) ($mb MB)"
        continue
    }

    if (Test-Path $local) {
        Remove-Item $local -Force
    }

    $url = "$releaseBase/$($item.UrlName)"
    Write-Host "Downloading $($item.FileName) from GreatV/oar-ocr v0.3.0 ..."
    curl.exe -L --fail --retry 3 --retry-delay 2 -o $local $url

    if (-not (Test-ArtifactComplete -Path $local -MinBytes $item.MinBytes)) {
        $size = if (Test-Path $local) { (Get-Item $local).Length } else { 0 }
        throw "Download incomplete for $($item.FileName) ($size bytes, need >= $($item.MinBytes))"
    }

    $mb = [math]::Round((Get-Item $local).Length / 1MB, 2)
    Write-Host "Saved: $local ($mb MB)"
}

Write-Host ''
Write-Host "PaddleOCR artifacts ready in $ModelDir"
Write-Host 'Next: powershell -ExecutionPolicy Bypass -File tools\push_paddleocr_models_to_device.ps1'
