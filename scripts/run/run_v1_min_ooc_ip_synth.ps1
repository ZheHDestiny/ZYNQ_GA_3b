param([string]$VivadoRoot = "C:\Users\huazh\Desktop\Vivado2023\Vivado\2023.2")
$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$vivado = Join-Path $VivadoRoot "bin\vivado.bat"
$env:TCL_LIBRARY = Join-Path $repo "tools\vivado_tcl\tcl8.5"
$env:PATH = (Join-Path $VivadoRoot "bin") + ";" + $env:PATH
$runs = Join-Path $repo "vivado\runs\v1_min_bd\ga3b_v1_min_bd.runs"
$customName = "ga3b_system_ga3b_accel_0_0_synth_1"
$customDir = Join-Path $runs $customName
$customDcp = Join-Path $customDir "ga3b_system_ga3b_accel_0_0.dcp"
$customSources = @(
  (Join-Path $repo "rtl\ga_core\ga3b_rng_xorshift32.v"),
  (Join-Path $repo "rtl\pure3_core\ga3b_pure3_rf_fitness_lane.v"),
  (Join-Path $repo "rtl\pure3_core\ga3b_pure3_rf_ga_core.v"),
  (Join-Path $repo "rtl\pure3_core\ga3b_pure3_rf_accel_top.v"),
  (Join-Path $repo "rtl\top\ga3b_v1_min_accel_top.v")
)
$latestSource = ($customSources | Get-Item | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
if (!(Test-Path -LiteralPath $customDcp) -or (Get-Item -LiteralPath $customDcp).LastWriteTime -lt $latestSource) {
  Write-Host "GA3B: custom RTL is newer than OOC DCP; invalidating generated IP cache"
  $cache = Join-Path $repo "vivado\runs\v1_min_bd\ga3b_v1_min_bd.cache\ip\2023.2"
  $repoFull = [IO.Path]::GetFullPath($repo.Path)
  $cacheFull = [IO.Path]::GetFullPath($cache)
  if (!$cacheFull.StartsWith($repoFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe generated cache path: $cacheFull"
  }
  if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Recurse -Force }
  foreach ($leaf in @("ga3b_system_ga3b_accel_0_0.dcp", "__synthesis_is_complete__", "__synthesis_is_running__")) {
    $path = Join-Path $customDir $leaf
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
  }
}
$ipRuns = @(
  "ga3b_system_auto_pc_0_synth_1",
  "ga3b_system_auto_pc_1_synth_1",
  "ga3b_system_auto_us_0_synth_1",
  "ga3b_system_auto_us_1_synth_1",
  "ga3b_system_axi_dma_0_0_synth_1",
  $customName,
  "ga3b_system_ps7_0_0_synth_1",
  "ga3b_system_rst_fclk0_0_synth_1",
  "ga3b_system_xbar_0_synth_1",
  "ga3b_system_xbar_1_synth_1"
)
foreach ($name in $ipRuns) {
  $dir = Join-Path $runs $name
  $tcl = Join-Path $dir (($name -replace '_synth_1$', '') + '.tcl')
  if (!(Test-Path -LiteralPath $tcl)) { throw "Missing generated IP synthesis Tcl: $tcl" }
  $done = Join-Path $dir "__synthesis_is_complete__"
  if (Test-Path -LiteralPath $done) {
    Write-Host "GA3B: reusing completed OOC DCP $name"
    continue
  }
  Write-Host "GA3B: synthesizing OOC IP $name"
  Push-Location $dir
  try { & $vivado -mode batch -source $tcl; if ($LASTEXITCODE -ne 0) { throw "OOC synthesis failed: $name" } }
  finally { Pop-Location }
}
