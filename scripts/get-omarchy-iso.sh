#!/usr/bin/env bash
# Downloads the official Omarchy ISO into .build/ and verifies its SHA-256.
# The bash twin of Get-OmarchyIso.ps1. The download resumes (curl -C -), so a
# dropped connection doesn't mean starting the ~6 GB over; if the file is
# already there and the hash matches, it does nothing.
#
# usage: scripts/get-omarchy-iso.sh [--force]
. "$(dirname "$0")/lib.sh"
load_config

force=0; [ "${1:-}" = --force ] && force=1
iso="$(iso_path)"
url="$CFG_iso_url"

# The hash published next to the ISO, unless config.json pins one.
expected="${CFG_iso_sha256:-}"
if [ -z "$expected" ]; then
    echo "Fetching the published SHA-256 from $url.sha256"
    expected="$(curl --location --fail --silent --show-error "$url.sha256" | awk '{print $1; exit}')"
fi
expected="$(echo "$expected" | tr -d '[:space:]' | tr 'A-F' 'a-f')"
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die "The expected SHA-256 does not look valid: '$expected'"

if [ -f "$iso" ] && [ "$force" = 0 ]; then
    echo "Verifying the ISO already on disk..."
    if [ "$(sha256_of "$iso")" = "$expected" ]; then
        echo "ISO OK: $iso"
        exit 0
    fi
    warn "The local ISO does not match the hash; resuming the download."
fi

echo "Downloading $url"
echo "(about 6 GB; you can interrupt it and resume by running this again)"
curl --location --fail --retry 3 --continue-at - --output "$iso" "$url"

echo "Verifying SHA-256..."
actual="$(sha256_of "$iso")"
[ "$actual" = "$expected" ] || die "SHA-256 mismatch.
  expected: $expected
  got:      $actual
Delete $iso and try again."
echo "ISO verified: $iso"
