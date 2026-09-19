<#
.SYNOPSIS
    Builds .build\cidata.iso: Omarchy's unattended-install drive.
.DESCRIPTION
    At boot, the Omarchy installer looks for a drive labeled `cidata`
    (cloud-init's NoCloud label). If it finds one, it copies off the files the
    setup wizard would otherwise write, skips the wizard entirely and installs
    on its own.

    The files written here are the same ones the ISO's configurator writes: the
    user_configuration.json template comes from omacom/omarchy-iso,
    configs/airootfs/root/configurator.

    It also generates the SSH keypair Vagrant will use to reach the VM: with
    authorized_keys present, the installer enables sshd and opens the firewall
    (something a stock Omarchy install does not do).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

$cfg   = Get-OmarchyConfig
$build = Get-BuildDir

# --- The same checks Omarchy's own setup form makes --------------------------
# (install/provisioning/setup-form.sh in omacom/omarchy)
$username = [string] $cfg['username']
$hostname = [string] $cfg['hostname']
if ($username -notmatch '^[a-z_][a-z0-9_-]*\$?$') {
    throw "Invalid username: '$username' (lowercase, must start with a letter or _)"
}
if ($username -match '^(root|bin|daemon|mail|ftp|http|nobody|dbus|git|qemu|lp|rpc|sddm)$') {
    throw "Username reserved by the system: '$username'"
}
if ($hostname -notmatch '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') {
    throw "Invalid hostname: '$hostname'"
}
if (-not $cfg['password']) {
    throw "Missing 'password' in config.json / config.local.json"
}
if ([int] $cfg['disk_gb'] -lt 16) {
    throw "disk_gb = $($cfg['disk_gb']) is too small: the ESP alone is 2 GiB. Use 32 or more."
}

# --- Dedicated SSH key -------------------------------------------------------
$keyPath = Get-SshKeyPath
$keyDir  = Split-Path -Parent $keyPath
if (-not (Test-Path $keyDir)) { New-Item -ItemType Directory -Path $keyDir | Out-Null }
if (-not (Test-Path $keyPath)) {
    Write-Host "Generating the SSH keypair for the VM..."
    Invoke-Native -FilePath 'ssh-keygen.exe' -Arguments @(
        '-t', 'ed25519', '-N', '', '-C', "vagrant@$hostname", '-f', $keyPath
    )
}
$authorizedKey = (Get-Content "$keyPath.pub" -Raw).Trim()

# --- Password hash -----------------------------------------------------------
$openssl = Get-OpenSsl
$passwordHash = (& $openssl passwd -6 ([string] $cfg['password'])).Trim()
if ($LASTEXITCODE -ne 0 -or -not $passwordHash) { throw "openssl passwd -6 failed" }

# --- Disk geometry -----------------------------------------------------------
# The same arithmetic the configurator does, over the exact size of the VDI
# New-EmptyBox.ps1 creates (VBoxManage --size is in MiB).
[long] $mib  = 1MB
[long] $disk = [long] $cfg['disk_gb'] * 1GB
[long] $gptBackupReserve   = $mib
[long] $bootPartitionStart = $mib
[long] $bootPartitionSize  = 2GB
[long] $mainPartitionStart = $bootPartitionSize + $bootPartitionStart
[long] $mainPartitionSize  = $disk - $mainPartitionStart - $gptBackupReserve

# --- cidata files ------------------------------------------------------------
$stage = Join-Path $build 'cidata'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

# Written without BOM and with LF endings: bash inside the ISO reads these.
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

# --- Packaging ---------------------------------------------------------------
$out = Get-CidataPath
if (Test-Path $out) { Remove-Item $out -Force }
New-IsoImage -SourceDir $stage -Label 'cidata' -OutFile $out

Write-Host "cidata ready: $out"
Write-Host "  user : $username"
Write-Host "  disk : /dev/sda, $($cfg['disk_gb']) GiB, unencrypted"
Write-Host "  key  : $keyPath"
