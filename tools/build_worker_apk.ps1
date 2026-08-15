# Builds the EdgeMint Worker Android APK using a mirrored Android SDK when dl.google.com is blocked.
param(
    [ValidateSet('release', 'debug')]
    [string]$Mode = 'release',
    [string]$OutputDir = 'dist/android-worker',
    [string]$WorkerBaseUrl = 'http://172.20.34.71:8081',
    [string]$HuggingFaceToken = '',
    [string]$GemmaModelDownloadUrl = '',
    [switch]$ForceRealInference,
    [string]$TargetPlatform = ''
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$WorkerDir = Join-Path $Root 'src\apps\worker'
$SdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$Mirror = 'https://mirrors.cloud.tencent.com/AndroidSDK'

. (Join-Path $Root 'tools\flutter_env.ps1')

function Resolve-JavaHome {
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
        return $env:JAVA_HOME
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'EdgeMint\jdk-17'),
        (Join-Path $env:LOCALAPPDATA 'EdgeMint\jdk-17.0.15+6'),
        'C:\Program Files\Microsoft\jdk-17.0.15.6-hotspot',
        'C:\Program Files\Eclipse Adoptium\jdk-17*'
    )
    foreach ($candidate in $candidates) {
        if ($candidate -like '*`*') {
            $match = Get-ChildItem ($candidate.TrimEnd('*')) -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($match -and (Test-Path (Join-Path $match.FullName 'bin\java.exe'))) {
                return $match.FullName
            }
            continue
        }
        if (Test-Path (Join-Path $candidate 'bin\java.exe')) {
            return $candidate
        }
    }
    throw 'JAVA_HOME is not configured. Install JDK 17 or rerun after tools/build_worker_apk.ps1 downloads one.'
}

$env:JAVA_HOME = Resolve-JavaHome
$env:Path = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:Path
Write-Host "JAVA_HOME=$($env:JAVA_HOME)"

$gradleHome = Join-Path $env:LOCALAPPDATA 'EdgeMint\gradle-home'
$initDir = Join-Path $gradleHome 'init.d'
New-Item -ItemType Directory -Force -Path $initDir | Out-Null
Copy-Item -Force (Join-Path $Root 'tools\gradle\edgemint-mirror.init.gradle') (Join-Path $initDir 'edgemint-mirror.init.gradle')
$env:GRADLE_USER_HOME = $gradleHome
Write-Host "GRADLE_USER_HOME=$gradleHome"

function Download-Archive {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    if (Test-Path $Destination) { return }
    Write-Host "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination
}

function Expand-ArchiveTo {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Expand-Archive -Path $ZipPath -DestinationPath $Destination -Force
}

function Normalize-AndroidPackageExtract {
    param([Parameter(Mandatory = $true)][string]$Destination)
    $nested = Get-ChildItem -Path $Destination -Directory | Where-Object { $_.Name -like 'android-*' } | Select-Object -First 1
    if ($null -eq $nested) { return }
    Get-ChildItem -Path $nested.FullName -Force | ForEach-Object {
        Move-Item -Force $_.FullName -Destination $Destination
    }
    Remove-Item -Recurse -Force $nested.FullName
}

function Ensure-BuildToolsVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$TemplateVersion
    )
    $targetDir = Join-Path $SdkRoot "build-tools\$Version"
    if (Test-Path (Join-Path $targetDir 'aapt.exe')) { return }
    $templateDir = Join-Path $SdkRoot "build-tools\$TemplateVersion"
    if (-not (Test-Path (Join-Path $templateDir 'aapt.exe'))) {
        throw "Missing build-tools template at $templateDir"
    }
    if (Test-Path $targetDir) { Remove-Item -Recurse -Force $targetDir }
    Copy-Item -Recurse -Force $templateDir $targetDir
    $sourceProps = Join-Path $targetDir 'source.properties'
    if (Test-Path $sourceProps) {
        (Get-Content $sourceProps) -replace 'Pkg.Revision=.*', "Pkg.Revision=$Version" | Set-Content $sourceProps
    }
}

function Ensure-AndroidSdk {
    New-Item -ItemType Directory -Force -Path $SdkRoot | Out-Null

    $cache = Join-Path $env:TEMP 'edgemint-android-sdk-cache'
    New-Item -ItemType Directory -Force -Path $cache | Out-Null

    $cmdlineZip = Join-Path $cache 'commandlinetools-win.zip'
    Download-Archive -Url "$Mirror/commandlinetools-win-11076708_latest.zip" -Destination $cmdlineZip
    $latestDir = Join-Path $SdkRoot 'cmdline-tools\latest'
    if (-not (Test-Path (Join-Path $latestDir 'bin\sdkmanager.bat'))) {
        $extract = Join-Path $cache 'cmdline-tools'
        if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
        Expand-ArchiveTo -ZipPath $cmdlineZip -Destination $extract
        New-Item -ItemType Directory -Force -Path (Split-Path $latestDir) | Out-Null
        Move-Item -Force (Join-Path $extract 'cmdline-tools') $latestDir
    }

    $platformToolsZip = Join-Path $cache 'platform-tools.zip'
    Download-Archive -Url "$Mirror/platform-tools_r36.0.0-win.zip" -Destination $platformToolsZip
    $platformToolsDir = Join-Path $SdkRoot 'platform-tools'
    if (-not (Test-Path (Join-Path $platformToolsDir 'adb.exe'))) {
        if (Test-Path $platformToolsDir) { Remove-Item -Recurse -Force $platformToolsDir }
        Expand-ArchiveTo -ZipPath $platformToolsZip -Destination $SdkRoot
    }

    $buildToolsZip = Join-Path $cache 'build-tools.zip'
    Download-Archive -Url "$Mirror/build-tools_r34-windows.zip" -Destination $buildToolsZip
    $buildToolsDir = Join-Path $SdkRoot 'build-tools\34.0.0'
    if (-not (Test-Path (Join-Path $buildToolsDir 'aapt.exe'))) {
        New-Item -ItemType Directory -Force -Path (Join-Path $SdkRoot 'build-tools') | Out-Null
        if (-not (Test-Path $buildToolsDir)) {
            Expand-ArchiveTo -ZipPath $buildToolsZip -Destination $buildToolsDir
        }
    }
    Normalize-AndroidPackageExtract -Destination $buildToolsDir
    Ensure-BuildToolsVersion -Version '36.0.0' -TemplateVersion '34.0.0'

    function Ensure-AndroidPlatform {
        param(
            [Parameter(Mandatory = $true)][string]$ApiLevel,
            [Parameter(Mandatory = $true)][string]$ZipName
        )
        $platformZip = Join-Path $cache $ZipName
        Download-Archive -Url "$Mirror/$ZipName" -Destination $platformZip
        $platformDir = Join-Path $SdkRoot "platforms\android-$ApiLevel"
        if (-not (Test-Path (Join-Path $platformDir 'android.jar'))) {
            New-Item -ItemType Directory -Force -Path (Join-Path $SdkRoot 'platforms') | Out-Null
            if (-not (Test-Path $platformDir)) {
                Expand-ArchiveTo -ZipPath $platformZip -Destination $platformDir
            }
        }
        Normalize-AndroidPackageExtract -Destination $platformDir
    }

    Ensure-AndroidPlatform -ApiLevel '34' -ZipName 'platform-34-ext7_r03.zip'
    Ensure-AndroidPlatform -ApiLevel '35' -ZipName 'platform-35-ext14_r01.zip'
    Ensure-AndroidPlatform -ApiLevel '36' -ZipName 'platform-36_r01.zip'

    $cmakeVersion = '3.22.1'
    $cmakeDir = Join-Path $SdkRoot "cmake\$cmakeVersion"
    if (-not (Test-Path (Join-Path $cmakeDir 'bin\cmake.exe'))) {
        $cmakeZip = Join-Path $cache 'cmake.zip'
        Download-Archive -Url "$Mirror/cmake-$cmakeVersion-windows.zip" -Destination $cmakeZip
        New-Item -ItemType Directory -Force -Path (Join-Path $SdkRoot 'cmake') | Out-Null
        if (Test-Path $cmakeDir) { Remove-Item -Recurse -Force $cmakeDir }
        Expand-ArchiveTo -ZipPath $cmakeZip -Destination $cmakeDir
    }

    $ndkVersion = '28.2.13676358'
    $ndkDir = Join-Path $SdkRoot "ndk\$ndkVersion"
    if (-not (Test-Path (Join-Path $ndkDir 'source.properties'))) {
        $ndkZip = Join-Path $cache 'android-ndk-r28c-windows.zip'
        Download-Archive -Url "$Mirror/android-ndk-r28c-windows.zip" -Destination $ndkZip
        Write-Host 'Installing Android NDK (large download on first run)...'
        $ndkExtract = Join-Path $cache 'android-ndk-r28c'
        if (Test-Path $ndkExtract) { Remove-Item -Recurse -Force $ndkExtract }
        Expand-ArchiveTo -ZipPath $ndkZip -Destination $cache
        New-Item -ItemType Directory -Force -Path (Join-Path $SdkRoot 'ndk') | Out-Null
        if (Test-Path $ndkDir) { Remove-Item -Recurse -Force $ndkDir }
        Move-Item -Force $ndkExtract $ndkDir
    }

    $localProps = Join-Path $WorkerDir 'android\local.properties'
    $sdkDirEscaped = ($SdkRoot -replace '\\', '\\')
    $flutterSdkLine = Get-Content $localProps -ErrorAction SilentlyContinue | Where-Object { $_ -like 'flutter.sdk=*' } | Select-Object -First 1
    $flutterSdk = if ($flutterSdkLine) { ($flutterSdkLine -split '=', 2)[1] } else { 'C:\\Users\\Admin\\flutter' }
    @(
        "sdk.dir=$sdkDirEscaped",
        "flutter.sdk=$flutterSdk",
        "ndk.dir=$sdkDirEscaped\\ndk\\$ndkVersion"
    ) | Set-Content -Path $localProps -Encoding ascii

    $licenseDir = Join-Path $SdkRoot 'licenses'
    New-Item -ItemType Directory -Force -Path $licenseDir | Out-Null
    @(
        @{ Name = 'android-sdk-license'; Value = "24333f8a63b6825ea9c5514f83c2829b004d1fee`n" },
        @{ Name = 'android-sdk-preview-license'; Value = "84831b9409646a918e30573bab4c9c91346d8abd`n" },
        @{ Name = 'mips-android-sysimage-license'; Value = "d975f751698a77b662f1254ddbeac3901e0969e`n" }
    ) | ForEach-Object {
        $path = Join-Path $licenseDir $_.Name
        if (-not (Test-Path $path)) {
            Set-Content -Path $path -Value $_.Value -NoNewline
        }
    }

    $env:ANDROID_SDK_ROOT = $SdkRoot
    $env:ANDROID_HOME = $SdkRoot
    flutter config --android-sdk $SdkRoot | Out-Null
}

Ensure-AndroidSdk

Push-Location $WorkerDir
try {
    flutter pub get
    $dartDefines = @(
        "--dart-define=EDGEMINT_WORKER_BASE_URL=$WorkerBaseUrl"
    )
    if ($HuggingFaceToken) {
        $dartDefines += "--dart-define=HUGGINGFACE_TOKEN=$HuggingFaceToken"
    }
    if ($GemmaModelDownloadUrl) {
        $dartDefines += "--dart-define=GEMMA_MODEL_DOWNLOAD_URL=$GemmaModelDownloadUrl"
    }
    if ($ForceRealInference) {
        $dartDefines += '--dart-define=WORKER_FORCE_REAL_INFERENCE=true'
    }
    if ($TargetPlatform) {
        $dartDefines += "--target-platform=$TargetPlatform"
    }
    Remove-Item -Recurse -Force 'build' -ErrorAction SilentlyContinue
    if ($Mode -eq 'debug') {
        flutter build apk --debug @dartDefines
        if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed with exit code $LASTEXITCODE" }
        $apk = Get-ChildItem -Path 'build\app\outputs\flutter-apk\app-debug.apk' -ErrorAction Stop
    } else {
        flutter build apk --release @dartDefines
        if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed with exit code $LASTEXITCODE" }
        $apk = Get-ChildItem -Path 'build\app\outputs\flutter-apk\app-release.apk' -ErrorAction Stop
    }
} finally {
    Pop-Location
}

$destRoot = Join-Path $Root $OutputDir
New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
$destApk = Join-Path $destRoot $apk.Name
Copy-Item -Force $apk.FullName $destApk
Write-Host "APK_READY: $destApk"
