#!/usr/bin/env bash
# Ejects the Omarchy ISO and the cidata drive from the VM.
# The bash twin of Eject-InstallMedia.ps1. The Vagrantfile already does this
# when the first 'vagrant up' finishes; this is for when that step fails. The
# cidata carries your password hash, so it shouldn't stay attached.
#
# usage: scripts/eject-install-media.sh
. "$(dirname "$0")/lib.sh"
load_config

vbox="$(vboxmanage)"
vm="$CFG_vm_name"

# --forceunmount is not optional: Omarchy's desktop auto-mounts both media with
# udiskie, and while the guest has them mounted VirtualBox answers
# VERR_PDM_MEDIA_LOCKED.
failed=""
for port in 1 2; do
    echo "Emptying SATA port $port of '$vm'..."
    "$vbox" storageattach "$vm" --storagectl SATA --port "$port" --device 0 \
        --type dvddrive --medium emptydrive --forceunmount || failed="$failed $port"
done

[ -z "$failed" ] || die "Could not eject port(s)$failed. Power the VM off (vagrant halt) and try again."

touch "$BUILD/installed-$vm"
echo "Done: both media are out."
