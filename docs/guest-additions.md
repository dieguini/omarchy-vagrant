# Guest Additions

VirtualBox Guest Additions give the VM a **shared clipboard** with the host and
dynamic screen resolution. On by default — the repo targets VirtualBox, and
copy-paste into the VM is otherwise genuinely painful.

Turn it off with `"guest_additions": false` in `config.json` if you would rather
the VM stayed isolated from the host clipboard.

## What the provisioner does

| Step | |
|---|---|
| Installs `virtualbox-guest-utils` | The Oracle package; not a third-party project |
| Loads `vboxguest`, `vboxsf`, `vboxvideo` | In-tree with the Omarchy kernel, so no DKMS build |
| Persists them in `/etc/modules-load.d/` | So they return on the next boot |
| Enables `vboxservice` | The system-side guest service |
| Adds `VBoxClient --clipboard` to Hyprland autostart | Clipboard sync lives in the graphical session |

It is idempotent: a second run detects the package, the modules and the
autostart line already in place and changes nothing.

## Using it

Copy anything on the host, then paste in the VM with **`Ctrl+Shift+V`** (the
terminal and most Wayland apps use Shift+V, not plain V). It works both ways —
copying in the VM makes the text available on the host too.

## The one subtlety, if you ever install it by hand

`VBoxClient --clipboard` fails with `VbglR3InitUser ... VERR_ACCESS_DENIED` when
`/dev/vboxuser` comes up `0600`. The udev rule sets it to `0666`, but only on the
module's `add` event — already passed if you `modprobe` by hand. Re-fire it:

```bash
sudo udevadm trigger --action=add --subsystem-match=misc
```

The provisioner does this for you. On a normal boot it is a non-issue: the module
loads, the event fires, the rule applies.

## Wayland note

The clipboard client is started with `--session-type wayland`. Under Hyprland
the X11 default does nothing, which is the usual reason a "working" Guest
Additions install still will not paste.
