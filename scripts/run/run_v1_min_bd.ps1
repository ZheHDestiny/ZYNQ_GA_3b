param(
    [string]$VivadoRoot = "C:\Users\huazh\Desktop\Vivado2023\Vivado\2023.2"
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$vivadoBat = Join-Path $VivadoRoot "bin\vivado.bat"
if (!(Test-Path -LiteralPath $vivadoBat)) {
    throw "vivado.bat not found: $vivadoBat"
}

# Keep the same Tcl environment workaround used by the existing project scripts.
$env:TCL_LIBRARY = Join-Path $repo "tools\vivado_tcl\tcl8.5"
$env:PATH = (Join-Path $VivadoRoot "bin") + ";" + $env:PATH

$tcl = Join-Path $repo "vivado\scripts\create_v1_min_bd.tcl"
& $vivadoBat -mode batch -source $tcl
exit $LASTEXITCODE