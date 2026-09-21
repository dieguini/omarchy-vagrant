# AGENTS.md

Guidance for anyone — human or agent — working on this repo.

## Rule one: read upstream before you write anything

This repo automates someone else's system. Almost every bug in its history came
from assuming how Omarchy works instead of looking. **Before adding a feature or
fixing something, go read the source of what you're automating.** It is all
public, and it is all short.

Where to look, in the order that usually pays off:

| Source | What it answers |
|---|---|
| **The VM itself**, `/usr/bin/omarchy-*` | How a thing actually works today. ~445 plain bash scripts, each self-documenting with `# omarchy:summary=` |
| `omarchy <group> --help` | What exists at all. Start with plain `omarchy` for the group list |
| [omacom/omarchy](https://github.com/omacom/omarchy) → `manual/` | The manual, authoritative. Mirrored at [learn.omacom.io](https://learn.omacom.io/2/the-omarchy-manual) |
| [omacom/omarchy-iso](https://github.com/omacom/omarchy-iso) | The installer. `configs/airootfs/root/configurator` is where the `cidata` format comes from |

Reading a 40-line bash script is faster than debugging a wrong guess, and it is
the only way to know what a version actually does rather than what a blog post
said a year ago.

## The pattern that keeps repeating

**Omarchy's helpers are built for humans, and most of them can't be used from a
provisioner.** They open `fzf` pickers, or `exec` something interactive at the
end. The fix is always the same: read the helper, find the non-interactive
commands it runs underneath, and run those.

Every provisioner in the Vagrantfile is an instance of this. Some worked
examples, so the shape is recognisable:

- **`omarchy-pkg-install` / `omarchy-pkg-aur-install`** are fzf TUIs. Underneath
  they run `pacman -S --noconfirm` and `yay -S --noconfirm`. The `tools`
  provisioner runs those.
- **`omarchy default agent <name>`** sets *and* installs the agent, then `exec`s
  it — which would hang a provisioner forever. The `agent` provisioner does the
  two halves itself: `mise use -g <pkg>`, then write
  `~/.config/omarchy/defaults/agent`.
- **`user_configuration.json`** is not documented as a format anywhere. The
  template in `New-CidataIso.ps1` is lifted from the ISO's own configurator,
  partition arithmetic included.

## What "read it" would have caught

Real mistakes made in this repo, each one avoidable by looking first:

- **Claude Code installed from the AUR.** It ran, so it looked fine. But
  `omarchy-default-agent` only recognises a pre-existing install at
  `~/.local/bin/<agent>` — a pacman package in `/usr/bin` is invisible to it, so
  the menu would have installed a *second* copy through mise. Omarchy installs
  agents through mise. Reading the 70-line script first would have shown that.
- **`config.ssh.sudo_command` for Omarchy's password-protected sudo.** Vagrant
  substitutes `%c` with the *shell* and feeds the command over stdin, so a
  piped password overwrites the command. It fails silently, returning 0.
- **Ejecting the install media without `--forceunmount`.** The desktop
  auto-mounts them with `udiskie`, VirtualBox answers `VERR_PDM_MEDIA_LOCKED`,
  and the trigger reported success anyway because it ignored the exit code.

## House rules

- **Verify against the running VM, not in your head.** If a change claims
  something works, run it. `vagrant provision --provision-with <name>` is fast.
- **Everything twice.** Provisioners run on every `vagrant up`, so they must be
  idempotent and say so: "already configured" rather than doing it again.
- **Never ignore an exit code in a cleanup step.** A step that ignores failure
  isn't a cleanup step, it's a reassuring message.
- **Fix it in the repo, not in the VM.** Then delete it from the VM and confirm
  the provisioner puts it back. Otherwise you've shipped something nobody else
  can reproduce.
- **Defaults stay generic.** `config.json` is what a stranger gets. Personal
  setups go in `config.local.json` (gitignored) or, if worth keeping, a profile
  in `examples/`.
- **No credentials anywhere in the repo.** Not in `config.json`, not in
  examples, not in docs. The VM password is a disposable dev password and is
  treated as public.
- **Pin versions in prose.** "Omarchy 4.0.4, September 2026" ages honestly;
  "the latest version" does not.
