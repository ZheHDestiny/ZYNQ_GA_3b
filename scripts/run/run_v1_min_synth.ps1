param(
    [string]$VivadoRoot = "C:\Users\huazh\Desktop\Vivado2023\Vivado\2023.2"
)
# Compatibility wrapper for the verified single-process custom RTL synthesis.
& (Join-Path $PSScriptRoot "run_v1_min_accel_synth.ps1") -VivadoRoot $VivadoRoot
exit $LASTEXITCODE