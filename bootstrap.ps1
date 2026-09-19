<#
.SYNOPSIS
    Prepares everything 'vagrant up' needs: ISO, cidata, keys and base box.
.EXAMPLE
    .\bootstrap.ps1
    vagrant up
.EXAMPLE
    # Rebuild cidata and box after editing config.local.json, without re-downloading the ISO
    .\bootstrap.ps1 -SkipIso -Force
#>
[CmdletBinding()]
param(
    [switch] $SkipIso,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\scripts\lib.ps1"

Write-Host "== Checking tools =="
$vbox = Get-VBoxManage
Write-Host "  VBoxManage : $vbox ($(& $vbox --version))"
if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) {
    throw "Vagrant is not on PATH. Install it from https://developer.hashicorp.com/vagrant"
}
Write-Host "  Vagrant    : $(vagrant --version)"
Write-Host "  openssl    : $(Get-OpenSsl)"

$cfg = Get-OmarchyConfig
Write-Host ""
Write-Host "== Configuration =="
Write-Host "  Omarchy $($cfg['omarchy_version']) -> $($cfg['vm_name']) ($($cfg['cpus']) vCPU, $($cfg['memory_mb']) MB RAM, $($cfg['disk_gb']) GB disk)"
if ($cfg['password'] -eq 'omarchy') {
    Write-Warning "You are using the default password. Set another one in config.local.json unless this VM is disposable."
}

if (-not $SkipIso) {
    Write-Host ""
    Write-Host "== Omarchy ISO =="
    & "$PSScriptRoot\scripts\Get-OmarchyIso.ps1"
} else {
    Write-Host ""
    Write-Host "== Omarchy ISO (skipped) =="
}

Write-Host ""
Write-Host "== Unattended-install drive (cidata) =="
& "$PSScriptRoot\scripts\New-CidataIso.ps1"

Write-Host ""
Write-Host "== Base Vagrant box =="
& "$PSScriptRoot\scripts\New-EmptyBox.ps1" -Force:$Force

Write-Host ""
Write-Host "Done. Now run:  vagrant up"
Write-Host "The VM boots the ISO, installs on its own and reboots; Vagrant waits for SSH."
