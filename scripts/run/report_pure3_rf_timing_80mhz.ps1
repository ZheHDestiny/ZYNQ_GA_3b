# Run Vivado synth/place/route for additional pure3 resource-fit RTL on xc7z020clg400-2.
$ErrorActionPreference = 'Stop'
$vivadoRoot = 'C:\Users\huazh\Desktop\Vivado2023\Vivado\2023.2'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..\..')
$localTcl85 = Resolve-Path (Join-Path $repoRoot 'tools\vivado_tcl\tcl8.5')
$env:TCL_LIBRARY = $localTcl85.Path.Replace('\', '/')
$env:TK_LIBRARY = $null
$env:TCLLIBPATH = $null
$env:XILINX_VIVADO = $vivadoRoot
$env:RDI_APPROOT = $vivadoRoot
$env:HDI_APPROOT = $vivadoRoot
$env:RDI_BINROOT = Join-Path $vivadoRoot 'bin'
$env:RDI_BINDIR = Join-Path $vivadoRoot 'bin'
$env:RDI_LIBDIR = Join-Path $vivadoRoot 'lib\win64.o'
$env:RDI_DATADIR = Join-Path $vivadoRoot 'data'
$env:RDI_PLATFORM = 'win64.o'
$env:ISL_IOSTREAMS_RSA = Join-Path $vivadoRoot 'tps\isl'
$env:PATH = (Join-Path $vivadoRoot 'lib\win64.o') + ';' +
            (Join-Path $vivadoRoot 'bin\unwrapped\win64.o') + ';' +
            (Join-Path $vivadoRoot 'bin') + ';' +
            (Join-Path $vivadoRoot 'tps\win64\python-3.8.3') + ';' +
            (Join-Path $vivadoRoot 'tps\win64\python-3.8.3\DLLs') + ';' +
            (Join-Path $vivadoRoot 'tps\win64\jre17.0.7_7\bin\server') + ';' +
            (Join-Path $vivadoRoot 'tps\win64\jre17.0.7_7\bin') + ';' +
            (Join-Path $vivadoRoot 'tps\mingw\6.2.0\win64.o\nt\bin') + ';' +
            $env:PATH
$tcl = Join-Path $repoRoot 'vivado\scripts\report_pure3_rf_timing_80mhz.tcl'
& (Join-Path $vivadoRoot 'bin\vivado.bat') -mode batch -source $tcl
exit $LASTEXITCODE

