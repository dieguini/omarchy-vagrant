<#
.SYNOPSIS
    Desmonta la ISO de Omarchy y el disco cidata de la VM.
.DESCRIPTION
    El Vagrantfile ya hace esto solo al terminar el primer 'vagrant up'. Este
    script está para el caso en que ese paso falle, o para limpiar a mano: el
    cidata lleva el hash de tu contraseña, así que no conviene dejarlo colgado
    de la VM más tiempo del necesario.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

$cfg  = Get-OmarchyConfig
$vbox = Get-VBoxManage
$vm   = [string] $cfg['vm_name']

foreach ($port in 1, 2) {
    Write-Host "Vaciando SATA puerto $port de '$vm'..."
    Invoke-Native $vbox @('storageattach', $vm, '--storagectl', 'SATA',
                          '--port', "$port", '--device', '0',
                          '--type', 'dvddrive', '--medium', 'emptydrive') -IgnoreExitCode
}

$marker = Join-Path (Get-BuildDir) "installed-$vm"
if (-not (Test-Path $marker)) { New-Item -ItemType File -Path $marker | Out-Null }
Write-Host "Hecho."
