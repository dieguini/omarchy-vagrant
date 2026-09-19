# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Omarchy in VirtualBox, via Vagrant.
#
# Omarchy 4 can't be installed with a script on top of an existing Arch system:
# it installs from its own ISO. The supported way to do that with nobody at the
# keyboard is the manual's "unattended install": a second drive labeled `cidata`
# carrying the configuration, which the installer finds and uses instead of the
# setup wizard.
#
# That's why the base box here is empty. `bootstrap.ps1` builds it, downloads
# the ISO and assembles the cidata; this Vagrantfile attaches both ISOs, boots,
# and waits for the install to finish and the system to come back with sshd open.

require 'json'
require 'fileutils'
require 'shellwords'

ROOT  = File.expand_path(File.dirname(__FILE__))
BUILD = File.join(ROOT, '.build')

config_data = JSON.parse(File.read(File.join(ROOT, 'config.json')))
local_path  = File.join(ROOT, 'config.local.json')
config_data.merge!(JSON.parse(File.read(local_path))) if File.exist?(local_path)

VM_NAME   = config_data['vm_name']
BOX_NAME  = "omarchy-empty-#{config_data['disk_gb']}g"
ISO_PATH  = File.join(BUILD, "omarchy-#{config_data['omarchy_version']}.iso")
CIDATA    = File.join(BUILD, 'cidata.iso')
SSH_KEY   = File.join(BUILD, 'ssh', 'id_ed25519')
# Marks that the install finished: from then on we stop attaching the ISO and
# the cidata, which carries the password hash.
INSTALLED = File.join(BUILD, "installed-#{VM_NAME}")

def vboxmanage
  candidates = []
  %w[VBOX_MSI_INSTALL_PATH VBOX_INSTALL_PATH].each do |var|
    next unless ENV[var]
    candidates << File.join(ENV[var].sub(%r{[\\/]$}, ''), 'VBoxManage.exe')
  end
  candidates << 'C:/Program Files/Oracle/VirtualBox/VBoxManage.exe'
  candidates.find { |c| File.exist?(c) } || 'VBoxManage'
end

# Only the commands that boot the VM need the artifacts; `vagrant destroy` and
# `vagrant status` must keep working even when they're missing.
if %w[up reload resume provision].include?(ARGV[0])
  missing = { ISO_PATH => 'the Omarchy ISO',
              CIDATA   => 'the cidata drive',
              SSH_KEY  => 'the SSH key' }.reject { |path, _| File.exist?(path) }
  unless missing.empty?
    warn ''
    warn "The environment isn't prepared yet. Missing:"
    missing.each { |path, what| warn "  - #{what}: #{path}" }
    warn ''
    warn 'Run this first:  .\bootstrap.ps1'
    warn ''
    exit 1
  end
end

Vagrant.configure('2') do |config|
  config.vm.box              = BOX_NAME
  config.vm.box_check_update = false
  config.vm.guest            = :arch
  config.vm.boot_timeout     = config_data['boot_timeout_seconds']

  # The whole install (partitioning, downloading packages, rebooting) happens
  # inside that boot window, which is why the timeout above is so generous.
  config.vm.synced_folder '.', '/vagrant', disabled: true

  # With no synced folders there is nothing to persist, and the block Vagrant
  # writes into /etc/fstab is exactly what broke the first 'up'.
  config.vm.allow_fstab_modification = false

  # Omarchy leaves the user in 'wheel' asking for a password, like any normal
  # install. Vagrant, on the other hand, assumes the passwordless sudo its own
  # boxes ship with: without it both its internal steps and every provisioner
  # with privileged: true fail.
  #
  # And config.ssh.sudo_command does NOT fix it: there Vagrant substitutes %c
  # with the *shell*, and feeds the command over stdin. Prefixing an
  # 'echo password |' overwrites that stdin, so the shell gets EOF and the
  # command never runs -- silently, and with exit code 0.
  #
  # So the sudoers rule gets installed instead, from an unprivileged provisioner
  # that escalates on its own. From then on the VM behaves like a normal Vagrant
  # box. Set this to false to keep Omarchy's password-protected sudo.
  if config_data['passwordless_sudo']
    config.vm.provision 'passwordless-sudo', type: 'shell', privileged: false,
                                             inline: <<~SHELL
      set -eu
      if sudo -n true 2>/dev/null; then
        echo "Passwordless sudo already configured."
        exit 0
      fi
      echo "Installing /etc/sudoers.d/99-vagrant..."
      echo #{Shellwords.escape(config_data['password'])} | sudo -S -p '' bash -c \\
        "echo '#{config_data['username']} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/99-vagrant &&
         chmod 440 /etc/sudoers.d/99-vagrant &&
         visudo -c -q"
    SHELL
  end

  config.ssh.username         = config_data['username']
  config.ssh.private_key_path = SSH_KEY
  config.ssh.insert_key       = false

  (config_data['forwarded_ports'] || []).each do |fp|
    config.vm.network 'forwarded_port', guest: fp['guest'], host: fp['host']
  end

  # Omarchy 4 boots into SDDM, and both its greeter and the bar (omarchy-shell,
  # which is quickshell) are QtQuick. On VirtualBox's emulated GPU the
  # EGL/dmabuf path doesn't survive: the greeter started and closed a second
  # later, and the bar entered a crash loop with "The Wayland connection
  # experienced a fatal error". With QtQuick in software both work. Hyprland
  # itself needs none of this: the compositor runs fine on vmwgfx.
  if config_data['software_rendering']
    config.vm.provision 'qt-software-rendering', type: 'shell', privileged: true,
                                                 inline: <<~SHELL
      set -eu
      changed=0

      conf=/etc/sddm.conf.d/99-vagrant-vm-rendering.conf
      want='[General]
      GreeterEnvironment=QT_QUICK_BACKEND=software'
      if [ ! -f "$conf" ] || [ "$(cat "$conf")" != "$want" ]; then
        mkdir -p /etc/sddm.conf.d
        printf '%s\\n' "$want" > "$conf"
        changed=1
      fi

      # For the user's session too, not just the greeter.
      if ! grep -q '^QT_QUICK_BACKEND=' /etc/environment 2>/dev/null; then
        echo 'QT_QUICK_BACKEND=software' >> /etc/environment
        changed=1
      fi

      # Only restart when something changed: a restart kills the open session.
      if [ "$changed" = 1 ]; then
        echo "Applying Qt software rendering and restarting SDDM..."
        systemctl restart sddm
      else
        echo "Qt software rendering already configured."
      fi
    SHELL
  end

  # Desktop resolution. Without Guest Additions there is no auto-resize, and
  # what Omarchy picks on its own inside a VM is cramped: mode 'preferred'
  # gives 1280x800 and the automatic scale goes to 2, an effective desktop of
  # 640x400 where its own dialogs don't fit.
  #
  # Omarchy 4 configures Hyprland in Lua, so this is written to monitors.lua;
  # 'hyprctl keyword' won't do ("can't work with non-legacy parsers"). The
  # emulated GPU offers modes up to 4096x2160: list them with
  # 'hyprctl monitors all'.
  if config_data['resolution'].to_s != ''
    config.vm.provision 'display', type: 'shell', privileged: false,
                                   inline: <<~SHELL
      set -eu
      conf="$HOME/.config/hypr/monitors.lua"
      mkdir -p "$(dirname "$conf")"

      want='-- Generated by omarchy-vagrant: change resolution/scale/gdk_scale in
      -- config.json or config.local.json, not this file, which gets rewritten.
      local omarchy_gdk_scale = #{config_data['gdk_scale'] || 1}
      hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
      hl.monitor({ output = "", mode = "#{config_data['resolution']}", position = "auto", scale = #{config_data['scale'] || 1} })'

      if [ "$(cat "$conf" 2>/dev/null)" = "$want" ]; then
        echo "Resolution already configured (#{config_data['resolution']})."
      else
        printf '%s\\n' "$want" > "$conf"
        echo "Wrote monitors.lua: #{config_data['resolution']}, scale #{config_data['scale'] || 1}."

        # Reload only if a session is alive; on the first up there isn't one yet.
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        sig=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1 || true)
        if [ -n "$sig" ]; then
          HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl reload >/dev/null 2>&1 || true
          echo "Hyprland reloaded."
        fi
      fi
    SHELL
  end

  # Extra tooling, declared in config.json. Omarchy's own helpers
  # (omarchy-pkg-install, omarchy-pkg-aur-install) are fzf TUIs and are no use
  # here, so this runs the same commands they run underneath.
  #
  # Unprivileged on purpose: yay refuses to run as root, and escalates by itself
  # thanks to the sudo provisioner above.
  pkgs     = config_data['packages']         || []
  aur      = config_data['aur_packages']     || []
  webapps  = config_data['webapps']          || []
  installs = config_data['omarchy_installs'] || []

  if pkgs.any? || aur.any? || webapps.any? || installs.any?
    webapp_cmds = webapps.map do |w|
      'omarchy-webapp-install ' + [w['name'], w['url'], w['icon']].map { |a|
        Shellwords.escape(a.to_s)
      }.join(' ')
    end.join("\n")

    # 'omarchy install ...' does more than install: the VS Code one turns off
    # its auto-updater, points it at gnome-libsecret and applies the Omarchy
    # theme. That's why it runs after the AUR list and is worth preferring over
    # installing the bare package.
    install_cmds = installs.map do |i|
      cmd = 'omarchy install ' + i.to_s.split.map { |t| Shellwords.escape(t) }.join(' ')
      "echo \"> #{cmd}\"\n#{cmd}"
    end.join("\n")

    config.vm.provision 'tools', type: 'shell', privileged: false,
                                 inline: <<~SHELL
      set -eu
      PKGS=#{Shellwords.escape(pkgs.join(' '))}
      AUR=#{Shellwords.escape(aur.join(' '))}

      if [ -n "$PKGS" ] || [ -n "$AUR" ]; then
        echo "Refreshing pacman databases..."
        sudo pacman -Sy --noconfirm >/dev/null
      fi

      if [ -n "$PKGS" ]; then
        echo "Official packages: $PKGS"
        sudo pacman -S --needed --noconfirm $PKGS
      fi

      if [ -n "$AUR" ]; then
        echo "AUR packages: $AUR"
        # --answerclean/--answerdiff are what stop yay from hanging on
        # "Packages to cleanBuild?" waiting for an answer that never comes.
        yay -S --needed --noconfirm --removemake \\
            --answerclean None --answerdiff None $AUR
        sudo updatedb --prune-bind-mounts=no --add-prunepaths=/.snapshots || true
      fi

      #{install_cmds}

      #{webapp_cmds}
    SHELL
  end

  config.vm.provider 'virtualbox' do |vb|
    vb.name   = VM_NAME
    vb.gui    = config_data['gui']
    vb.memory = config_data['memory_mb']
    vb.cpus   = config_data['cpus']

    vb.customize ['modifyvm', :id,
                  '--firmware', 'efi',
                  '--ioapic', 'on',
                  '--rtcuseutc', 'on',
                  '--graphicscontroller', 'vmsvga',
                  '--vram', config_data['vram_mb'].to_s,
                  '--accelerate3d', config_data['accelerate_3d'] ? 'on' : 'off',
                  '--clipboard-mode', 'bidirectional',
                  # Disk first: the empty disk boots nothing and falls through
                  # to the DVD; once installed it boots from disk and ignores
                  # the ISO.
                  '--boot1', 'disk', '--boot2', 'dvd', '--boot3', 'none', '--boot4', 'none']

    unless File.exist?(INSTALLED)
      vb.customize ['storageattach', :id, '--storagectl', 'SATA',
                    '--port', '1', '--device', '0', '--type', 'dvddrive', '--medium', ISO_PATH]
      vb.customize ['storageattach', :id, '--storagectl', 'SATA',
                    '--port', '2', '--device', '0', '--type', 'dvddrive', '--medium', CIDATA]
    end
  end

  # Once the install is done, eject both media and drop the marker.
  config.trigger.after :up do |trigger|
    trigger.name = 'Eject install media'
    trigger.ruby do |_env, _machine|
      next if File.exist?(INSTALLED)

      # --forceunmount is not optional: udiskie auto-mounts both media on the
      # desktop, and while the guest has them mounted VirtualBox refuses to
      # eject with VERR_PDM_MEDIA_LOCKED.
      failed = [1, 2].reject do |port|
        system(vboxmanage, 'storageattach', VM_NAME, '--storagectl', 'SATA',
               '--port', port.to_s, '--device', '0',
               '--type', 'dvddrive', '--medium', 'emptydrive', '--forceunmount',
               out: File::NULL, err: File::NULL)
      end

      # The marker is only written if they really came out: otherwise the next
      # boot must try again instead of assuming the job is done.
      if failed.empty?
        FileUtils.touch(INSTALLED)
        puts 'Install media ejected. The VM now boots from disk on its own.'
      else
        puts "WARNING: could not eject the media on port(s) #{failed.join(', ')}."
        puts 'The cidata carries your password hash and the desktop auto-mounts it.'
        puts 'Run scripts\\Eject-InstallMedia.ps1 to remove them.'
      end
    end
  end

  config.trigger.after :destroy do |trigger|
    trigger.name = 'Clean up install marker'
    trigger.ruby do |_env, _machine|
      File.delete(INSTALLED) if File.exist?(INSTALLED)

      # On Windows, VirtualBox rewrites Logs\VBoxHardening.log right after
      # deleting the VM, so the folder survives the destroy. The next 'up' then
      # fails to rename the imported VM: "Could not rename the directory ...
      # (VERR_ALREADY_EXISTS)". Remove it, but only when nothing but the logs
      # is left inside.
      begin
        props = IO.popen([vboxmanage, 'list', 'systemproperties'], &:read)
        base  = props[/^Default machine folder:\s+(.+)$/, 1]&.strip
        next if base.nil? || base.empty?

        dir = File.join(base, VM_NAME)
        next unless Dir.exist?(dir)

        if (Dir.children(dir) - ['Logs']).empty?
          FileUtils.rm_rf(dir)
          puts "Removed the folder VirtualBox left behind: #{dir}"
        else
          puts "Heads up: #{dir} is still there and not empty. The next " \
               "'vagrant up' will fail to create the VM until you look at it."
        end
      rescue StandardError => e
        puts "Could not clean up the VM folder: #{e.message}"
      end
    end
  end

  config.vm.post_up_message = <<~MSG
    Omarchy is up.

      Desktop  : the VirtualBox window (Hyprland)
      SSH      : vagrant ssh
      User     : #{config_data['username']}

    If the graphical session comes up black, see the "Graphics" section of the README.
  MSG
end
