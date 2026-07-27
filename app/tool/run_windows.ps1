param(
    [switch]$ShowEngineLogs
)

$ErrorActionPreference = "Stop"

$flutter = "C:\flutter\bin\flutter.bat"
if (-not (Test-Path $flutter)) {
    $flutter = "flutter"
}

if ($ShowEngineLogs) {
    & $flutter run -d windows
    exit $LASTEXITCODE
}

$logDir = Join-Path $PSScriptRoot "..\.dart_tool"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$stderrLog = Join-Path $logDir "flutter_windows_stderr.log"
Write-Host "Flutter Windows debug run. Engine stderr is saved to $stderrLog"
Write-Host "Use -ShowEngineLogs to print engine logs in this terminal."

& $flutter run -d windows 2> $stderrLog
exit $LASTEXITCODE
