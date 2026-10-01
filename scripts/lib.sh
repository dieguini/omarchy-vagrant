# Helpers shared by the bootstrap scripts on macOS and Linux hosts.
# The bash twin of lib.ps1; load with: . "$(dirname "$0")/lib.sh"

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build"
mkdir -p "$BUILD"

die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }

# Omarchy only ships an x86_64 ISO. VirtualBox on Apple Silicon runs ARM guests
# only, so an M-series Mac cannot run this at any speed -- say so up front
# instead of failing half an hour into a 6 GB download.
check_host() {
    case "$(uname -s)/$(uname -m)" in
        Darwin/x86_64|Linux/x86_64) ;;
        Darwin/arm64)
            die "Apple Silicon Mac detected. Omarchy is x86_64-only and VirtualBox on
       Apple Silicon only runs ARM guests, so this VM cannot run here.
       Use an Intel Mac, a Linux or Windows x86_64 host." ;;
        *) die "Unsupported host: $(uname -s) $(uname -m). Needs an x86_64 macOS or Linux host." ;;
    esac
}

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required. $2"; }

# config.json holds the defaults; config.local.json (gitignored) overrides the
# keys it declares. Exported as CFG_<key> shell variables, safely quoted.
load_config() {
    need python3 "macOS: xcode-select --install   Linux: install python3 with your package manager."
    eval "$(python3 - "$ROOT" <<'PY'
import json, os, shlex, sys
root = sys.argv[1]
cfg = json.load(open(os.path.join(root, "config.json")))
local = os.path.join(root, "config.local.json")
if os.path.exists(local):
    cfg.update(json.load(open(local)))
if not cfg.get("iso_url"):
    cfg["iso_url"] = f"https://iso.omarchy.org/omarchy-{cfg['omarchy_version']}.iso"
for k, v in cfg.items():
    if not k.isidentifier():  # "//" comment keys document the file; they aren't settings
        continue
    if isinstance(v, (dict, list)):
        v = json.dumps(v)
    elif v is None:
        v = ""
    elif isinstance(v, bool):
        v = "true" if v else "false"
    print(f"CFG_{k}={shlex.quote(str(v))}")
PY
)"
}

iso_path()    { echo "$BUILD/omarchy-$CFG_omarchy_version.iso"; }
cidata_path() { echo "$BUILD/cidata.iso"; }
ssh_key_path(){ echo "$BUILD/ssh/id_ed25519"; }
box_name()    { echo "omarchy-empty-${CFG_disk_gb}g"; }

vboxmanage() {
    local c
    for c in "$(command -v VBoxManage 2>/dev/null || true)" \
             /usr/local/bin/VBoxManage /usr/bin/VBoxManage \
             /Applications/VirtualBox.app/Contents/MacOS/VBoxManage; do
        [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return; }
    done
    die "Cannot find VBoxManage. Install VirtualBox 7 from https://www.virtualbox.org/"
}

# The password goes into the cidata as a SHA-512 crypt hash. macOS's own
# /usr/bin/openssl is LibreSSL, whose 'passwd' has no -6, so look for a real
# OpenSSL (Homebrew's openssl@3) when the first one can't do it.
openssl_sha512() {
    local c
    for c in "$(command -v openssl 2>/dev/null || true)" \
             /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/opt/openssl@3/bin/openssl; do
        [ -n "$c" ] && [ -x "$c" ] && "$c" passwd -6 probe >/dev/null 2>&1 && { echo "$c"; return; }
    done
    die "No openssl that supports 'passwd -6' (SHA-512). macOS ships LibreSSL, which doesn't:
       brew install openssl@3"
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# ISO9660 + Joliet with the given volume label. The Linux kernel reads long
# filenames from Joliet, which is what Omarchy's installer needs to find
# user_configuration.json -- the same image IMAPI2 builds on Windows.
make_iso() {
    local src=$1 label=$2 out=$3
    rm -f "$out"
    if [ "$(uname -s)" = Darwin ]; then
        hdiutil makehybrid -quiet -iso -joliet \
            -iso-volume-name "$label" -joliet-volume-name "$label" -default-volume-name "$label" \
            -o "$out" "$src"
    elif command -v xorriso >/dev/null 2>&1; then
        xorriso -as mkisofs -quiet -J -r -V "$label" -o "$out" "$src"
    elif command -v genisoimage >/dev/null 2>&1; then
        genisoimage -quiet -J -r -V "$label" -o "$out" "$src"
    elif command -v mkisofs >/dev/null 2>&1; then
        mkisofs -quiet -J -r -V "$label" -o "$out" "$src"
    else
        die "No ISO builder found. Install xorriso (or genisoimage) with your package manager."
    fi
    [ -s "$out" ] || die "ISO build produced nothing: $out"
}
