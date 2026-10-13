#!/usr/bin/env bash
# chromium-cdp: a Chromium that scripts and agents can drive (`cdp`, `text-shot`), with the
# DevTools protocol on 127.0.0.1 only. Software rendering, because the VM's GPU is emulated
# and a GPU-accelerated Chromium on Wayland has frozen the display. Chromium refuses remote
# debugging on its default profile, so this one runs on a copy of it: sign-ins made in your
# normal Chromium carry over on the first start (or with --refresh-profile).
#
#   chromium-cdp [url]                    start (or reuse) and open url
#   chromium-cdp --refresh-profile [url]  re-copy ~/.config/chromium first
set -euo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
PORT=${CDP_PORT:-9222}
PROFILE="${CDP_PROFILE:-$HOME/.config/chromium-cdp}"

copy_profile() {
  if [ -d "$HOME/.config/chromium" ]; then cp -a "$HOME/.config/chromium" "$PROFILE"; else mkdir -p "$PROFILE"; fi
  rm -f "$PROFILE"/Singleton*
}
if [ "${1:-}" = "--refresh-profile" ]; then
  shift
  pkill -f -- "--user-data-dir=$PROFILE" || true; sleep 2
  rm -rf "$PROFILE"; copy_profile
fi
[ -d "$PROFILE" ] || copy_profile

if curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null; then
  [ -n "${1:-}" ] && curl -s -X PUT "http://127.0.0.1:$PORT/json/new?$1" >/dev/null
  echo "CDP already on 127.0.0.1:$PORT"; exit 0
fi

setsid /usr/lib/chromium/chromium \
  --user-data-dir="$PROFILE" --remote-debugging-address=127.0.0.1 --remote-debugging-port="$PORT" \
  --ozone-platform=wayland --disable-gpu --disable-gpu-compositing \
  --disable-gpu-rasterization --disable-accelerated-video-decode \
  --password-store=gnome-libsecret --no-first-run --no-default-browser-check \
  ${1:+"$1"} >/tmp/chromium-cdp.log 2>&1 < /dev/null &

for _ in $(seq 1 20); do
  curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null && { echo "CDP ready on 127.0.0.1:$PORT"; exit 0; }
  sleep 1
done
echo "CDP did not come up -- see /tmp/chromium-cdp.log" >&2; exit 1
