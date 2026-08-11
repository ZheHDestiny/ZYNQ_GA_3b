param(
    [string]$VitisRoot = "C:\Users\huazh\Desktop\Vivado2023\Vitis\2023.2"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$gcc = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe"
$workspace = Join-Path $repo "vitis_workspace\v1_min_standalone"
$templateSrc = Join-Path $workspace "ga3b_dma_smoke\src"
$app = Join-Path $workspace "ga3b_uart_board_agent"
$src = Join-Path $app "src"
$domain = Join-Path $workspace "ga3b_v1_platform\export\ga3b_v1_platform\sw\ga3b_v1_platform\standalone_domain"
$include = Join-Path $domain "bspinclude\include"
$lib = Join-Path $domain "bsplib\lib"
$elf = Join-Path $app "ga3b_uart_board_agent.elf"

foreach ($required in @($gcc, $include, (Join-Path $lib "libxil.a"),
                         (Join-Path $templateSrc "lscript.ld"), (Join-Path $templateSrc "Xilinx.spec"))) {
    if (!(Test-Path -LiteralPath $required)) { throw "Missing Vitis build input: $required" }
}
New-Item -ItemType Directory -Force -Path $src | Out-Null
Copy-Item -LiteralPath (Join-Path $templateSrc "lscript.ld") -Destination $src -Force
Copy-Item -LiteralPath (Join-Path $templateSrc "Xilinx.spec") -Destination $src -Force
Copy-Item -LiteralPath (Join-Path $repo "ps_app\board_agent\standalone\ga3b_uart_board_agent.c") -Destination $src -Force
Copy-Item -LiteralPath (Join-Path $repo "ps_app\common\ga3b_protocol.h") -Destination $src -Force

$gccArgs = @(
    "-mcpu=cortex-a9", "-mfpu=vfpv3", "-mfloat-abi=hard",
    "-O2", "-g", "-Wall", "-Wextra",
    "-specs=$(Join-Path $src 'Xilinx.spec')",
    "-I", $include, "-I", $src,
    "-Wl,-T", (Join-Path $src "lscript.ld"), "-L", $lib,
    "-o", $elf, (Join-Path $src "ga3b_uart_board_agent.c"),
    "-Wl,--start-group", "-lxil", "-lgcc", "-lc", "-Wl,--end-group"
)
& $gcc @gccArgs
if ($LASTEXITCODE -ne 0) { throw "Standalone UART board-agent ELF build failed: $LASTEXITCODE" }
Write-Host "GA3B_UART_AGENT_BUILD_PASS: $elf"
