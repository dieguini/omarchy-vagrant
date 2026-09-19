# Security

This is a disposable development VM. Read this before treating it as anything
more.

## The sudo rule

Omarchy leaves the user in `wheel` **asking for a password**, like any normal
install. Vagrant assumes the passwordless sudo its own boxes ship with: without
it, Vagrant's internal steps fail and so does every `privileged: true`
provisioner.

So a provisioner installs `/etc/sudoers.d/99-vagrant` with `NOPASSWD`, which is
the convention every Vagrant box follows. To keep Omarchy's behaviour instead,
set `"passwordless_sudo": false`.

Omarchy ships its own `omarchy sudo passwordless`, but it doesn't serve here:
it's a *toggle* that grants the privilege for 15 minutes by default and arms a
systemd timer to take it away. That's built for an interactive session, not for
leaving a machine in a stable state.

### The trap worth remembering

This is **not** fixed with `config.ssh.sudo_command`. There Vagrant substitutes
`%c` with the *shell*, and feeds the command over stdin. Prefixing an
`echo password |` overwrites that stdin, the shell receives EOF, and the
provisioner never runs — silently, and returning 0. Vagrant reports success.

## Where the password lives

`cidata.iso` carries the SHA-512 hash of the user's password. Therefore:

- it lives in `.build\`, which is gitignored;
- the Vagrantfile ejects it from the VM as soon as the install finishes, and
  leaves a marker at `.build\installed-<vm>` so it isn't attached again. If that
  step fails it says so and does **not** write the marker, so the next boot
  retries; `scripts\Eject-InstallMedia.ps1` does it by hand.

The eject uses `--forceunmount`, and that isn't optional: Omarchy's desktop
auto-mounts both media with `udiskie`, and while the guest has them mounted
VirtualBox answers `VERR_PDM_MEDIA_LOCKED` and refuses. **If you ever see the
cidata at `/run/media/<user>/cidata`, that step didn't complete.**

The password also travels inside the sudo provisioner, in the script Vagrant
uploads to `/tmp/vagrant-shell`. One more reason not to reuse a password here
that you use anywhere else.

## The SSH key

The keypair in `.build\ssh\` is generated for this VM alone — Vagrant's
well-known insecure key is never used.
