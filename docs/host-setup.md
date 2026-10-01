# Setting up your host

What to install before the first `bootstrap`, per operating system. Everything
after that — `bootstrap`, `vagrant up`, `vagrant ssh` — is the same on all three.

| Host | Bootstrap | Status |
|---|---|---|
| Windows 10/11, x86_64 | `.\bootstrap.ps1` | Verified end to end |
| macOS on **Intel** | `./bootstrap.sh` | Script ready; not yet run end to end on a Mac |
| Linux, x86_64 | `./bootstrap.sh` | cidata generation verified; full `vagrant up` not yet run |
| macOS on **Apple Silicon** (M1–M4) | — | **Not possible** — see below |

All of them need **VirtualBox 7**, **Vagrant**, ~15 GB free disk, and hardware
virtualization enabled in the firmware (Intel VT-x / AMD-V).

## Windows

```powershell
winget install Oracle.VirtualBox Hashicorp.Vagrant Git.Git
```

Git for Windows is there for its `openssl`, which hashes the password — it
doesn't need to be on your `PATH`, the script finds it. Open a new terminal
afterwards so `vagrant` is found, then:

```powershell
git clone https://github.com/dieguini/omarchy-vagrant
cd omarchy-vagrant
.\bootstrap.ps1
vagrant up
```

If VirtualBox reports it can't use hardware virtualization, Hyper-V (or a
feature built on it: WSL2, Windows Sandbox, Memory Integrity) is holding VT-x.
VirtualBox 7 can run on top of Hyper-V, slowly; turning Hyper-V off gives it the
CPU back.

## macOS on Intel

With [Homebrew](https://brew.sh):

```bash
brew install --cask virtualbox vagrant
brew install openssl@3
xcode-select --install        # python3; skip if it says it's already installed
```

**Approve VirtualBox's kernel extension.** The first time, macOS blocks it:
open *System Settings → Privacy & Security*, allow the software from
*Oracle America, Inc.*, and restart. Until then every VM fails with
*"Kernel driver not installed"*.

**Why `openssl@3`:** the `openssl` macOS ships is LibreSSL, and its `passwd`
command can't make the SHA-512 hash the installer expects. You don't need to
put Homebrew's on your `PATH` — `bootstrap.sh` looks for it in both Homebrew
prefixes.

Then:

```bash
git clone https://github.com/dieguini/omarchy-vagrant
cd omarchy-vagrant
./bootstrap.sh
vagrant up
```

## Linux

VirtualBox and Vagrant are best taken from their vendors
([VirtualBox downloads](https://www.virtualbox.org/wiki/Linux_Downloads),
[Vagrant install](https://developer.hashicorp.com/vagrant/install)) — the
packages some distributions carry lag behind. The helpers come from your
package manager:

```bash
# Debian / Ubuntu
sudo apt install python3 openssl xorriso

# Fedora
sudo dnf install python3 openssl xorriso

# Arch (VirtualBox and Vagrant are in the official repos here)
sudo pacman -S --needed virtualbox virtualbox-host-modules-arch vagrant python openssl xorriso
```

`genisoimage` or `mkisofs` work in place of `xorriso` if that's what you have.

Two things VirtualBox needs on Linux:

- **Its kernel module.** `VBoxManage --version` warning about *"kernel driver
  not installed"* means `vboxdrv` isn't loaded. With Secure Boot on, the module
  has to be signed before the kernel will load it — your distribution's
  VirtualBox notes explain how.
- **VT-x for itself.** If KVM holds it (*"VirtualBox can't operate in VMX root
  mode"*), unload KVM while you use VirtualBox: `sudo modprobe -r kvm_intel`
  (or `kvm_amd`).

Then:

```bash
git clone https://github.com/dieguini/omarchy-vagrant
cd omarchy-vagrant
./bootstrap.sh
vagrant up
```

## Apple Silicon (M1–M4): not possible

Omarchy publishes an x86_64 ISO only, and VirtualBox on Apple Silicon runs ARM
guests only — there is no x86 emulation in it. `bootstrap.sh` checks for this
and stops before downloading anything. Full x86 emulation (QEMU / UTM) can
technically boot it, but far too slowly for a desktop to be usable. Use an
Intel Mac, or a Windows or Linux x86_64 machine.

## Checking you're ready

Each of these should print a version:

```bash
VBoxManage --version
vagrant --version
```

`bootstrap` checks the rest itself and names whatever is missing before it
starts the 6 GB download.
