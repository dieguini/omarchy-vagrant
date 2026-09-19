# Graphics

## The black desktop is not Hyprland

Hyprland runs fine on the emulated GPU: VirtualBox provides VMSVGA, the kernel
loads `vmwgfx`, `/dev/dri/card0` shows up and the compositor modesets without
complaint.

What doesn't survive that path is **QtQuick**. Omarchy 4 boots into SDDM, and
both its greeter and the bar (`omarchy-shell`, which is quickshell) are QtQuick
over EGL/dmabuf. Left alone, the result is a black screen in two acts:

- the greeter starts and closes a second later (`Greeter stopped` in `sddm`'s
  journal);
- and if you log in anyway, the bar enters a crash loop with
  `The Wayland connection experienced a fatal error: Invalid argument`.

The `qt-software-rendering` provisioner fixes both, in the two places it has to
be set — the greeter runs as a different user than your session:

- `/etc/sddm.conf.d/99-vagrant-vm-rendering.conf` →
  `GreeterEnvironment=QT_QUICK_BACKEND=software`
- `QT_QUICK_BACKEND=software` in `/etc/environment`

Hyprland itself needs none of this. To turn it off — testing on another
hypervisor, say — set `"software_rendering": false`.

If the screen is still black after that, `vagrant ssh` keeps working. Look at
`journalctl -b -u sddm` and the compositor's log at
`/run/user/<uid>/hypr/*/hyprland.log`. Turning off emulated 3D
(`"accelerate_3d": false`, then `vagrant reload`) is the next thing to try.

## Resolution

Without Guest Additions there's no auto-resize, and what Omarchy picks on its
own inside a VM is cramped: mode `preferred` gives **1280x800** and the
automatic scale goes to **2** — an effective desktop of 640x400, where
Omarchy's own dialogs don't fit. The symptom is huge text and clipped windows.

The `display` provisioner writes `~/.config/hypr/monitors.lua` from
`resolution`, `scale` and `gdk_scale`. Omarchy 4 configures Hyprland in **Lua**,
which is worth knowing before reaching for the usual commands: `hyprctl keyword`
answers *"can't work with non-legacy parsers"*.

The emulated GPU offers modes all the way up to 4096x2160:

```powershell
vagrant ssh -c 'hyprctl monitors all'
```

Change `resolution` and apply it without restarting the VM:

```powershell
vagrant provision --provision-with display
```

That file is rewritten on every `vagrant up`, so configure resolution from
`config.local.json` rather than editing it by hand. To manage it yourself, set
`"resolution": ""` and the provisioner won't run.

If the desktop ends up larger than the VirtualBox window, the **View** menu has
*Scaled Mode* and the window scaling settings.
