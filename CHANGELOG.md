# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioned with [SemVer](https://semver.org/).

Since this automates third-party software, the version describes the repo, not
Omarchy. Which Omarchy version gets installed is chosen in `config.json`
(`omarchy_version`), and every release states which one it was verified against.

## [1.2.0] - 2026-09-23

Verified against **Omarchy 4.0.4** on VirtualBox 7.2.6 and Vagrant 2.4.9,
Windows 11 host. Both new provisioners were run against a live VM and checked
for idempotency on a second pass.

### Added

- `guest_additions` (default **on**): VirtualBox Guest Additions for a shared
  clipboard between host and VM, and dynamic resolution. Copy on the host, paste
  with `Ctrl+Shift+V` in the VM. Handles the `/dev/vboxuser` udev permission
  race that otherwise makes `VBoxClient` fail with `VERR_ACCESS_DENIED`, and
  starts the clipboard client with the Wayland session type Hyprland needs. See
  [docs/guest-additions.md](docs/guest-additions.md).
- `onyx` (default off): self-hosted search over your own sources (Asana,
  SharePoint, repos, Slack) with an LLM that answers citing the document it
  found. Eleven containers, ~8 GB resident and ~25 GB of disk before indexing
  anything, so it is opt-in and the provisioner refuses to start on too little
  disk. No LLM key is needed to boot; connectors and credentials are configured
  in the UI. See [docs/onyx.md](docs/onyx.md) and
  `examples/knowledge-base.json`.

## [1.1.0] - 2026-09-22

Verified against **Omarchy 4.0.4** on VirtualBox 7.2.6 and Vagrant 2.4.9,
Windows 11 host. Every provisioner was run against a live VM and checked for
idempotency on a second pass.

### Added

- `mise_tools`: extra tools through mise, which is how Omarchy installs coding
  agents. Having `codex` alongside `claude` means switching the default later
  is a flag, not an install.
- `keyboard` now also applies to the running desktop, not just the install. A
  VM whose layout does not match the physical keyboard is a quiet source of
  mistyped passwords and misplaced symbols.
- `az_extensions`: Azure CLI extensions per machine — `azure-cli` ships without
  the `azure-devops` one, so `az repos` does not exist until it is added.
- `screensaver_text`, `screensaver_seconds`, `lock_seconds`: branding and idle
  timing.
- `git-identity`: the identity an agent needs to commit, plus a libsecret
  credential helper so PATs stay out of plaintext.
- `default_agent`: installs a coding agent through mise and records it as
  Omarchy's default. Documented in `docs/agents.md`.
- `AGENTS.md`: how to work on this repo, starting with reading upstream
  before automating it.
- `examples/` with ready-made profiles to copy into `config.local.json`: an
  infrastructure-as-code workstation, a web dev box, and a headless one. Since
  `config.local.json` is gitignored, a setup worth keeping belongs here.

### Changed

- Everything in the repo is now in English: README, changelog, code comments
  and console output. The long README was split into `docs/`.

## [1.0.1] - 2026-09-19

### Fixed

- **Ejecting the install media didn't work, and lied about it.** The desktop
  auto-mounts the ISO and the cidata with `udiskie`, and while the guest has
  them mounted VirtualBox answers `VERR_PDM_MEDIA_LOCKED`. The trigger ignored
  that error, printed that it had ejected them and wrote its done-marker
  anyway — so the cidata, which carries the password hash, stayed attached and
  mounted at `/run/media/<user>/cidata`.

  It now uses `--forceunmount`, and the marker is only written when they really
  came out; otherwise it warns and the next boot retries. Same in
  `scripts\Eject-InstallMedia.ps1`, which now fails instead of staying quiet.

## [1.0.0] - 2026-09-19

First release. Verified end to end against **Omarchy 4.0.4** on VirtualBox
7.2.6 and Vagrant 2.4.9 on Windows 11: unattended install, working Hyprland
desktop, tools installed.

### Added

- Unattended install via a `cidata` drive, the method Omarchy's manual
  documents. `bootstrap.ps1` downloads and verifies the ISO, generates the
  cidata and a dedicated SSH keypair, and builds the empty EFI Vagrant box.
- `cidata` ISO generation with IMAPI2 — no external tooling needed on Windows.
- `passwordless-sudo` provisioner: installs the sudoers rule Vagrant assumes.
- `qt-software-rendering` provisioner: puts QtQuick in software for SDDM's
  greeter and for the session, without which a VM has no desktop.
- `display` provisioner: sets resolution and scale in `monitors.lua`.
- `tools` provisioner: four declarative lists — `omarchy_installs`, `packages`,
  `aur_packages` and `webapps`.
- Automatic ejection of the ISO and the cidata once the install finishes: the
  cidata carries the password hash.
- Cleanup, in the `destroy` trigger, of the folder VirtualBox leaves behind on
  Windows.

### Notes

- No synced folders: Omarchy ships no Guest Additions.
- No disk encryption: it would ask for the LUKS passphrase at every boot and
  break the unattended part.
- Graphics performance is what it is. To just try Omarchy,
  [try-omarchy-windows](https://github.com/omacom/try-omarchy-windows) uses
  QEMU with virgl and performs better.

[1.1.0]: https://github.com/dieguini/omarchy-vagrant/releases/tag/v1.1.0
[1.0.1]: https://github.com/dieguini/omarchy-vagrant/releases/tag/v1.0.1
[1.0.0]: https://github.com/dieguini/omarchy-vagrant/releases/tag/v1.0.0
