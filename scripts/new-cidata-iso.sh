#!/usr/bin/env bash
# Builds .build/cidata.iso: Omarchy's unattended-install drive.
# The bash twin of New-CidataIso.ps1 -- see that file for the background. The
# files written here must stay identical to the ones it writes; if you change
# the user_configuration.json template, change it in both.
#
# usage: scripts/new-cidata-iso.sh
. "$(dirname "$0")/lib.sh"
load_config

# --- The same checks Omarchy's own setup form makes --------------------------
# (install/provisioning/setup-form.sh in omacom/omarchy)
username="$CFG_username"; hostname="$CFG_hostname"
[[ "$username" =~ ^[a-z_][a-z0-9_-]*\$?$ ]] || die "Invalid username: '$username' (lowercase, must start with a letter or _)"
[[ "$username" =~ ^(root|bin|daemon|mail|ftp|http|nobody|dbus|git|qemu|lp|rpc|sddm)$ ]] && die "Username reserved by the system: '$username'"
[[ "$hostname" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || die "Invalid hostname: '$hostname'"
[ -n "${CFG_password:-}" ] || die "Missing 'password' in config.json / config.local.json"
[ "$CFG_disk_gb" -ge 16 ] || die "disk_gb = $CFG_disk_gb is too small: the ESP alone is 2 GiB. Use 32 or more."

# --- Dedicated SSH key -------------------------------------------------------
key="$(ssh_key_path)"
mkdir -p "$(dirname "$key")"
if [ ! -f "$key" ]; then
    echo "Generating the SSH keypair for the VM..."
    ssh-keygen -q -t ed25519 -N '' -C "vagrant@$hostname" -f "$key"
fi
chmod 600 "$key"

# --- Password hash -----------------------------------------------------------
hash="$("$(openssl_sha512)" passwd -6 "$CFG_password")"
[ -n "$hash" ] || die "openssl passwd -6 failed"

# --- cidata files ------------------------------------------------------------
stage="$BUILD/cidata"
rm -rf "$stage"; mkdir -p "$stage"

# Geometry: the same arithmetic as the configurator, over the exact size of the
# VDI new-empty-box.sh creates (VBoxManage --size is in MiB).
HASH="$hash" STAGE="$stage" CFG_disk_gb="$CFG_disk_gb" CFG_hostname="$CFG_hostname" \
CFG_timezone="$CFG_timezone" CFG_keyboard="$CFG_keyboard" CFG_username="$CFG_username" python3 - <<'PY'
import json, os
mib = 1024 ** 2
disk = int(os.environ["CFG_disk_gb"]) * 1024 ** 3
boot_start, boot_size, gpt_backup = mib, 2 * 1024 ** 3, mib
main_start = boot_size + boot_start
main_size = disk - main_start - gpt_backup
sector = {"unit": "B", "value": 512}
size = lambda v: {"sector_size": sector, "unit": "B", "value": v}

user_configuration = {
    "app_config": None,
    "archinstall-language": "English",
    "auth_config": {},
    "audio_config": {"audio": "pipewire"},
    "bootloader_config": {"bootloader": "Limine", "uki": False, "removable": False},
    "custom_commands": [],
    "omarchy_install": {
        "mode": "full_disk",
        "defer_provisioning": False,
        "target_mount": "/mnt",
        "boot": {"esp_mount": "/boot", "esp_path": "/EFI/limine",
                 "efi_binary": "limine_x64.efi", "enable_fallback": True},
        "storage": {"kernel": "linux-omarchy"},
    },
    "disk_config": {
        "config_type": "default_layout",
        "device_modifications": [{
            "device": "/dev/sda",
            "partitions": [
                {"btrfs": [], "dev_path": None, "flags": ["boot", "esp"], "fs_type": "fat32",
                 "mount_options": [], "mountpoint": "/boot",
                 "obj_id": "ea21d3f2-82bb-49cc-ab5d-6f81ae94e18d",
                 "size": size(boot_size), "start": size(boot_start), "status": "create", "type": "primary"},
                {"btrfs": [{"mountpoint": "/", "name": "@"}, {"mountpoint": "/home", "name": "@home"},
                           {"mountpoint": "/var/log", "name": "@log"},
                           {"mountpoint": "/var/cache/pacman/pkg", "name": "@pkg"}],
                 "dev_path": None, "flags": [], "fs_type": "btrfs", "mount_options": ["compress=zstd"],
                 "mountpoint": None, "obj_id": "8c2c2b92-1070-455d-b76a-56263bab24aa",
                 "size": size(main_size), "start": size(main_start), "status": "create", "type": "primary"},
            ],
            "wipe": True,
        }],
    },
    "hostname": os.environ["CFG_hostname"],
    "kernels": ["linux-omarchy"],
    "network_config": {"type": "iso"},
    "ntp": True,
    "parallel_downloads": 8,
    "script": None,
    "services": [],
    "swap": True,
    "timezone": os.environ["CFG_timezone"],
    "locale_config": {"kb_layout": os.environ["CFG_keyboard"], "sys_enc": "UTF-8", "sys_lang": "en_US.UTF-8"},
    "mirror_config": {
        "custom_repositories": [],
        "custom_servers": [{"url": "https://mirror.omarchy.org/$repo/os/$arch"},
                           {"url": "https://mirror.rackspace.com/archlinux/$repo/os/$arch"},
                           {"url": "https://geo.mirror.pkgbuild.com/$repo/os/$arch"}],
        "mirror_regions": {},
        "optional_repositories": [],
    },
    "packages": ["base-devel", "git", "omarchy-keyring", "omarchy-settings", "omarchy"],
    "profile_config": {"gfx_driver": None, "greeter": None, "profile": {}},
    "version": "3.0.9",
}
h, user = os.environ["HASH"], os.environ["CFG_username"]
user_credentials = {"root_enc_password": h,
                    "users": [{"enc_password": h, "groups": [], "sudo": True, "username": user}]}

stage = os.environ["STAGE"]
def write(name, text):  # UTF-8, no BOM, LF: bash inside the ISO reads these
    with open(os.path.join(stage, name), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
write("user_configuration.json", json.dumps(user_configuration, indent=4) + "\n")
write("user_credentials.json", json.dumps(user_credentials, indent=4) + "\n")
write("user_encrypt_installation.txt", "false\n")
PY

cp "$key.pub" "$stage/authorized_keys"
[ -n "${CFG_full_name:-}" ]     && printf '%s\n' "$CFG_full_name"     > "$stage/user_full_name.txt"
[ -n "${CFG_email_address:-}" ] && printf '%s\n' "$CFG_email_address" > "$stage/user_email_address.txt"

# --- Packaging ---------------------------------------------------------------
out="$(cidata_path)"
make_iso "$stage" cidata "$out"

echo "cidata ready: $out"
echo "  user : $username"
echo "  disk : /dev/sda, $CFG_disk_gb GiB, unencrypted"
echo "  key  : $key"
