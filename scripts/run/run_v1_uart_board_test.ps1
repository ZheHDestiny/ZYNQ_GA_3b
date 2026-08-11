param(
    [string]$Port = "COM13",
    [int]$Count = 100,
    [string]$VivadoRoot = "C:\Users\huazh\Desktop\Vivado2023\Vivado\2023.2",
    [string]$VitisRoot = "C:\Users\huazh\Desktop\Vivado2023\Vitis\2023.2"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$hwServer = Join-Path $VivadoRoot "bin\hw_server.bat"
$xsct = Join-Path $VitisRoot "bin\xsct.bat"
$downloadTcl = Join-Path $repo "scripts\vitis\download_v1_uart_agent.tcl"
$bit = Join-Path $repo "vivado\runs\v1_min_bd\artifacts\ga3b_v1_min.bit"
$elf = Join-Path $repo "vitis_workspace\v1_min_standalone\ga3b_uart_board_agent\ga3b_uart_board_agent.elf"
$psInit = Join-Path $repo "vitis_workspace\v1_min_standalone\ga3b_v1_platform\export\ga3b_v1_platform\hw\ps7_init.tcl"
$report = Join-Path $repo "doc\test_results\v1_uart_soak_latest.json"
foreach ($path in @($hwServer, $xsct, $downloadTcl, $bit, $elf, $psInit)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Missing board-test input: $path" }
}
if ([System.IO.Ports.SerialPort]::GetPortNames() -notcontains $Port) {
    throw "Serial port $Port is not present"
}

$existing = Get-Process hw_server -ErrorAction SilentlyContinue
$started = $null
if (!$existing) {
    $started = Start-Process -FilePath $hwServer -ArgumentList "-s", "tcp::3121" -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 4
}
try {
    & $xsct $downloadTcl $bit $elf $psInit
    if ($LASTEXITCODE -ne 0) { throw "XSCT download failed: $LASTEXITCODE" }
    Start-Sleep -Milliseconds 500
    Push-Location (Join-Path $repo "ps_app\host_backend")
    try {
        python -B ga3b_uart_soak.py --port $Port --count $Count --report $report
        if ($LASTEXITCODE -ne 0) { throw "UART soak failed: $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
} finally {
    if ($started -and !$started.HasExited) {
        Stop-Process -Id $started.Id -Force -ErrorAction SilentlyContinue
    }
}
Write-Host "GA3B_V1_UART_BOARD_TEST_PASS: $report"
