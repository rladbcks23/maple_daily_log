param(
    [string]$FlutterCommand = "C:\flutter\bin\flutter.bat",
    [string]$ShorebirdCommand = "$env:USERPROFILE\.shorebird\bin\shorebird.ps1",
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"

$appRoot = Split-Path -Parent $PSScriptRoot

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

if (-not (Test-Path -LiteralPath $ShorebirdCommand)) {
    throw "Shorebird CLI was not found at: $ShorebirdCommand"
}

$pubspecVersionLine = Get-Content (Join-Path $appRoot "pubspec.yaml") |
    Select-String -Pattern '^version:\s*(\S+)'
if (-not $pubspecVersionLine) {
    throw "Could not find a 'version:' line in pubspec.yaml."
}
$fullVersion = $pubspecVersionLine.Matches[0].Groups[1].Value
$versionParts = $fullVersion -split '\+'
$version = $versionParts[0]
$buildNumber = if ($versionParts.Count -gt 1) { $versionParts[1] } else { "1" }

Write-Host "Patching against release $version+$buildNumber..."

Push-Location $appRoot
try {
    Invoke-Checked -Command $FlutterCommand -CommandArguments @("pub", "get")
    Invoke-Checked -Command $FlutterCommand -CommandArguments @("analyze")
    if (-not $SkipTests) {
        Invoke-Checked -Command $FlutterCommand -CommandArguments @("test")
    }
    # Patches only carry Dart code changes. If this run reports asset/native diffs,
    # the fix needs a full "업데이트 파일" release instead — see release notes memory.
    Invoke-Checked `
        -Command $ShorebirdCommand `
        -CommandArguments @(
            "patch", "windows",
            "--build-name=$version",
            "--build-number=$buildNumber"
        )
} finally {
    Pop-Location
}

Write-Host "Patch pushed. Already-installed apps (matching release $version+$buildNumber, built via shorebird release) will pick it up automatically on next launch."
