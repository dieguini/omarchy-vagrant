#!/usr/bin/env bash
# vm-term: opens a terminal (foot) in the running Hyprland session, even when called over SSH
# or from a systemd unit, and prints the new window's PID.
#
#   vm-term [--title T] [--hold] -- <command…>   run it in a new window; --hold keeps a shell
#                                                open after it ends, to read the output
#   vm-term --close <pid>                        close exactly that window
#
# One argument is a shell command line ('deploy.sh --apply'); several are quoted as words.
#
# What it is for: leaving a command ready for a human to confirm. A script that ends in a
# [y/N] prompt (default No) runs here, on the desktop, and a person answers it; the agent or
# timer that prepared it never answers its own confirmations.
#
# --close kills that PID and nothing else. A generic "close the active window" closes whatever
# has focus, and once closed the automation browser instead of the terminal.
set -euo pipefail

die() { echo "vm-term: $*" >&2; exit 1; }
usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

# The session's environment, rebuilt from /run/user: SSH and systemd units have none of it.
session_env() {
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  [ -d "$XDG_RUNTIME_DIR" ] || die "no $XDG_RUNTIME_DIR: is this user logged into the desktop?"
  local s sig=""
  for s in $(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null); do
    # Newest first, and only one that answers: a crashed session leaves its directory behind.
    if HYPRLAND_INSTANCE_SIGNATURE="$s" hyprctl version >/dev/null 2>&1; then sig=$s; break; fi
  done
  [ -n "$sig" ] || die "no running Hyprland session for $(id -un) (log into the desktop first)"
  export HYPRLAND_INSTANCE_SIGNATURE="$sig"
  local w="${WAYLAND_DISPLAY:-}"
  if [ -z "$w" ] || [ ! -S "$XDG_RUNTIME_DIR/$w" ]; then
    w=""
    for s in "$XDG_RUNTIME_DIR"/wayland-*; do [ -S "$s" ] && { w=${s##*/}; break; }; done
  fi
  [ -n "$w" ] || die "no Wayland socket in $XDG_RUNTIME_DIR"
  export WAYLAND_DISPLAY="$w"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
  export LANG="${LANG:-C.UTF-8}"
}

client_pid() { # $1 pid, $2 title: the PID of a Hyprland window with that pid, else that title
  hyprctl clients -j | jq -r --argjson p "$1" --arg t "$2" \
    '([.[] | select(.pid == $p)] + [.[] | select(.title == $t)]) | .[0].pid // empty'
}

title="" hold=false close=""
while [ $# -gt 0 ]; do
  case $1 in
    --title) [ $# -ge 2 ] || usage; title=$2; shift 2;;
    --hold)  hold=true; shift;;
    --close) [ $# -ge 2 ] || usage; close=$2; shift 2;;
    --)      shift; break;;
    -h|--help) usage;;
    *)       break;;
  esac
done

command -v jq >/dev/null || die "jq is required"

if [ -n "$close" ]; then
  [[ $close =~ ^[0-9]+$ ]] || die "--close takes a PID, got '$close'"
  session_env
  # Only a PID that is a window in this session: never an arbitrary process.
  [ "$(hyprctl clients -j | jq --argjson p "$close" '[.[] | select(.pid == $p)] | length')" -gt 0 ] \
    || die "PID $close is not a window in this Hyprland session"
  kill "$close"
  for _ in $(seq 1 25); do kill -0 "$close" 2>/dev/null || { echo "closed $close"; exit 0; }; sleep 0.2; done
  die "PID $close is still running after SIGTERM"
fi

[ $# -gt 0 ] || usage
command -v foot >/dev/null || die "foot is not installed (sudo pacman -S foot)"
session_env

if [ $# -eq 1 ]; then cmdline=$1; else cmdline=$(printf '%q ' "$@"); fi
$hold && cmdline="$cmdline; exec bash"
title=${title:-vm-term-$$-$(date +%s)}

# setsid: the window outlives this SSH session or unit. In a script the background child is
# not a group leader, so setsid execs foot in place and $! is foot's own PID.
setsid foot --title "$title" bash -lc "$cmdline" </dev/null >/dev/null 2>&1 &
pid=$!

for _ in $(seq 1 50); do
  win=$(client_pid "$pid" "$title" || true)
  [ -n "$win" ] && { echo "$win"; exit 0; }
  kill -0 "$pid" 2>/dev/null || die "foot exited before its window appeared"
  sleep 0.2
done
die "foot started (PID $pid) but no window titled '$title' appeared in 10 s"
