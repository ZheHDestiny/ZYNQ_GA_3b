param([string]$VivadoRoot = "C:\Users\huazh\Desktop\Vivado2023\Vivado\2023.2")
$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$vivado = Join-Path $VivadoRoot "bin\vivado.bat"
$env:TCL_LIBRARY = Join-Path $repo "tools\vivado_tcl\tcl8.5"
$env:PATH = (Join-Path $VivadoRoot "bin") + ";" + $env:PATH
$runs = Join-Path $repo "vivado\runs\v1_min_bd\ga3b_v1_min_bd.runs"
$ipRuns = @(
  "ga3b_system_auto_pc_0_synth_1",
  "ga3b_system_auto_pc_1_synth_1",
  "ga3b_system_auto_us_0_synth_1",
  "ga3b_system_auto_us_1_synth_1",
  "ga3b_system_axi_dma_0_0_synth_1",
  "ga3b_system_ga3b_accel_0_0_synth_1",
  "ga3b_system_ps7_0_0_synth_1",
  "ga3b_system_rst_fclk0_0_synth_1",
  "ga3b_system_xbar_0_synth_1",
  "ga3b_system_xbar_1_synth_1"
)
foreach ($name in $ipRuns) {
  $dir = Join-Path $runs $name
  $tcl = Join-Path $dir (($name -replace '_synth_1$', '') + '.tcl')
  if (!(Test-Path -LiteralPath $tcl)) { throw "Missing generated IP synthesis Tcl: $tcl" }
  Write-Host "GA3B: synthesizing OOC IP $name"
  Push-Location $dir
  try { & $vivado -mode batch -source $tcl; if ($LASTEXITCODE -ne 0) { throw "OOC synthesis failed: $name" } }
  finally { Pop-Location }
}