<#
.SYNOPSIS
    Genera .build\cidata.iso: el disco de autoinstalación de Omarchy.
.DESCRIPTION
    El instalador de la ISO de Omarchy busca al arrancar un disco etiquetado
    `cidata` (la etiqueta NoCloud de cloud-init). Si lo encuentra, copia de ahí
    los archivos que normalmente escribe el asistente, se salta el asistente
    entero e instala solo.

    Los archivos que dejamos son los mismos que escribe el configurador de la
    ISO: la plantilla de user_configuration.json viene de
    omacom/omarchy-iso, configs/airootfs/root/configurator.

    De paso genera el par de llaves SSH con el que Vagrant entrará a la VM:
    con authorized_keys presente, el instalador habilita sshd y abre el
    firewall (algo que una instalación normal de Omarchy no hace).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

$cfg   = Get-OmarchyConfig
$build = Get-BuildDir

# --- Validaciones que hace el propio formulario de Omarchy -------------------
# (install/provisioning/setup-form.sh en omacom/omarchy)
$username = [string] $cfg['username']
$hostname = [string] $cfg['hostname']
if ($username -notmatch '^[a-z_][a-z0-9_-]*\$?$') {
    throw "username inválido: '$username' (minúsculas, empieza por letra o _)"
}
if ($username -match '^(root|bin|daemon|mail|ftp|http|nobody|dbus|git|qemu|lp|rpc|sddm)$') {
    throw "username reservado por el sistema: '$username'"
}
if ($hostname -notmatch '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') {
    throw "hostname inválido: '$hostname'"
}
if (-not $cfg['password']) {
    throw "Falta 'password' en config.json / config.local.json"
}
if ([int] $cfg['disk_gb'] -lt 16) {
    throw "disk_gb = $($cfg['disk_gb']) es muy chico: la ESP sola son 2 GiB. Usa 32 o más."
}

# --- Llave SSH dedicada ------------------------------------------------------
$keyPath = Get-SshKeyPath
$keyDir  = Split-Path -Parent $keyPath
if (-not (Test-Path $keyDir)) { New-Item -ItemType Directory -Path $keyDir | Out-Null }
if (-not (Test-Path $keyPath)) {
    Write-Host "Generando par de llaves SSH para la VM..."
    Invoke-Native -FilePath 'ssh-keygen.exe' -Arguments @(
        '-t', 'ed25519', '-N', '', '-C', "vagrant@$hostname", '-f', $keyPath
    )
}
$authorizedKey = (Get-Content "$keyPath.pub" -Raw).Trim()

# --- Hash de la contraseña ---------------------------------------------------
$openssl = Get-OpenSsl
$passwordHash = (& $openssl passwd -6 ([string] $cfg['password'])).Trim()
if ($LASTEXITCODE -ne 0 -or -not $passwordHash) { throw "openssl passwd -6 falló" }

# --- Geometría del disco -----------------------------------------------------
# Mismo cálculo que el configurador, sobre el tamaño exacto del VDI que crea
# New-EmptyBox.ps1 (VBoxManage --size usa MiB).
[long] $mib  = 1MB
[long] $disk = [long] $cfg['disk_gb'] * 1GB
[long] $gptBackupReserve   = $mib
[long] $bootPartitionStart = $mib
[long] $bootPartitionSize  = 2GB
[long] $mainPartitionStart = $bootPartitionSize + $bootPartitionStart
[long] $mainPartitionSize  = $disk - $mainPartitionStart - $gptBackupReserve

# --- Archivos de cidata ------------------------------------------------------
$stage = Join-Path $build 'cidata'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

# Escribe sin BOM y con saltos LF: los lee bash dentro de la ISO.
function Write-CidataFile {
    param([string] $Name, [string] $Content)
    $path = Join-Path $stage $Name
    [IO.File]::WriteAllText($path, ($Content -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
}

$userConfiguration = @"
{
    "app_config": null,
    "archinstall-language": "English",
    "auth_config": {},
    "audio_config": { "audio": "pipewire" },
    "bootloader_config": { "bootloader": "Limine", "uki": false, "removable": false },
    "custom_commands": [],
    "omarchy_install": {
        "mode": "full_disk",
        "defer_provisioning": false,
        "target_mount": "/mnt",
        "boot": {
            "esp_mount": "/boot",
            "esp_path": "/EFI/limine",
            "efi_binary": "limine_x64.efi",
            "enable_fallback": true
        },
        "storage": {
            "kernel": "linux-omarchy"
        }
    },
    "disk_config": {
        "config_type": "default_layout",
        "device_modifications": [
            {
                "device": "/dev/sda",
                "partitions": [
                    {
                        "btrfs": [],
                        "dev_path": null,
                        "flags": [ "boot", "esp" ],
                        "fs_type": "fat32",
                        "mount_options": [],
                        "mountpoint": "/boot",
                        "obj_id": "ea21d3f2-82bb-49cc-ab5d-6f81ae94e18d",
                        "size": {
                            "sector_size": { "unit": "B", "value": 512 },
                            "unit": "B",
                            "value": $bootPartitionSize
                        },
                        "start": {
                            "sector_size": { "unit": "B", "value": 512 },
                            "unit": "B",
                            "value": $bootPartitionStart
                        },
                        "status": "create",
                        "type": "primary"
                    },
                    {
                        "btrfs": [
                            { "mountpoint": "/", "name": "@" },
                            { "mountpoint": "/home", "name": "@home" },
                            { "mountpoint": "/var/log", "name": "@log" },
                            { "mountpoint": "/var/cache/pacman/pkg", "name": "@pkg" }
                        ],
                        "dev_path": null,
                        "flags": [],
                        "fs_type": "btrfs",
                        "mount_options": [ "compress=zstd" ],
                        "mountpoint": null,
                        "obj_id": "8c2c2b92-1070-455d-b76a-56263bab24aa",
                        "size": {
                            "sector_size": { "unit": "B", "value": 512 },
                            "unit": "B",
                            "value": $mainPartitionSize
                        },
                        "start": {
                            "sector_size": { "unit": "B", "value": 512 },
                            "unit": "B",
                            "value": $mainPartitionStart
                        },
                        "status": "create",
                        "type": "primary"
                    }
                ],
                "wipe": true
            }
        ]
    },
    "hostname": "$hostname",
    "kernels": [ "linux-omarchy" ],
    "network_config": { "type": "iso" },
    "ntp": true,
    "parallel_downloads": 8,
    "script": null,
    "services": [],
    "swap": true,
    "timezone": "$($cfg['timezone'])",
    "locale_config": {
        "kb_layout": "$($cfg['keyboard'])",
        "sys_enc": "UTF-8",
        "sys_lang": "en_US.UTF-8"
    },
    "mirror_config": {
        "custom_repositories": [],
        "custom_servers": [
            {"url": "https://mirror.omarchy.org/`$repo/os/`$arch"},
            {"url": "https://mirror.rackspace.com/archlinux/`$repo/os/`$arch"},
            {"url": "https://geo.mirror.pkgbuild.com/`$repo/os/`$arch"}
        ],
        "mirror_regions": {},
        "optional_repositories": []
    },
    "packages": [
        "base-devel",
        "git",
        "omarchy-keyring",
        "omarchy-settings",
        "omarchy"
    ],
    "profile_config": {
        "gfx_driver": null,
        "greeter": null,
        "profile": {}
    },
    "version": "3.0.9"
}
"@

$jsonHash = ConvertTo-Json $passwordHash -Compress
$jsonUser = ConvertTo-Json $username     -Compress

$userCredentials = @"
{
    "root_enc_password": $jsonHash,
    "users": [
        {
            "enc_password": $jsonHash,
            "groups": [],
            "sudo": true,
            "username": $jsonUser
        }
    ]
}
"@

Write-CidataFile 'user_configuration.json'       $userConfiguration
Write-CidataFile 'user_credentials.json'         $userCredentials
Write-CidataFile 'user_encrypt_installation.txt' "false`n"
Write-CidataFile 'authorized_keys'               "$authorizedKey`n"
if ($cfg['full_name'])     { Write-CidataFile 'user_full_name.txt'     "$($cfg['full_name'])`n" }
if ($cfg['email_address']) { Write-CidataFile 'user_email_address.txt' "$($cfg['email_address'])`n" }

# --- Empaquetado -------------------------------------------------------------
$out = Get-CidataPath
if (Test-Path $out) { Remove-Item $out -Force }
New-IsoImage -SourceDir $stage -Label 'cidata' -OutFile $out

Write-Host "cidata listo: $out"
Write-Host "  usuario : $username"
Write-Host "  disco   : /dev/sda, $($cfg['disk_gb']) GiB, sin cifrado"
Write-Host "  llave   : $keyPath"
