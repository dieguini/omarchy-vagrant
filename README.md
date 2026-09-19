# omarchy-vagrant

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?style=flat&logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/g0l14t)

[Omarchy](https://omarchy.org/) — DHH's Arch + Hyprland distro — in a VirtualBox
VM with one `vagrant up`, without touching the setup wizard.

Built for Windows hosts: try the desktop, and keep it as a disposable Linux dev
box, before wiping a disk for the real thing.

```powershell
git clone https://github.com/dieguini/omarchy-vagrant
cd omarchy-vagrant
.\bootstrap.ps1
vagrant up
```

`bootstrap.ps1` downloads and verifies the ISO (~6 GB, resumable), builds the
unattended-install drive and a dedicated SSH key, and registers the base box.
`vagrant up` opens the VirtualBox window, the installer runs on its own, the VM
reboots and Vagrant waits for SSH — 10-20 minutes depending on your connection.

Then: `vagrant ssh` for a shell, `vagrant halt` / `vagrant up` to stop and
start, `vagrant destroy -f` to wipe it and begin again.

## Requirements

- Windows with **VirtualBox 7** and **Vagrant**
- **Git for Windows** (provides the `openssl` that hashes the password)
- ~15 GB free: 6 GB of ISO plus whatever the VM's disk grows to
- Virtualization enabled in the BIOS, and Hyper-V off if VirtualBox complains

## Configuring it

`config.json` holds the defaults. Don't edit it — create a `config.local.json`
next to it with only the keys you want to change. That file is gitignored, so
your password and identity stay out of git.

```json
{
  "username": "diego",
  "password": "something-better-than-the-default",
  "timezone": "America/La_Paz",
  "keyboard": "latam",
  "memory_mb": 12288,
  "omarchy_installs": ["editor vscode", "dev-env node"]
}
```

Every key, and the four lists that declare what software the VM carries, are in
**[docs/configuration.md](docs/configuration.md)**.

## Documentation

| | |
|---|---|
| **[How it works](docs/how-it-works.md)** | The `cidata` unattended install, the empty box trick, and why it's built this way |
| **[Configuration](docs/configuration.md)** | Every config key, and installing packages, AUR, and web apps |
| **[Graphics](docs/graphics.md)** | Why the desktop comes up black without help, and setting resolution |
| **[Security](docs/security.md)** | Where the password hash lives and what the sudo rule does |
| **[Troubleshooting](docs/troubleshooting.md)** | Recovering from an interrupted `vagrant up` |

The story of building this, including the three failures between a finished
install and a usable desktop, is written up in
[Running Omarchy in a Vagrant VM](https://medium.com/@diegojaureguisalvatierra/running-omarchy-in-a-vagrant-vm-and-the-three-failures-nobody-documented-8a83d4111abc).

## What you don't get

- **Synced folders.** Omarchy has no Guest Additions, so `/vagrant` is disabled
  on purpose. Use `scp` over `vagrant ssh`, or a forwarded port.
- **Graphics performance.** QtQuick runs in software. Browsing and video are
  sluggish; gaming is out. To just *try* Omarchy with better acceleration, the
  project ships [try-omarchy-windows](https://github.com/omacom/try-omarchy-windows),
  which uses QEMU with virgl.
- **Disk encryption.** An encrypted install asks for the LUKS passphrase at
  every boot, which defeats the unattended part.

## Versioning

Changes are in [CHANGELOG.md](CHANGELOG.md). Each release states which Omarchy
version it was verified against.

## License

MIT. Omarchy belongs to Basecamp/omacom and has its own license.
