#!/usr/bin/env bash
# Prepares everything 'vagrant up' needs: ISO, cidata, keys and base box.
# The macOS (Intel) and Linux twin of bootstrap.ps1 -- same steps, same
# artifacts in .build/, so the one Vagrantfile serves every host.
#
#   ./bootstrap.sh
#   vagrant up
#
#   # Rebuild cidata and box after editing config.local.json, without re-downloading the ISO
#   ./bootstrap.sh --skip-iso --force
. "$(dirname "$0")/scripts/lib.sh"

skip_iso=0; force=""
for arg in "$@"; do
    case "$arg" in
        --skip-iso) skip_iso=1 ;;
        --force)    force=--force ;;
        -h|--help)  sed -n '2,10p' "$0"; exit 0 ;;
        *)          die "Unknown option: $arg (use --skip-iso, --force)" ;;
    esac
done

echo "== Checking tools =="
check_host
vbox="$(vboxmanage)"
echo "  VBoxManage : $vbox ($("$vbox" --version))"
need vagrant "Install it from https://developer.hashicorp.com/vagrant"
echo "  Vagrant    : $(vagrant --version)"
need curl ""
need ssh-keygen ""
echo "  openssl    : $(openssl_sha512)"
echo "  python3    : $(command -v python3 || echo missing)"

load_config
echo ""
echo "== Configuration =="
echo "  Omarchy $CFG_omarchy_version -> $CFG_vm_name ($CFG_cpus vCPU, $CFG_memory_mb MB RAM, $CFG_disk_gb GB disk)"
[ "$CFG_password" = omarchy ] && \
    warn "You are using the default password. Set another one in config.local.json unless this VM is disposable."

echo ""
if [ "$skip_iso" = 0 ]; then
    echo "== Omarchy ISO =="
    "$ROOT/scripts/get-omarchy-iso.sh"
else
    echo "== Omarchy ISO (skipped) =="
fi

echo ""
echo "== Unattended-install drive (cidata) =="
"$ROOT/scripts/new-cidata-iso.sh"

echo ""
echo "== Base Vagrant box =="
"$ROOT/scripts/new-empty-box.sh" $force

echo ""
echo "Done. Now run:  vagrant up"
echo "The VM boots the ISO, installs on its own and reboots; Vagrant waits for SSH."
