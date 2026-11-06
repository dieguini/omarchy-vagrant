#!/usr/bin/env bash
# vm-health: read-only check that what the VM's scripts, agents and timers rely on is up. One
# line per item (OK / WARN / FAIL). Changes nothing and restarts nothing.
#
#   vm-health [--quiet] [--no-sites]
#   --quiet     only WARN and FAIL lines (for a timer); a desktop notification on any FAIL
#   --no-sites  skip the web-session checks (each opens and closes one background tab)
#
# Checked: one Chromium on the chromium-cdp profile with DevTools answering; the web sessions
# in SITES (still signed in?); the user services in SERVICES; every enabled user timer
# scheduled; no failed user units; optionally az (CHECK_AZ=1).
#
# Lists live in ~/.config/vm-health.conf (bash, sourced; all empty by default):
#   SITES=("Docs|https://example.com/app")   name|url, FAIL when it lands on a sign-in page
#   SERVICES=(my-listener)                   user services that must be active
#   CHECK_CHROMIUM=0                         skip the Chromium and site checks
#   CHECK_AZ=1                               check the az sign-in (needs az installed)
#
# Exit code: 0 all OK, 1 any WARN, 2 any FAIL, 3 bad usage.
set -euo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
PORT=${CDP_PORT:-9222}
PROFILE="${CDP_PROFILE:-$HOME/.config/chromium-cdp}"
CONF="${VM_HEALTH_CONF:-$HOME/.config/vm-health.conf}"

quiet=false sites=true
for a in "$@"; do
  case $a in
    --quiet) quiet=true;; --no-sites) sites=false;;
    *) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 3;;
  esac
done

SITES=() SERVICES=() CHECK_CHROMIUM=1 CHECK_AZ=0 AZ_RESOURCES=(https://management.azure.com/)
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"

fails=() warns=()
ok()   { $quiet || printf '  OK    %s\n' "$*"; }
warn() { warns+=("$*"); printf '  WARN  %s\n' "$*"; }
fail() { fails+=("$*"); printf '  FAIL  %s\n' "$*"; }
section() { $quiet || printf '\n%s\n' "$*"; }

$quiet || echo "vm-health $(date '+%Y-%m-%d %H:%M %Z')"

if [ "$CHECK_CHROMIUM" = 1 ]; then
  section "Chromium (chromium-cdp)"
  # Browser processes only: renderers and helpers carry --type=..., the browser starts with
  # --user-data-dir.
  pids=$(pgrep -f -- "^/usr/lib/chromium/chromium --user-data-dir=$PROFILE( |$)" || true)
  n=$(grep -c . <<<"$pids" || true)
  case $n in
    0) fail "no Chromium on $PROFILE (start one: chromium-cdp)";;
    1) ok "one instance (PID $pids)";;
    *) fail "$n Chromiums on the same profile (PIDs $(tr '\n' ' ' <<<"$pids")) - close them by PID and start one";;
  esac
  if curl -sf --max-time 10 "http://127.0.0.1:$PORT/json/version" >/dev/null; then ok "DevTools answering on 127.0.0.1:$PORT"
  else fail "DevTools not answering on 127.0.0.1:$PORT"; sites=false; fi
else
  sites=false
fi

if $sites && [ ${#SITES[@]} -gt 0 ]; then
  section "Web sessions (one background tab per site, closed after)"
  if ! command -v node >/dev/null; then
    warn "node not found: web sessions not checked"
  else
    # Final URL after redirects: a sign-in host or a login path means the session is gone.
    # Background tabs load normally; they just are never shown.
    results=$(printf '%s\n' "${SITES[@]}" | timeout 120 node --input-type=module -e '
      import { createInterface } from "node:readline";
      const port = process.argv[1];
      const lines = []; for await (const l of createInterface({ input: process.stdin })) if (l.trim()) lines.push(l);
      const ver = await (await fetch(`http://127.0.0.1:${port}/json/version`, { signal: AbortSignal.timeout(10000) })).json();
      const ws = new WebSocket(ver.webSocketDebuggerUrl);
      await new Promise((ok, ko) => { ws.onopen = ok; ws.onerror = ko; });
      let id = 0; const pending = new Map();
      ws.onmessage = m => { const d = JSON.parse(m.data); if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); } };
      const send = (method, params = {}) => Promise.race([
        new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); }),
        new Promise(r => setTimeout(() => r({ error: { message: `${method} timed out` } }), 15000)),
      ]);
      const signin = /(^|\.)(login\.microsoftonline\.com|login\.live\.com|accounts\.google\.com)$/;
      const loginPath = /(\/|-)(login|signin|sign_in|sign-in|auth)(\/|\?|$)/i;
      await Promise.all(lines.map(async line => {
        const [name, url] = line.split("|");
        const t = await send("Target.createTarget", { url, background: true });
        const tid = t.result?.targetId; let final = "";
        if (!tid) { console.log(`FAIL|${name}: could not open a tab (${t.error?.message || "no target"})`); return; }
        for (let i = 0; i < 20; i++) {
          await new Promise(r => setTimeout(r, 1000));
          const info = (await send("Target.getTargetInfo", { targetId: tid })).result?.targetInfo;
          final = info?.url || final;
          if (i >= 8 && final && !final.startsWith("about:")) break;
        }
        await send("Target.closeTarget", { targetId: tid });
        let u; try { u = new URL(final); } catch { console.log(`FAIL|${name}: no page loaded`); return; }
        console.log(signin.test(u.hostname) || loginPath.test(u.pathname)
          ? `FAIL|${name}: signed out (${u.hostname}${u.pathname.slice(0, 30)}) - sign in in the chromium-cdp window`
          : `OK|${name}: signed in`);
      }));
      ws.close(); process.exit(0);
    ' "$PORT" 2>&1) || results="${results:-}
FAIL|web-session check did not finish (node exit $?)"
    while IFS='|' read -r level msg; do
      [ -n "$level" ] || continue
      case $level in
        OK)   ok "$msg";;
        FAIL) fail "$msg";;
        *)    fail "web-session check: $level${msg:+|$msg}";;
      esac
    done < <(sort -t'|' -k2 <<<"$results")
  fi
fi

if [ "$CHECK_AZ" = 1 ]; then
  section "az"
  if ! command -v az >/dev/null; then
    fail "CHECK_AZ=1 but az is not installed"
  elif subs=$(az account list --query "length(@)" -o tsv 2>/dev/null) && [ "${subs:-0}" -gt 0 ]; then
    for res in "${AZ_RESOURCES[@]}"; do
      if exp=$(az account get-access-token --resource "$res" --query expiresOn -o tsv 2>/dev/null); then
        ok "token for ${res#https://} (until $exp)"
      else fail "no token for ${res#https://} - run: az login"; fi
    done
    ok "$subs subscription(s) visible"
  else fail "az not signed in - run: az login"; fi
fi

if [ ${#SERVICES[@]} -gt 0 ]; then
  section "Services"
  for s in "${SERVICES[@]}"; do
    st=$(systemctl --user is-active "$s.service" 2>/dev/null || true)
    if [ "$st" = active ]; then ok "$s active"; else fail "$s is ${st:-unknown}"; fi
  done
fi

section "Timers"
mapfile -t timers < <(systemctl --user list-unit-files --type=timer --state=enabled --no-legend 2>/dev/null | awk '{print $1}')
waiting=0
for t in "${timers[@]}"; do
  st=$(systemctl --user is-active "$t" 2>/dev/null || true)
  if [ "$st" = active ]; then waiting=$((waiting+1)); else fail "$t enabled but not scheduled (${st:-unknown})"; fi
done
ok "$waiting of ${#timers[@]} enabled timers scheduled"

section "Failed units"
mapfile -t failed < <(systemctl --user list-units --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}')
if [ ${#failed[@]} -eq 0 ]; then ok "none"
else for u in "${failed[@]}"; do fail "$u failed - journalctl --user -u $u -n 30"; done; fi

notify() {
  command -v notify-send >/dev/null || return 0
  # From a timer there is no session environment: find the Wayland socket and the bus.
  local w="${WAYLAND_DISPLAY:-}" s
  if [ -z "$w" ]; then for s in "$XDG_RUNTIME_DIR"/wayland-*; do [ -S "$s" ] && { w=${s##*/}; break; }; done; fi
  [ -n "$w" ] || return 0
  WAYLAND_DISPLAY=$w DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}" \
    notify-send -u critical "VM health: ${#fails[@]} problem(s)" "$(printf '%s\n' "${fails[@]}" | head -5)" \
    || echo "  (desktop notification failed)" >&2
}

$quiet || echo
if [ ${#fails[@]} -gt 0 ]; then
  $quiet || echo "${#fails[@]} FAIL, ${#warns[@]} WARN"
  $quiet && notify
  exit 2
fi
if [ ${#warns[@]} -gt 0 ]; then $quiet || echo "${#warns[@]} WARN"; exit 1; fi
$quiet || echo "all OK"
exit 0
