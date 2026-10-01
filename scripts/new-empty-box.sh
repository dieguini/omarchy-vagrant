#!/usr/bin/env bash
# Builds and registers the empty Vagrant box Omarchy gets installed onto.
# The bash twin of New-EmptyBox.ps1: a VM with EFI firmware, a SATA controller
# and a blank disk, exported to .box. The disk size is baked into the box, so
# it is named omarchy-empty-<N>g.
#
# usage: scripts/new-empty-box.sh [--force]
. "$(dirname "$0")/lib.sh"
load_config

force=0; [ "${1:-}" = --force ] && force=1
vbox="$(vboxmanage)"
box="$(box_name)"
disk_mib=$(( CFG_disk_gb * 1024 ))

if [ "$force" = 0 ] && vagrant box list 2>/dev/null | grep -q "^$box "; then
    echo "Box '$box' is already registered. Use --force to rebuild it."
    exit 0
fi

work="$BUILD/boxbuild"
vm="$box-builder"
export_dir="$work/export"
box_file="$BUILD/$box.box"

cleanup() {
    "$vbox" unregistervm "$vm" --delete >/dev/null 2>&1 || true
    rm -rf "$work"
}
# An interrupted earlier run leaves the VM registered; remove it first.
cleanup
trap cleanup EXIT
mkdir -p "$export_dir"

echo "Creating the template VM ($disk_mib MiB disk, EFI firmware)..."
"$vbox" createvm --name "$vm" --ostype ArchLinux_64 --basefolder "$work" --register >/dev/null
"$vbox" modifyvm "$vm" --firmware efi --memory 4096 --cpus 2 --ioapic on --rtcuseutc on \
    --graphicscontroller vmsvga --vram 128 --nic1 nat

# portcount 4: port 0 the disk, 1 the Omarchy ISO, 2 the cidata.
"$vbox" storagectl "$vm" --name SATA --add sata --controller IntelAhci --portcount 4 --bootable on

vdi="$work/$box.vdi"
"$vbox" createmedium disk --filename "$vdi" --size "$disk_mib" --format VDI --variant Standard >/dev/null
"$vbox" storageattach "$vm" --storagectl SATA --port 0 --device 0 --type hdd --medium "$vdi"

echo "Exporting to OVF..."
"$vbox" export "$vm" --output "$export_dir/box.ovf"

# Vagrant box format: a tar holding metadata.json, the .ovf and its disks.
printf '%s' '{"provider":"virtualbox"}' > "$export_dir/metadata.json"

echo "Packaging $box_file..."
rm -f "$box_file"
tar -cf "$box_file" -C "$export_dir" .

echo "Registering box '$box' with Vagrant..."
vagrant box add --name "$box" --force "$box_file"

echo "Box ready: $box"
