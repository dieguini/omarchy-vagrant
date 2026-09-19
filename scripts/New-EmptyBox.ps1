<#
.SYNOPSIS
    Construye y registra la caja Vagrant vacía sobre la que se instala Omarchy.
.DESCRIPTION
    No existe una caja de Omarchy: el sistema se instala desde la ISO. Pero
    Vagrant necesita una caja para arrancar, así que fabricamos una: una VM con
    firmware EFI, controladora SATA y un disco virgen, exportada a .box.

    El truco es el mismo que documenta el manual de Omarchy para Proxmox: el
    orden de arranque pone el disco primero, el disco vacío no arranca nada y
    cae al DVD; ya instalado, arranca del disco y la ISO deja de importar.

    El tamaño del disco queda grabado en la caja, así que la caja se llama
    omarchy-empty-<N>g. Cambiar disk_gb en config.json genera otra caja.
#>
[CmdletBinding()]
param([switch] $Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

$cfg     = Get-OmarchyConfig
$vbox    = Get-VBoxManage
$boxName = Get-BoxName $cfg
$diskMib = [long] $cfg['disk_gb'] * 1024

$existing = & vagrant box list 2>$null
if (-not $Force -and $existing -and ($existing | Select-String -SimpleMatch "$boxName ")) {
    Write-Host "La caja '$boxName' ya está registrada. Usa -Force para regenerarla."
    return
}

$work    = Join-Path (Get-BuildDir) 'boxbuild'
$vmName  = "$boxName-builder"
$export  = Join-Path $work 'export'
$boxFile = Join-Path (Get-BuildDir) "$boxName.box"

# Una corrida anterior interrumpida deja la VM registrada; quítala antes.
& $vbox unregistervm $vmName --delete 2>$null | Out-Null
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Path $work   | Out-Null
New-Item -ItemType Directory -Path $export | Out-Null

try {
    Write-Host "Creando la VM plantilla ($diskMib MiB de disco, firmware EFI)..."
    Invoke-Native $vbox @('createvm', '--name', $vmName, '--ostype', 'ArchLinux_64',
                          '--basefolder', $work, '--register')

    Invoke-Native $vbox @('modifyvm', $vmName,
        '--firmware', 'efi',
        '--memory', '4096', '--cpus', '2',
        '--ioapic', 'on', '--rtcuseutc', 'on',
        '--graphicscontroller', 'vmsvga', '--vram', '128',
        '--nic1', 'nat')

    # portcount 4: puerto 0 el disco, 1 la ISO de Omarchy, 2 el cidata.
    Invoke-Native $vbox @('storagectl', $vmName, '--name', 'SATA', '--add', 'sata',
                          '--controller', 'IntelAhci', '--portcount', '4', '--bootable', 'on')

    $vdi = Join-Path $work "$boxName.vdi"
    Invoke-Native $vbox @('createmedium', 'disk', '--filename', $vdi,
                          '--size', "$diskMib", '--format', 'VDI', '--variant', 'Standard')
    Invoke-Native $vbox @('storageattach', $vmName, '--storagectl', 'SATA',
                          '--port', '0', '--device', '0', '--type', 'hdd', '--medium', $vdi)

    Write-Host "Exportando a OVF..."
    $ovf = Join-Path $export 'box.ovf'
    Invoke-Native $vbox @('export', $vmName, '--output', $ovf)

    # Formato de caja Vagrant: un tar con metadata.json, el .ovf y sus discos.
    [IO.File]::WriteAllText(
        (Join-Path $export 'metadata.json'),
        '{"provider":"virtualbox"}',
        (New-Object Text.UTF8Encoding $false))

    Write-Host "Empaquetando $boxFile..."
    if (Test-Path $boxFile) { Remove-Item $boxFile -Force }
    Invoke-Native 'tar.exe' @('-cf', $boxFile, '-C', $export, '.')

    Write-Host "Registrando la caja '$boxName' en Vagrant..."
    Invoke-Native 'vagrant' @('box', 'add', '--name', $boxName, '--force', $boxFile)
}
finally {
    & $vbox unregistervm $vmName --delete 2>$null | Out-Null
    if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "Caja lista: $boxName"
