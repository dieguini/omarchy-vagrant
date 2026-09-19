<#
.SYNOPSIS
    Ejects the Omarchy ISO and the cidata drive from the VM.
.DESCRIPTION
    The Vagrantfile already does this on its own when the first 'vagrant up'
    finishes. This script is for when that step fails, or to clean up by hand:
    the cidata carries your password hash, so it shouldn't stay attached to the
    VM any longer than necessary.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

$cfg  = Get-OmarchyConfig
$vbox = Get-VBoxManage
$vm   = [string] $cfg['vm_name']

# --forceunmount is not optional: Omarchy's desktop auto-mounts both media
# with udiskie, and while the guest has them mounted VirtualBox answers
# VERR_PDM_MEDIA_LOCKED.
$failed = @()
foreach ($port in 1, 2) {
    Write-Host "Emptying SATA port $port of '$vm'..."
    & $vbox storageattach $vm --storagectl SATA --port $port --device 0 `
            --type dvddrive --medium emptydrive --forceunmount
    if ($LASTEXITCODE -ne 0) { $failed += $port }
}

if ($failed.Count -gt 0) {
    throw "Could not eject port(s) $($failed -join ', '). Power the VM off (vagrant halt) and try again."
}

$marker = Join-Path (Get-BuildDir) "installed-$vm"
if (-not (Test-Path $marker)) { New-Item -ItemType File -Path $marker | Out-Null }
Write-Host "Done: both media are out."
