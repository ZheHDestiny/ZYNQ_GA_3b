param(
    [string]$HostName = "zynq",
    [string]$UserName = "root",
    [string]$Password,
    [string]$HostKey = "ssh-rsa 2048 SHA256:lFCxH6HrLrq75VdPG3ZaC07zdXo3cjvZJTTFqX1a15w"
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrEmpty($Password)) { $Password = Read-Host "SSH password" }
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$artifacts = Join-Path $repo "vivado\runs\v1_min_bd\artifacts"
$bitBin = Join-Path $artifacts "ga3b_v1_min.bit.bin"
$probe = Join-Path $artifacts "ga3b_reg_probe"
$plink = "C:\Program Files\PuTTY\plink.exe"
$pscp = "C:\Program Files\PuTTY\pscp.exe"
foreach ($required in @($plink, $pscp, $bitBin, $probe)) {
    if (!(Test-Path -LiteralPath $required)) { throw "Missing deployment input: $required" }
}

$ssh = @("-batch", "-ssh", "-hostkey", $HostKey, "-l", $UserName, "-pw", $Password, $HostName)
& $plink @ssh "mkdir -p /tmp/ga3b && chmod 700 /tmp/ga3b"
if ($LASTEXITCODE -ne 0) { throw "Remote staging directory creation failed" }

& $pscp -batch -scp -hostkey $HostKey -l $UserName -pw $Password $bitBin $probe "${HostName}:/tmp/ga3b/"
if ($LASTEXITCODE -ne 0) { throw "SCP deployment failed" }

$remote = @'
set -e
cp /tmp/ga3b/ga3b_v1_min.bit.bin /lib/firmware/ga3b_v1_min.bit.bin
if test -L /sys/bus/platform/devices/43c00000.PWM/driver; then
    echo 43c00000.PWM > /sys/bus/platform/drivers/dglnt-pwm/unbind
fi
echo 0 > /sys/class/fpga_manager/fpga0/flags
echo ga3b_v1_min.bit.bin > /sys/class/fpga_manager/fpga0/firmware
sleep 1
echo FPGA_STATE=$(cat /sys/class/fpga_manager/fpga0/state)
chmod 700 /tmp/ga3b/ga3b_reg_probe
/tmp/ga3b/ga3b_reg_probe
'@
& $plink @ssh $remote
if ($LASTEXITCODE -ne 0) { throw "GA3B Linux register probe failed" }
