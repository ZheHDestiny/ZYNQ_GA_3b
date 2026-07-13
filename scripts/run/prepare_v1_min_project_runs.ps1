param([string]$VivadoRoot = "C:\Users\huazh\Desktop\Vivado2023\Vivado\2023.2")
$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$env:TCL_LIBRARY = Join-Path $repo "tools\vivado_tcl\tcl8.5"
$env:PATH = (Join-Path $VivadoRoot "bin") + ";" + $env:PATH
& (Join-Path $VivadoRoot "bin\vivado.bat") -mode batch -source (Join-Path $repo "vivado\scripts\prepare_v1_min_project_runs.tcl")
exit $LASTEXITCODE