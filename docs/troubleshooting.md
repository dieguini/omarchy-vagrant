# Troubleshooting

An interrupted `vagrant up` — a Ctrl+C, or a VirtualBox error partway through —
leaves traces in two places, and the next attempt fails with a message that
doesn't point at the cause.

## "another process is already executing an action on the machine"

…with no Vagrant process alive anywhere. It's an orphaned lock: Vagrant writes
an `action_<name>` file into `.vagrant/machines/default/virtualbox/` while each
action runs, and doesn't clean it up if the process dies.

Check that nothing really is running, then delete it:

```powershell
# Windows
Get-Process ruby,vagrant -ErrorAction SilentlyContinue
Remove-Item .\.vagrant\machines\default\virtualbox\action_*
```

```bash
# macOS / Linux
pgrep -fl 'vagrant|ruby'
rm .vagrant/machines/default/virtualbox/action_*
```

## "Could not rename the directory … (VERR_ALREADY_EXISTS)"

VirtualBox left behind the folder of a previous VM. On Windows it rewrites
`Logs\VBoxHardening.log` right after deleting the VM, so the directory survives
the destroy.

The `destroy` trigger handles this, but if you do see it, look at what's inside
and remove it:

```powershell
# Windows
Get-ChildItem "$env:USERPROFILE\VirtualBox VMs\omarchy" -Recurse
Remove-Item "$env:USERPROFILE\VirtualBox VMs\omarchy" -Recurse
```

```bash
# macOS / Linux
ls -R ~/"VirtualBox VMs/omarchy"
rm -r ~/"VirtualBox VMs/omarchy"
```

That error also leaves a half-imported VM registered, under a name like
`omarchy-empty-64g-builder_<numbers>`. Remove it too (same on every host):

```sh
VBoxManage list vms
VBoxManage unregistervm "<that-name>" --delete
```

## Where to pick up

After cleaning, `vagrant status` tells you where you stand:

- **`not created`** — start over with `vagrant up`.
- **`poweroff`** — the VM survived and `vagrant up` resumes it where it was.

## The desktop is black

That's its own story: see [graphics](graphics.md). Short version — it's almost
certainly QtQuick, not Hyprland, and `vagrant ssh` still works while you
investigate.

## The install seems stuck

While the install runs, `vagrant up` prints `Authentication failure` and
`Remote connection disconnect` over and over. That's the live ISO's own sshd
rejecting your key, and it's expected for 10-20 minutes.

To see what the installer is actually doing:

```powershell
# Windows
VBoxManage controlvm omarchy screenshotpng "$env:USERPROFILE\Desktop\omarchy.png"
```

```bash
# macOS / Linux
VBoxManage controlvm omarchy screenshotpng ~/Desktop/omarchy.png
```

## `bootstrap.sh` stops with an error (macOS / Linux)

Each check names what's missing before anything is downloaded:

| Message | Fix |
|---|---|
| `Apple Silicon Mac detected` | Not fixable on that machine: Omarchy is x86_64-only. See [host setup](host-setup.md#apple-silicon-m1m4-not-possible) |
| `Cannot find VBoxManage` | Install VirtualBox 7 ([host setup](host-setup.md)) |
| `vagrant is required` | Install Vagrant, then open a new terminal |
| `No openssl that supports 'passwd -6'` | macOS: `brew install openssl@3`. The system `openssl` is LibreSSL and can't make the hash |
| `python3 is required` | macOS: `xcode-select --install`. Linux: your package manager |
| `No ISO builder found` | Linux: install `xorriso` (or `genisoimage`) |
| `SHA-256 mismatch` | A corrupted download. Delete `.build/omarchy-*.iso` and run `./bootstrap.sh` again |

On macOS, *"Kernel driver not installed"* from `VBoxManage` means VirtualBox's
kernel extension hasn't been approved yet: *System Settings → Privacy &
Security*, allow Oracle, restart. On Linux the same message means `vboxdrv`
isn't loaded — see [host setup](host-setup.md#linux).
