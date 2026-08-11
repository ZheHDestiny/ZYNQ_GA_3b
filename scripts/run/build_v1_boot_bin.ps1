param(
    [string]$VitisRoot = "C:\Users\huazh\Desktop\Vivado2023\Vitis\2023.2"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$xsct = Join-Path $VitisRoot "bin\xsct.bat"
$bootgen = Join-Path $VitisRoot "bin\bootgen.bat"
$gcc = Join-Path $VitisRoot "gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe"
$fsblTcl = Join-Path $repo "scripts\vitis\create_build_v1_fsbl.tcl"
$fsbl = Join-Path $repo "vitis_workspace\v1_min_standalone\ga3b_v1_fsbl\Debug\ga3b_v1_fsbl.elf"
$fsblSrc = Join-Path $repo "vitis_workspace\v1_min_standalone\ga3b_v1_fsbl\src"
$domain = Join-Path $repo "vitis_workspace\v1_min_standalone\ga3b_v1_platform\export\ga3b_v1_platform\sw\ga3b_v1_platform\standalone_domain"
$include = Join-Path $domain "bspinclude\include"
$lib = Join-Path $domain "bsplib\lib"
$bit = Join-Path $repo "vivado\runs\v1_min_bd\artifacts\ga3b_v1_min.bit"
$agent = Join-Path $repo "vitis_workspace\v1_min_standalone\ga3b_uart_board_agent\ga3b_uart_board_agent.elf"
$outDir = Join-Path $repo "vivado\runs\v1_min_bd\artifacts\sd_boot"
$bif = Join-Path $outDir "ga3b_v1_min.bif"
$bootBin = Join-Path $outDir "BOOT.BIN"

# XSCT is used once to generate the canonical FSBL sources and xilffs-enabled
# BSP.  Vitis/Eclipse project builds can hang on this Windows host, so compile
# the generated sources deterministically with the Vitis ARM GCC afterwards.
if (!(Test-Path -LiteralPath (Join-Path $fsblSrc "main.c")) -or
    !(Test-Path -LiteralPath (Join-Path $lib "libxilffs.a"))) {
    & $xsct $fsblTcl
    if ($LASTEXITCODE -ne 0) { throw "FSBL XSCT generation failed: $LASTEXITCODE" }
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fsbl) | Out-Null
$sources = @()
$sources += Get-ChildItem -LiteralPath $fsblSrc -Filter "*.c" | ForEach-Object { $_.FullName }
$sources += Get-ChildItem -LiteralPath $fsblSrc -Filter "*.S" | ForEach-Object { $_.FullName }
$gccArgs = @(
    "-mcpu=cortex-a9", "-mfpu=vfpv3", "-mfloat-abi=hard", "-O2", "-g",
    "-specs=$(Join-Path $fsblSrc 'Xilinx.spec')",
    "-I", $include, "-I", $fsblSrc,
    "-Wl,-T", (Join-Path $fsblSrc "lscript.ld"), "-L", $lib,
    "-o", $fsbl
) + $sources + @(
    "-Wl,--start-group", "-lxilffs", "-lxil", "-lgcc", "-lc", "-Wl,--end-group"
)
& $gcc @gccArgs
if ($LASTEXITCODE -ne 0) { throw "Direct FSBL GCC build failed: $LASTEXITCODE" }
Write-Host "GA3B_FSBL_GCC_PASS: $fsbl"
foreach ($path in @($fsbl, $bit, $agent)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Missing boot image input: $path" }
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$bifText = @"
the_ROM_image:
{
  [bootloader] $($fsbl.Replace('\','/'))
  $($bit.Replace('\','/'))
  $($agent.Replace('\','/'))
}
"@
Set-Content -LiteralPath $bif -Value $bifText -Encoding ascii
& $bootgen -arch zynq -image $bif -o $bootBin -w on
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $bootBin)) {
    throw "Bootgen failed: $LASTEXITCODE"
}
Write-Host "GA3B_BOOT_BIN_PASS: $bootBin"
