<#
.SYNOPSIS
    Builds and registers the empty Vagrant box Omarchy gets installed onto.
.DESCRIPTION
    There is no Omarchy box: the system installs from an ISO. But Vagrant needs
    a box to boot, so we make one: a VM with EFI firmware, a SATA controller
    and a blank disk, exported to .box.

    The trick is the one Omarchy's manual documents for Proxmox: the boot order
    puts the disk first, the empty disk boots nothing and falls through to the
    DVD; once installed it boots from disk and the ISO stops mattering.

    The disk size is baked into the box, so the box is named
    omarchy-empty-<N>g. Changing disk_gb in config.json produces another box.
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
    Write-Host "Box '$boxName' is already registered. Use -Force to rebuild it."
    return
}

$work    = Join-Path (Get-BuildDir) 'boxbuild'
$vmName  = "$boxName-builder"
$export  = Join-Path $work 'export'
$boxFile = Join-Path (Get-BuildDir) "$boxName.box"

# An interrupted earlier run leaves the VM registered; remove it first.
& $vbox unregistervm $vmName --delete 2>$null | Out-Null
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Path $work   | Out-Null
New-Item -ItemType Directory -Path $export | Out-Null

try {
    Write-Host "Creating the template VM ($diskMib MiB disk, EFI firmware)..."
    Invoke-Native $vbox @('createvm', '--name', $vmName, '--ostype', 'ArchLinux_64',
                          '--basefolder', $work, '--register')

    Invoke-Native $vbox @('modifyvm', $vmName,
        '--firmware', 'efi',
        '--memory', '4096', '--cpus', '2',
        '--ioapic', 'on', '--rtcuseutc', 'on',
        '--graphicscontroller', 'vmsvga', '--vram', '128',
        '--nic1', 'nat')

    # portcount 4: port 0 the disk, 1 the Omarchy ISO, 2 the cidata.
    Invoke-Native $vbox @('storagectl', $vmName, '--name', 'SATA', '--add', 'sata',
                          '--controller', 'IntelAhci', '--portcount', '4', '--bootable', 'on')

    $vdi = Join-Path $work "$boxName.vdi"
    Invoke-Native $vbox @('createmedium', 'disk', '--filename', $vdi,
                          '--size', "$diskMib", '--format', 'VDI', '--variant', 'Standard')
    Invoke-Native $vbox @('storageattach', $vmName, '--storagectl', 'SATA',
                          '--port', '0', '--device', '0', '--type', 'hdd', '--medium', $vdi)

    Write-Host "Exporting to OVF..."
    $ovf = Join-Path $export 'box.ovf'
    Invoke-Native $vbox @('export', $vmName, '--output', $ovf)

    # Vagrant box format: a tar holding metadata.json, the .ovf and its disks.
    [IO.File]::WriteAllText(
        (Join-Path $export 'metadata.json'),
        '{"provider":"virtualbox"}',
        (New-Object Text.UTF8Encoding $false))

    Write-Host "Packaging $boxFile..."
    if (Test-Path $boxFile) { Remove-Item $boxFile -Force }
    Invoke-Native 'tar.exe' @('-cf', $boxFile, '-C', $export, '.')

    Write-Host "Registering box '$boxName' with Vagrant..."
    Invoke-Native 'vagrant' @('box', 'add', '--name', $boxName, '--force', $boxFile)
}
finally {
    & $vbox unregistervm $vmName --delete 2>$null | Out-Null
    if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "Box ready: $boxName"
