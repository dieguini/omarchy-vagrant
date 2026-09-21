# Configuration

`config.json` holds the defaults. **Don't edit it** — create a
`config.local.json` next to it with only the keys you want to change. That file
is gitignored, so your password and identity stay out of git.

```json
{
  "username": "diego",
  "password": "something-better-than-the-default",
  "full_name": "Diego Jauregui",
  "email_address": "diego@example.com",
  "timezone": "America/La_Paz",
  "keyboard": "latam",
  "memory_mb": 12288,
  "cpus": 6,
  "disk_gb": 96,
  "forwarded_ports": [{ "guest": 3000, "host": 3000 }]
}
```

## Starting from an example

`examples/` has ready-made profiles. Copy one and edit from there:

```powershell
Copy-Item examples\iac.json config.local.json
```

| Profile | What it sets up |
|---|---|
| `iac.json` | Terraform, Terragrunt, Ansible, kubectl, k9s, helm, and the AWS and Azure CLIs |
| `web-dev.json` | Node and Python via `dev-env`, an editor and a browser, with ports forwarded |
| `minimal.json` | Headless: no desktop window, SSH only, small |

Because `config.local.json` is gitignored, whatever you build there lives on one
machine and isn't backed up. If it's a setup you'd want again, add it to
`examples/` — that folder **is** tracked.

## Every key

| Key | Default | Notes |
|---|---|---|
| `omarchy_version` | `4.0.4` | Determines the ISO URL |
| `iso_url`, `iso_sha256` | empty | To pin your own ISO; derived from the version when empty |
| `vm_name`, `hostname` | `omarchy` | |
| `cpus`, `memory_mb`, `disk_gb` | 4 / 8192 / 64 | `disk_gb` is baked into the base box |
| `gui` | `true` | Set to `false` for SSH only |
| `accelerate_3d`, `vram_mb` | `true` / 128 | See [graphics](graphics.md) |
| `resolution`, `scale`, `gdk_scale` | `1920x1080@60` / 1 / 1 | See [graphics](graphics.md). Leave `resolution` empty to skip |
| `software_rendering` | `true` | Puts QtQuick in software. Without it there is no desktop |
| `passwordless_sudo` | `true` | Installs the sudoers rule Vagrant assumes. See [security](security.md) |
| `username`, `password` | `omarchy` | The user must satisfy Omarchy's rules: lowercase, starting with a letter or `_` |
| `full_name`, `email_address` | empty | Used for the git identity inside the VM |
| `timezone`, `keyboard` | `UTC` / `us` | |
| `boot_timeout_seconds` | 3600 | Covers the whole install, not just the boot |
| `forwarded_ports` | `[]` | List of `{guest, host}` |

After changing something that affects the install itself (user, disk, keyboard):

```powershell
vagrant destroy -f
.\bootstrap.ps1 -SkipIso -Force   # rebuild cidata and box without re-downloading 6 GB
vagrant up
```

## Installing tools

Four lists declare what the VM carries beyond what Omarchy ships. They're
applied on every `vagrant up` and are idempotent:

```json
{
  "omarchy_installs": ["editor vscode", "dev-env node", "browser brave"],
  "packages": ["httpie", "jq"],
  "aur_packages": ["some-aur-only-thing"],
  "webapps": [
    { "name": "Claude", "url": "https://claude.ai", "icon": "claude" }
  ]
}
```

**`omarchy_installs`** → `omarchy install …`, Omarchy's curated installers.
**Prefer this list whenever an entry exists for what you want**, because they do
more than install: `editor vscode` turns off VS Code's auto-updater (Omarchy
handles updates), points it at `gnome-libsecret` and applies the system theme.
Browse the catalogue with:

```powershell
vagrant ssh -c 'omarchy install --help'
```

There are entries for `editor`, `browser`, `dev-env` (ruby, node, bun, go,
python, rust, java…), `ai`, `docker dbs` and more.

**`packages`** → `pacman`, official repos (and Omarchy's).

**`aur_packages`** → `yay`. The provisioner passes `--answerclean None
--answerdiff None`, which is what stops `yay` from hanging on *"Packages to
cleanBuild?"* waiting for an answer that never arrives in a provisioner.

**`webapps`** → `omarchy-webapp-install`, which creates a launcher for a website
as if it were an app. `icon` can be an icon name or the URL of one.

The two middle lists are the escape hatch for anything without a curated
installer. Execution order is as listed above.

To apply them without restarting the VM:

```powershell
vagrant provision --provision-with tools
```

### One Arch caveat

The provisioner runs `pacman -Sy` to refresh the databases, not `-Syu`. That's
deliberate — a `-Syu` inside a `vagrant up` can turn into a half-hour upgrade
and even want a reboot. The trade-off is the classic partial-upgrade risk, so if
the VM has been alive for a while, upgrade it first:

```powershell
vagrant ssh -c 'omarchy update'
```

Note that `omarchy update` rewrites `monitors.lua` back to Omarchy's own values.
Run `vagrant provision --provision-with display` afterwards to restore yours.
