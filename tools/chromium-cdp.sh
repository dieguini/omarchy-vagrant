#!/usr/bin/env bash
# chromium-cdp: a Chromium that scripts and agents can drive (`cdp`, `text-shot`), with the
# DevTools protocol on 127.0.0.1 only. Software rendering, because the VM's GPU is emulated
# and a GPU-accelerated Chromium on Wayland has frozen the display. Chromium refuses remote
# debugging on its default profile, so this one runs on a copy of it: sign-ins made in your
# normal Chromium carry over on the first start (or with --refresh-profile).
#
#   chromium-cdp [url]                    start (or reuse) and open url
#   chromium-cdp --refresh-profile [url]  re-copy ~/.config/chromium first
#
# One launcher at a time: two started together (two timers at boot) each saw no DevTools
# yet and started two Chromiums on the same profile. More than one is reported, not killed.
set -euo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
PORT=${CDP_PORT:-9222}
PROFILE="${CDP_PROFILE:-$HOME/.config/chromium-cdp}"

lockdir=$XDG_RUNTIME_DIR; [ -d "$lockdir" ] && [ -w "$lockdir" ] || lockdir=/tmp
LOCK="$lockdir/chromium-cdp.lock"
exec 9>"$LOCK"
flock -w 60 9 || { echo "another chromium-cdp is still starting (lock $LOCK held for 60 s)" >&2; exit 1; }

# Browser processes only: renderers and helpers carry --type=..., the browser starts with
# --user-data-dir.
browsers() { pgrep -f -- "^/usr/lib/chromium/chromium --user-data-dir=$PROFILE( |$)" || true; }
check_single() {
  local pids n
  pids=$(browsers); n=$(grep -c . <<<"$pids" || true)
  if [ "$n" -gt 1 ]; then
    echo "WARNING: $n Chromiums on $PROFILE (PIDs $(tr '\n' ' ' <<<"$pids")); close the extra ones by PID" >&2
  fi
}

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
  echo "CDP already on 127.0.0.1:$PORT"; check_single; exit 0
fi

# 9>&-: Chromium must not inherit the lock, or it would hold it for as long as it runs.
setsid /usr/lib/chromium/chromium \
  --user-data-dir="$PROFILE" --remote-debugging-address=127.0.0.1 --remote-debugging-port="$PORT" \
  --ozone-platform=wayland --disable-gpu --disable-gpu-compositing \
  --disable-gpu-rasterization --disable-accelerated-video-decode \
  --password-store=gnome-libsecret --no-first-run --no-default-browser-check \
  ${1:+"$1"} >/tmp/chromium-cdp.log 2>&1 < /dev/null 9>&- &

for _ in $(seq 1 20); do
  curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null && { echo "CDP ready on 127.0.0.1:$PORT"; check_single; exit 0; }
  sleep 1
done
echo "CDP did not come up -- see /tmp/chromium-cdp.log" >&2; exit 1
