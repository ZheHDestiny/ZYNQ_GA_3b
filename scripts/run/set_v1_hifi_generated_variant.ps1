param([ValidateSet(0,1)][int]$Mode)
$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$path = Join-Path $repo "vivado\runs\v1_min_bd\ga3b_v1_min_bd.gen\sources_1\bd\ga3b_system\ip\ga3b_system_ga3b_accel_0_0\synth\ga3b_system_ga3b_accel_0_0.v"
if (!(Test-Path -LiteralPath $path)) { throw "Generated module wrapper missing: $path" }
$text = Get-Content -LiteralPath $path -Raw
$text = [regex]::Replace($text,
  '(?s)\.GENE_COUNT\(8\),\s*\.GENE_WIDTH\(32\),\s*\.FITNESS_WIDTH\(64\)(?:,\s*\.HIFI_ENABLE\([01]\),\s*\.INTEGRATOR_MODE\([01]\))?',
  ".GENE_COUNT(8),`r`n    .GENE_WIDTH(32),`r`n    .FITNESS_WIDTH(64),`r`n    .HIFI_ENABLE(1),`r`n    .INTEGRATOR_MODE($Mode)")
if ($text -notmatch "\.INTEGRATOR_MODE\($Mode\)") { throw "Failed to parameterize generated wrapper" }
# Vivado Verilog rejects a UTF-8 BOM as three non-printable source bytes.
[IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
Write-Host "GA3B_GENERATED_VARIANT_SET mode=$Mode path=$path"
