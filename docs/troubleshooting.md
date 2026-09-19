# Troubleshooting

An interrupted `vagrant up` — a Ctrl+C, or a VirtualBox error partway through —
leaves traces in two places, and the next attempt fails with a message that
doesn't point at the cause.

## "another process is already executing an action on the machine"

…with no Vagrant process alive anywhere. It's an orphaned lock: Vagrant writes
an `action_<name>` file into `.vagrant\machines\default\virtualbox\` while each
action runs, and doesn't clean it up if the process dies.

Check that nothing really is running, then delete it:

```powershell
Get-Process ruby,vagrant -ErrorAction SilentlyContinue
Remove-Item .\.vagrant\machines\default\virtualbox\action_*
```

## "Could not rename the directory … (VERR_ALREADY_EXISTS)"

VirtualBox left behind the folder of a previous VM. On Windows it rewrites
`Logs\VBoxHardening.log` right after deleting the VM, so the directory survives
the destroy.

The `destroy` trigger handles this, but if you do see it, look at what's inside
and remove it:

```powershell
Get-ChildItem "$env:USERPROFILE\VirtualBox VMs\omarchy" -Recurse
Remove-Item "$env:USERPROFILE\VirtualBox VMs\omarchy" -Recurse
```

That error also leaves a half-imported VM registered, under a name like
`omarchy-empty-64g-builder_<numbers>`. Remove it too:

```powershell
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
VBoxManage controlvm omarchy screenshotpng "$env:USERPROFILE\Desktop\omarchy.png"
```
