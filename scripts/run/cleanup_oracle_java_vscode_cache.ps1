# Run only after all VS Code windows are closed.
param([string]$WorkspaceStorage = "C:\Users\huazh\AppData\Roaming\Code\User\workspaceStorage\cee791d5fc70e1edc56d68a761d2468b")
$ErrorActionPreference = "Stop"
$cache = Join-Path $WorkspaceStorage "Oracle.oracle-java"
if (Test-Path -LiteralPath $cache) {
    Remove-Item -LiteralPath $cache -Recurse -Force
    Write-Host "Removed: $cache"
} else {
    Write-Host "Cache already absent: $cache"
}