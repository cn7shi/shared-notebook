[CmdletBinding()]
param(
    [string]$FlutterSdk = $env:FLUTTER_ROOT,
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$BuildRoot = (Join-Path ([IO.Path]::GetTempPath()) 'shared-notebook-android'),
    [string]$ApiBaseUrl = 'http://10.0.2.2:3300',
    [string]$TestDevice = '',
    [switch]$KeepTestApp
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $FlutterSdk) {
    $flutterCommand = (Get-Command flutter -ErrorAction Stop).Source
    $FlutterSdk = Split-Path (Split-Path $flutterCommand -Parent) -Parent
}
$flutter = Join-Path $FlutterSdk 'bin/flutter.bat'
if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) { throw 'Flutter SDK not found.' }
$buildRootPath = [IO.Path]::GetFullPath($BuildRoot)
if ($buildRootPath -match '[^\x00-\x7F]') { throw 'BuildRoot must have an ASCII-only absolute path.' }

# A junction can resolve back to the non-ASCII checkout in Gradle. Require a
# physical build directory, leaving the source checkout and other repos intact.
New-Item -ItemType Directory -Path $buildRootPath -Force | Out-Null
$ancestor = Get-Item -LiteralPath $buildRootPath
while ($null -ne $ancestor) {
    if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'BuildRoot and its parents must be real directories, not links.'
    }
    $ancestor = $ancestor.Parent
}
$stage = Join-Path $buildRootPath ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
$files = @(& git -c core.quotepath=false -C $repoRoot ls-files --cached --others --exclude-standard -- mobile)
if ($LASTEXITCODE -ne 0 -or $files.Count -eq 0) { throw 'Cannot enumerate mobile source files.' }
$sources = @()
foreach ($file in ($files | Sort-Object -Unique)) {
    if (-not $file.StartsWith('mobile/', [StringComparison]::Ordinal)) { throw 'Unexpected source path.' }
    $source = [IO.Path]::GetFullPath((Join-Path $repoRoot $file))
    # Deleted tracked files are intentionally absent from the working snapshot.
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    $item = Get-Item -LiteralPath $source
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source links are not supported.' }
    $destination = [IO.Path]::GetFullPath((Join-Path $stage $file.Substring(7)))
    if (-not $destination.StartsWith($stage + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Source path escapes the build directory.'
    }
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
    $sources += @{ path = $file; sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash }
}

$previousAndroidHome = $env:ANDROID_HOME
$previousAndroidRoot = $env:ANDROID_SDK_ROOT
try {
    if ($AndroidSdk) {
        $env:ANDROID_HOME = $AndroidSdk
        $env:ANDROID_SDK_ROOT = $AndroidSdk
    }
    Push-Location -LiteralPath $stage
    try {
        Write-Host "Building Android debug APK from physical source snapshot: $stage"
        & $flutter pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }
        if ($TestDevice) {
            $testArgs = @('test', 'integration_test/android_flow_test.dart', '-d', $TestDevice,
                "--dart-define=API_BASE_URL=$ApiBaseUrl", '--reporter', 'expanded')
            if ($KeepTestApp) { $testArgs += '--no-uninstall' }
            & $flutter @testArgs
            if ($LASTEXITCODE -ne 0) { throw "Android device tests failed. Diagnostic workspace retained: $stage" }
        } else {
            & $flutter build apk --debug "--dart-define=API_BASE_URL=$ApiBaseUrl"
            if ($LASTEXITCODE -ne 0) { throw "Android build failed. Diagnostic workspace retained: $stage" }
        }
    } finally { Pop-Location }
    if ($TestDevice) {
        $reportDir = Join-Path $repoRoot 'mobile/build/reports'
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        @{
            testedAt = [DateTime]::UtcNow.ToString('o'); device = $TestDevice; result = 'passed'; retainedTestApp = [bool]$KeepTestApp
            sourceCommit = (& git -C $repoRoot rev-parse HEAD); sourceFiles = $sources
            apiBaseUrl = $ApiBaseUrl; buildDirectory = $stage
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportDir 'android-flow.json') -Encoding utf8
        Write-Host 'Device test passed; source hashes saved in mobile/build/reports/android-flow.json.'
        return
    }
    $artifactDir = Join-Path $repoRoot 'mobile/build/app/outputs/flutter-apk'
    New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
    $apk = Join-Path $artifactDir 'app-debug.apk'
    Copy-Item -LiteralPath (Join-Path $stage 'build/app/outputs/flutter-apk/app-debug.apk') -Destination $apk
    $revision = & git -C $repoRoot rev-parse HEAD
    $workingChanges = @(& git -C $repoRoot status --porcelain -- mobile)
    @{
        builtAt = [DateTime]::UtcNow.ToString('o'); sourceCommit = $revision
        hasMobileChanges = $workingChanges.Count -gt 0; apiBaseUrl = $ApiBaseUrl
        sha256 = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash
        sourceFiles = $sources; buildDirectory = $stage
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $artifactDir 'build-manifest.json') -Encoding utf8
    Write-Host "Debug APK: $apk"
    Write-Host 'Source hashes saved in build-manifest.json; build workspace retained for diagnosis.'
} finally {
    $env:ANDROID_HOME = $previousAndroidHome
    $env:ANDROID_SDK_ROOT = $previousAndroidRoot
}
