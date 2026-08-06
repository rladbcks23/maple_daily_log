param(
    [string]$FlutterCommand = "C:\flutter\bin\flutter.bat",
    [string]$ShorebirdCommand = "$env:USERPROFILE\.shorebird\bin\shorebird.ps1",
    [switch]$SkipTests,
    [switch]$SkipInstaller,
    [switch]$SkipShorebird
)

$ErrorActionPreference = "Stop"

$appRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $appRoot
$releaseDirectory = Join-Path $appRoot "build\windows\x64\runner\Release"
$distDirectory = Join-Path $repositoryRoot "dist"

$pubspecVersionLine = Get-Content (Join-Path $appRoot "pubspec.yaml") |
    Select-String -Pattern '^version:\s*(\S+)'
if (-not $pubspecVersionLine) {
    throw "Could not find a 'version:' line in pubspec.yaml."
}
$fullVersion = $pubspecVersionLine.Matches[0].Groups[1].Value
$versionParts = $fullVersion -split '\+'
$version = $versionParts[0]
$buildNumber = if ($versionParts.Count -gt 1) { $versionParts[1] } else { "1" }
$distVersion = $version

$zipPath = Join-Path $distDirectory "MapleTaskReminder-$distVersion-windows-x64.zip"
$installerScript = Join-Path $appRoot "installer\maple_task_reminder.iss"

function Invoke-Checked {
    param(
        [string]$Command,
        [string[]]$CommandArguments
    )

    & $Command @CommandArguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path -LiteralPath $FlutterCommand)) {
    throw "Flutter executable was not found: $FlutterCommand"
}

New-Item -ItemType Directory -Path $distDirectory -Force | Out-Null

Push-Location $appRoot
try {
    Invoke-Checked -Command $FlutterCommand -CommandArguments @("pub", "get")
    Invoke-Checked -Command $FlutterCommand -CommandArguments @("analyze")
    if (-not $SkipTests) {
        Invoke-Checked -Command $FlutterCommand -CommandArguments @("test")
    }
    if ($SkipShorebird -or -not (Test-Path -LiteralPath $ShorebirdCommand)) {
        Invoke-Checked `
            -Command $FlutterCommand `
            -CommandArguments @("build", "windows", "--release")
    } else {
        # Building via Shorebird (instead of a plain flutter build) registers this
        # build as a patchable release, so future "테스트 파일"/hotfix-style Dart-only
        # changes can be pushed with shorebird_patch_windows.ps1 without a full reinstall.
        Invoke-Checked `
            -Command $ShorebirdCommand `
            -CommandArguments @(
                "release", "windows",
                "--build-name=$version",
                "--build-number=$buildNumber"
            )
    }
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $releaseDirectory)) {
    throw "Windows release directory was not created: $releaseDirectory"
}

Compress-Archive `
    -Path (Join-Path $releaseDirectory "*") `
    -DestinationPath $zipPath `
    -CompressionLevel Optimal `
    -Force
Write-Host "Portable package: $zipPath"

if ($SkipInstaller) {
    exit 0
}

$innoSetupCandidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
$innoSetupCompiler = $innoSetupCandidates |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
    Select-Object -First 1

if (-not $innoSetupCompiler) {
    Write-Warning "Inno Setup 6 was not found. The portable ZIP is ready, but the installer was not created."
    exit 0
}

Invoke-Checked `
    -Command $innoSetupCompiler `
    -CommandArguments @($installerScript)
Write-Host "Installer: $(Join-Path $distDirectory "MapleTaskReminder-Setup-$distVersion.exe")"
