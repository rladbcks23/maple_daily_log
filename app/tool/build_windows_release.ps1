param(
    [string]$FlutterCommand = "C:\flutter\bin\flutter.bat",
    [switch]$SkipTests,
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"

$appRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $appRoot
$releaseDirectory = Join-Path $appRoot "build\windows\x64\runner\Release"
$distDirectory = Join-Path $repositoryRoot "dist"
$version = "0.1.0"
$zipPath = Join-Path $distDirectory "MapleTaskReminder-$version-windows-x64.zip"
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
    Invoke-Checked `
        -Command $FlutterCommand `
        -CommandArguments @("build", "windows", "--release")
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
Write-Host "Installer: $(Join-Path $distDirectory "MapleTaskReminder-Setup-$version.exe")"
