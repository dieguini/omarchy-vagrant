# Helper tools

Small commands for scripts and coding agents working inside the VM:

| Command | What it does |
|---|---|
| `chromium-cdp` | Starts a Chromium that can be driven over the DevTools protocol, on `127.0.0.1` only |
| `cdp` | Drives that Chromium: run JavaScript, click, type, upload, screenshot |
| `text-shot` | Turns a command's output into a clean, page-only screenshot |
| `mask` | Replaces IPs, emails, IDs and your own terms with stable tokens before text leaves the VM, and puts them back afterwards |
| `vm-term` | Opens a terminal in the desktop session from SSH or a systemd unit, for a human to confirm a command |
| `vm-health` | Read-only check of the browser, signed-in sessions, services and timers |
| `schedule-apply` | Keeps the times of systemd user timers in one TOML file, in your timezone |

They are installed by default (`"helper_tools": true` in `config.json`). `cdp` needs Node,
which the provisioner installs through mise when it is missing (the same way Omarchy
installs it); `vm-term` needs `foot`, a small terminal the provisioner adds with pacman; the
rest is bash and the Python standard library. Set `"helper_tools": false` in
`config.local.json` to skip them.

The files are copied from the host as they are, so the provisioner strips any CRLF first:
a Windows checkout with `core.autocrlf=true` would otherwise break every shebang.

## chromium-cdp

```bash
chromium-cdp                          # start it (or reuse the running one)
chromium-cdp https://example.com      # and open a page
chromium-cdp --refresh-profile        # re-copy your normal profile first
```

Why a separate launcher instead of plain `chromium`:

- **Rendering.** The VM's GPU is emulated. A GPU-accelerated Chromium on Wayland has frozen
  the whole display, so this one runs with GPU, compositing, rasterization and video
  decoding off. See [graphics](graphics.md).
- **Profile.** Chromium refuses remote debugging on its default profile. This one runs on a
  copy, `~/.config/chromium-cdp`, made from `~/.config/chromium` on the first start, so the
  sites you signed in to in your normal Chromium are signed in here too. Never type
  passwords into it from a script; sign in by hand in its window.
- **Port.** DevTools listens on `127.0.0.1:9222` (`CDP_PORT` to change it). Nothing outside
  the VM can reach it unless you forward the port yourself, and you should not.
- **One at a time.** Launchers take a lock (`$XDG_RUNTIME_DIR/chromium-cdp.lock`) while they
  check and start: two timers at boot once started two Chromiums on the same profile. If
  more than one is running anyway, it says so with their PIDs and kills nothing.

## cdp

```bash
cdp eval 'document.title'                     # any expression; prints the JSON result
CDP_URL_MATCH=github.com cdp eval 'location.href'
cdp click 'Sign in'                           # real mouse click on the first visible match
cdp field 'Email' && cdp type 'me@example.com'
cdp key Enter                                 # Escape, Tab, arrows, Shift+Tab, ...
cdp clickat 513 634                           # at page coordinates
cdp wheel 900 700 500                         # scroll down 500 px at that point
cdp options                                   # options of an open dropdown
cdp upload report.pdf                         # into the last <input type=file>
cdp nav https://example.com/#/settings        # navigate, without waiting for the load
cdp shot page.png                             # screenshot of the page only
REDACT=all cdp shot page.png                  # ... pixelated by redact-shot first
```

It acts on the first open page whose target id starts with `CDP_URL_MATCH`, else whose URL
contains it, or on the first page when that is unset. `click` and `field` look inside an
open dialog first and fall back to the whole page, because menus are often rendered outside
the dialog. Clicks are real mouse events at the element's centre, so pages that ignore
synthetic `element.click()` still react. `type` inserts text into the focused element,
symbols included. `key` sends a real key press with the right key code (Enter 13,
Escape 27, Tab 9), so handlers that check `keyCode` see it.

`nav` returns after two seconds even when Chromium has not answered: a hash-only change in a
single-page app may never answer at all.

With `REDACT=sensitive` or `REDACT=all`, `shot` runs [redact-shot](redact-shot.md) on the
file before returning. If `redact-shot` is not installed, the screenshot is deleted rather
than left unredacted.

### Tabs of its own, in the background

```bash
id=$(cdp new https://example.com/report)      # background tab: the user's focus stays put
CDP_URL_MATCH=$id cdp eval 'document.title'
CDP_URL_MATCH=$id cdp close
```

`new` opens the tab behind the current one and prints its target id; `CDP_URL_MATCH` takes
that id (or its first characters), so a script addresses exactly the tab it opened. `close`
refuses to run without `CDP_URL_MATCH`: the first page may be the one the user is reading.

**Screenshots need a visible tab.** Chromium only paints what is shown, and
`Page.captureScreenshot` never returns for a background tab or a minimised window, and
mouse input (`wheel` most of all) can wait for a paint that never comes either. They fail
after the timeout with that explanation instead of hanging. `eval`, `type`, `key` and `nav`
do not need a visible tab. `cdp activate` brings
that one tab to front; it changes what the user sees, so use it only when a screenshot
needs it, and prefer `eval` for reading a page.

### Timeout, viewport and crop

| Variable | Effect |
|---|---|
| `CDP_TIMEOUT_MS` | Every call gives up after this long (default 30000) and `cdp` exits 5 naming the call that hung. A hung or hidden tab cannot block a script forever |
| `CDP_VIEWPORT=1920x1080` | Emulates that viewport for the command (scale 1, not mobile) and clears it at the end, so a portal renders its desktop layout even in a small window. Coordinates for `clickat`, `wheel` and `click:x,y` are then in that viewport |
| `CDP_CLIP=x,y,w,h` | `shot` crops to that rectangle, at scale 1: no image library needed |

### Several steps in one session

A viewport override ends with the command, and a menu that opened in the emulated layout
closes when the window's own size comes back. `steps` runs a sequence in one session with
the viewport held:

```bash
CDP_VIEWPORT=1920x1080 cdp steps 'click:Filters' 'wait:800' 'click:513,634' \
  'type:hello' 'key:Enter' 'wheel:900,700,500' 'shot:/tmp/a.png' 'eval:document.title'
```

Each step is `name:argument`: `wait:<ms>`, `click:<x>,<y>` or `click:<text>`, `field`,
`hover`, `type`, `key`, `wheel:<x>,<y>,<dy>`, `shot:<file>`, `eval:<js>`, `nav:<url>`,
`upload:<file>`, `options`, `newline`. The first failing step stops the run with its exit
code. `REDACT` applies to `shot` steps too.

Exit codes: 1 usage, 2 no Chromium or no matching tab, 3 element not found or page error,
4 redaction failed (screenshot deleted), 5 timeout.

## text-shot

```bash
az vm list -o table > vms.txt
text-shot vms.txt vms.png "VMs in the subscription"
REDACT=sensitive text-shot vms.txt vms.png
```

The text is rendered as a dark monospace page with the title, the time and the source
file in a header, in columns when it is long, and captured through `cdp`. Only the page
is in the image: no desktop, no terminal, no other windows. It needs `chromium-cdp`
running.

## mask

```bash
mask mask   notes.txt notes.masked.txt    # before pasting into a prompt or a ticket
mask unmask answer.txt answer.real.txt    # restore the real values in the reply
mask selftest
```

Replaced with stable tokens such as `<IP_1>` or `<TERM_3>`: IPv4 and IPv6 addresses,
emails, GUIDs, Azure resource IDs, URL query strings, UNC host names, and every term in
`~/.config/mask/terms.txt` (one per line: servers, databases, customers, people; created
empty by the provisioner, `--terms` for another file). The value after `password=`,
`pwd=`, `secret=`, `token=`, `sig=` and similar becomes `<REDACTED>` and is never stored.

The mapping is kept in `~/.config/mask/maps/default.json` (mode 600; `--map NAME` for a
separate one per task), so the same value gets the same token in every file masked with
that map, and `unmask` can put it back. The maps are the only place the real values live:
never send them anywhere.

## vm-term

```bash
vm-term --title 'Apply changes' -- 'deploy.sh --apply'   # prints the window's PID
vm-term --hold -- make test                             # shell stays open afterwards
vm-term --close 12345                                   # that window, and nothing else
```

Opens a `foot` window in the running Hyprland session, also when called over SSH or from a
systemd unit: it rebuilds the session environment from `/run/user/<uid>` (Wayland socket,
Hyprland instance, D-Bus) and detaches the window, so it outlives the caller. One argument
is a shell command line; several are quoted as separate words. It fails with a clear message
when nobody is logged into the desktop.

What it is for: **leaving a command ready for a human to confirm.** A script that ends in a
`[y/N]` prompt (default No) runs in a window on the desktop, and a person reads it and
answers. The agent or timer that prepared it never answers its own confirmations.

`--close` kills exactly that PID, and only if it is a window in the session. A generic
"close the active window" closes whatever has focus, and once closed the automation browser
instead of the terminal.

## vm-health

```bash
vm-health              # one line per check: OK / WARN / FAIL
vm-health --quiet      # only WARN and FAIL; a desktop notification on any FAIL
vm-health --no-sites   # skip the web-session checks
```

Read-only: it changes and restarts nothing. It checks that exactly one Chromium runs on the
`chromium-cdp` profile and DevTools answers on `127.0.0.1:${CDP_PORT:-9222}`; that each site
in `SITES` is still signed in (opened in a background tab and closed again; FAIL when it
lands on `login.microsoftonline.com`, `login.live.com`, `accounts.google.com` or a
`/login`, `/signin` or `/auth` path); that each service in `SERVICES` is active; that every
enabled user timer is scheduled; and that no user unit has failed. Exit code 0 all OK, 1 a
WARN, 2 a FAIL.

The lists are yours, in `~/.config/vm-health.conf` (bash, sourced; all empty by default):

```bash
SITES=("Docs|https://docs.example.com/" "Tracker|https://tracker.example.com/home")
SERVICES=(my-listener)
CHECK_CHROMIUM=0     # skip the Chromium and site checks
CHECK_AZ=1           # also check the az sign-in; only when az is installed
```

`examples/systemd/` has a `vm-health.service` and `vm-health.timer` that run
`vm-health --quiet` 10 minutes after boot and every 2 hours; the header of the service says
how to install them.

## schedule-apply

```bash
cp examples/schedule.toml ~/.config/omarchy-schedule.toml   # then edit it
schedule-apply --check     # what would change; exit 1 if anything differs
schedule-apply             # write; then: systemctl --user daemon-reload
schedule-apply --reload    # ... and reload in one go
```

The times of every timer, in one file instead of scattered `.timer` files:

```toml
timezone = "America/Los_Angeles"

[workday]               # optional
start = "06:00"
end   = "17:00"

[timers.backup]
file        = "systemd/user/backup.timer"   # relative to the TOML's directory
description = "Nightly backup of ~/Work"
on          = ["*-*-* 02:30:00"]
```

Only the `Description=` and `OnCalendar=` lines of each timer are rewritten; the rest of the
file is left alone, and the file must already exist with an `OnCalendar=` line. Each
`OnCalendar` gets the timezone appended (`*-*-* 02:30:00 America/Los_Angeles`), so systemd
follows daylight saving itself. With `[workday]`, a `schedule.env` next to the TOML gets
`WORK_TZ`, `WORK_START` and `WORK_END`, for scripts that guard their own hours. Specs are
checked with `systemd-analyze calendar` before anything is written; files are written with
LF. Exit code 0 done, 1 `--check` found differences, 2 bad input.

## Limits

`mask` works on patterns and your term list. A name it does not know, or an identifier in
an unusual format, passes through unchanged: read the masked text before it leaves the
VM. `cdp` targets the first matching page; with several tabs on the same site, narrow
`CDP_URL_MATCH`, or open your own tab with `cdp new` and use its id. `shot` cannot capture a
tab nobody can see.
