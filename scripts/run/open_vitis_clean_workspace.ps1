param(
    [string]$VitisRoot = "C:\Users\huazh\Desktop\Vivado2023\Vitis\2023.2",
    [string]$Workspace = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
    $Workspace = Join-Path $repo "vitis_workspace"
}
$eclipse = Join-Path $VitisRoot "eclipse\win64.o\eclipse.exe"
if (!(Test-Path -LiteralPath $eclipse)) {
    throw "Vitis Eclipse executable not found: $eclipse"
}
New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
Write-Host "Starting Vitis with clean workspace: $Workspace"
Start-Process -FilePath $eclipse -ArgumentList @("-data", $Workspace) -WorkingDirectory (Split-Path -Parent $eclipse)