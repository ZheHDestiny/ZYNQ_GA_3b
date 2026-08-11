param(
    [string]$VitisRoot = "C:\Users\huazh\Desktop\Vivado2023\Vitis\2023.2"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$gcc = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe"
$app = Join-Path $repo "vitis_workspace\v1_min_standalone\ga3b_dma_smoke"
$src = Join-Path $app "src"
$domain = Join-Path $repo "vitis_workspace\v1_min_standalone\ga3b_v1_platform\export\ga3b_v1_platform\sw\ga3b_v1_platform\standalone_domain"
$include = Join-Path $domain "bspinclude\include"
$lib = Join-Path $domain "bsplib\lib"
$elf = Join-Path $app "ga3b_dma_smoke.elf"

foreach ($required in @($gcc, $include, (Join-Path $lib "libxil.a"), (Join-Path $src "lscript.ld"), (Join-Path $src "Xilinx.spec"))) {
    if (!(Test-Path -LiteralPath $required)) { throw "Missing Vitis build input: $required" }
}
Copy-Item -LiteralPath (Join-Path $repo "ps_app\board_agent\standalone\ga3b_dma_smoke.c") -Destination $src -Force
Copy-Item -LiteralPath (Join-Path $repo "ps_app\common\ga3b_protocol.h") -Destination $src -Force

$gccArgs = @(
    "-mcpu=cortex-a9", "-mfpu=vfpv3", "-mfloat-abi=hard",
    "-O2", "-g", "-Wall", "-Wextra",
    "-specs=$(Join-Path $src 'Xilinx.spec')",
    "-I", $include, "-I", $src,
    "-Wl,-T", (Join-Path $src "lscript.ld"), "-L", $lib,
    "-o", $elf, (Join-Path $src "ga3b_dma_smoke.c"),
    "-Wl,--start-group", "-lxil", "-lgcc", "-lc", "-Wl,--end-group"
)
& $gcc @gccArgs
if ($LASTEXITCODE -ne 0) { throw "Standalone ELF build failed with exit code $LASTEXITCODE" }
Write-Host "GA3B_VITIS_BUILD_PASS: $elf"
