<#
.SYNOPSIS
    Prepara todo lo que 'vagrant up' necesita: ISO, cidata, llaves y caja base.
.EXAMPLE
    .\bootstrap.ps1
    vagrant up
.EXAMPLE
    # Regenerar cidata y caja tras tocar config.local.json, sin rebajar la ISO
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

Write-Host "== Comprobando herramientas =="
$vbox = Get-VBoxManage
Write-Host "  VBoxManage : $vbox ($(& $vbox --version))"
if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) {
    throw "Vagrant no está en el PATH. Instálalo desde https://developer.hashicorp.com/vagrant"
}
Write-Host "  Vagrant    : $(vagrant --version)"
Write-Host "  openssl    : $(Get-OpenSsl)"

$cfg = Get-OmarchyConfig
Write-Host ""
Write-Host "== Configuración =="
Write-Host "  Omarchy $($cfg['omarchy_version']) -> $($cfg['vm_name']) ($($cfg['cpus']) vCPU, $($cfg['memory_mb']) MB RAM, $($cfg['disk_gb']) GB disco)"
if ($cfg['password'] -eq 'omarchy') {
    Write-Warning "Estás usando la contraseña por defecto. Ponle otra en config.local.json si la VM no es desechable."
}

if (-not $SkipIso) {
    Write-Host ""
    Write-Host "== ISO de Omarchy =="
    & "$PSScriptRoot\scripts\Get-OmarchyIso.ps1"
} else {
    Write-Host ""
    Write-Host "== ISO de Omarchy (omitida) =="
}

Write-Host ""
Write-Host "== Disco de autoinstalación (cidata) =="
& "$PSScriptRoot\scripts\New-CidataIso.ps1"

Write-Host ""
Write-Host "== Caja Vagrant base =="
& "$PSScriptRoot\scripts\New-EmptyBox.ps1" -Force:$Force

Write-Host ""
Write-Host "Listo. Ahora:  vagrant up"
Write-Host "La VM arranca de la ISO, instala sola y reinicia; Vagrant espera por SSH."
