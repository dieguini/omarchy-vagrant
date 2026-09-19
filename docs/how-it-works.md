# How it works

Omarchy 4 **cannot** be installed with a script on top of an existing Arch
system — that path is gone, and the old `omarchy.org/install` endpoint points at
a `boot.sh` that 404s. It installs from its own ISO.

What it does support, and what this repo uses, is the
[unattended install](https://learn.omacom.io/2/the-omarchy-manual/51/unattended-installs)
from the manual:

> If the installer finds a second drive labeled `cidata` carrying its
> configuration files, it copies them off, skips the setup wizard entirely, and
> reboots into the finished system on its own.

`cidata` is cloud-init's NoCloud label, so this is the same mechanism Proxmox
and Packer already speak. It becomes three pieces that `bootstrap.ps1` builds
before the first boot:

| Piece | What it is |
|---|---|
| `.build\omarchy-<ver>.iso` | The official ISO, downloaded and checked against its published SHA-256 |
| `.build\cidata.iso` | A tiny ISO holding `user_configuration.json`, `user_credentials.json` and your `authorized_keys` |
| Box `omarchy-empty-<N>g` | An **empty** Vagrant box: EFI, a SATA controller and a blank disk |

## Why the box is empty

Vagrant needs a box to boot and there is no Omarchy box. So one gets built: a VM
with EFI firmware, a SATA controller and a blank disk, exported to OVF and
tarred with a `metadata.json`.

The boot order puts the **disk first** — the empty disk boots nothing and falls
through to the DVD; once installed it boots from disk and the ISO stops
mattering. That's the same trick the manual's Proxmox example uses.

The disk size is baked into the box, so it's named after it. Changing `disk_gb`
produces a different box.

## Why SSH works at all

A stock Omarchy install ships openssh with the service **disabled and the port
closed**. Because the `cidata` includes `authorized_keys`, the installer enables
`sshd` and opens the firewall. Without that, Vagrant could never reach the
machine.

While the install runs, `vagrant up` prints `Authentication failure` over and
over. That's expected: the live ISO runs its own sshd, which rejects your key.
It stops once the machine reboots into the installed system.

## Building the cidata on Windows

`genisoimage` isn't there, but Windows ships IMAPI2, the burning API, reachable
from PowerShell. It produces ISO9660+Joliet, and Joliet is what preserves
`user_configuration.json` as a long filename for the Linux kernel to read.

The `user_configuration.json` template comes from the ISO's own configurator
([omacom/omarchy-iso](https://github.com/omacom/omarchy-iso), in
`configs/airootfs/root/configurator`) — archinstall's schema with an
`omarchy_install` block bolted on, and the partition geometry computed from the
disk size. Since the virtual disk is created here, those numbers are known up
front and the JSON can be generated without ever booting the wizard.

**If Omarchy changes that format in a future version, that file is where to
look.**

## Layout

```
bootstrap.ps1                    Orchestrates the three preparation steps
config.json                      Defaults (tracked)
config.local.json                Your overrides (gitignored)
Vagrantfile                      Defines the VM, attaches the media, ejects at the end
scripts/
  lib.ps1                        Config, paths, ISO creation via IMAPI2
  Get-OmarchyIso.ps1             Download + SHA-256 verification
  New-CidataIso.ps1              Generates the installer files and the cidata ISO
  New-EmptyBox.ps1               Builds and registers the empty Vagrant box
  Eject-InstallMedia.ps1         Ejects the ISO and cidata by hand
```

## Provisioners

They run in this order, and all of them are idempotent:

1. `passwordless-sudo` — installs the sudoers rule Vagrant assumes. See
   [security](security.md).
2. `qt-software-rendering` — without this there is no desktop. See
   [graphics](graphics.md).
3. `display` — resolution and scale.
4. `tools` — packages, AUR, `omarchy install`, web apps. See
   [configuration](configuration.md).

You can add your own `config.vm.provision "shell"` blocks, with or without
`privileged: true`: the first two leave the VM in a state where that works like
any other Vagrant box.

One thing that is deliberately disabled: `allow_fstab_modification`. Vagrant
writes a marker block into `/etc/fstab` as part of its synced-folder machinery
even when every synced folder is off, and that is what killed the first
`vagrant up`.
