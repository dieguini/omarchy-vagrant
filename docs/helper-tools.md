# Helper tools

Four small commands for scripts and coding agents working inside the VM:

| Command | What it does |
|---|---|
| `chromium-cdp` | Starts a Chromium that can be driven over the DevTools protocol, on `127.0.0.1` only |
| `cdp` | Drives that Chromium: run JavaScript, click, type, upload, screenshot |
| `text-shot` | Turns a command's output into a clean, page-only screenshot |
| `mask` | Replaces IPs, emails, IDs and your own terms with stable tokens before text leaves the VM, and puts them back afterwards |

They are installed by default (`"helper_tools": true` in `config.json`). No packages are
added: `cdp` needs Node, which the provisioner installs through mise when it is missing
(the same way Omarchy installs it), and the rest is bash and the Python standard library.
Set `"helper_tools": false` in `config.local.json` to skip them.

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

## cdp

```bash
cdp eval 'document.title'                     # any expression; prints the JSON result
CDP_URL_MATCH=github.com cdp eval 'location.href'
cdp click 'Sign in'                           # real mouse click on the first visible match
cdp field 'Email' && cdp type 'me@example.com'
cdp options                                   # options of an open dropdown
cdp upload report.pdf                         # into the last <input type=file>
cdp shot page.png                             # screenshot of the page only
REDACT=all cdp shot page.png                  # ... pixelated by redact-shot first
```

It acts on the first open page whose URL contains `CDP_URL_MATCH`, or on the first page
when that is unset. `click` and `field` look inside an open dialog first and fall back to
the whole page, because menus are often rendered outside the dialog. Clicks are real mouse
events at the element's centre, so pages that ignore synthetic `element.click()` still
react. `type` inserts text into the focused element, symbols included.

With `REDACT=sensitive` or `REDACT=all`, `shot` runs [redact-shot](redact-shot.md) on the
file before returning. If `redact-shot` is not installed, the screenshot is deleted rather
than left unredacted.

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

## Limits

`mask` works on patterns and your term list. A name it does not know, or an identifier in
an unusual format, passes through unchanged: read the masked text before it leaves the
VM. `cdp` targets the first matching page; with several tabs on the same site, narrow
`CDP_URL_MATCH`.
