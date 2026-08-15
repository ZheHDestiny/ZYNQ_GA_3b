param(
    [string]$Port = "COM13",
    [int]$HttpPort = 8000,
    [string]$BindHost = "127.0.0.1",
    [int]$UartTimeout = 600,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$backend = Join-Path $repo "ps_app\host_backend"
$url = "http://${BindHost}:${HttpPort}/"

Write-Host "GA3B v1.1 Web Demo"
Write-Host "  UART : $Port"
Write-Host "  URL  : $url"
Write-Host "Close serial terminals before continuing. Press Ctrl+C to stop."

Push-Location $backend
try {
    $arguments = @('-B', 'ga3b_api.py', '--port', $Port, '--host', $BindHost,
                   '--http-port', $HttpPort, '--uart-timeout', $UartTimeout)
    if (-not $NoBrowser) { $arguments += '--open-browser' }
    & python @arguments
    if ($LASTEXITCODE -ne 0) { throw "GA3B backend exited with code $LASTEXITCODE" }
}
finally {
    Pop-Location
}
