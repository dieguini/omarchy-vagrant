# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Omarchy en VirtualBox, vía Vagrant.
#
# Omarchy 4 no se instala con un script sobre un Arch existente: se instala
# desde su ISO. El camino soportado para hacerlo sin nadie al teclado es el
# "unattended install" del manual: un segundo disco etiquetado `cidata` con la
# configuración, que el instalador detecta y usa en lugar del asistente.
#
# Por eso aquí la caja base está vacía. `bootstrap.ps1` la fabrica, baja la ISO
# y arma el cidata; este Vagrantfile monta las dos ISOs, arranca, y espera a que
# la instalación termine y el sistema reinicie con sshd abierto.

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
# Marca de que la instalación ya terminó: a partir de ahí no volvemos a montar
# la ISO ni el cidata, que lleva el hash de la contraseña.
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

# Sólo los comandos que arrancan la VM necesitan los artefactos; `vagrant
# destroy` o `vagrant status` deben seguir funcionando aunque falten.
if %w[up reload resume provision].include?(ARGV[0])
  missing = { ISO_PATH => 'la ISO de Omarchy',
              CIDATA   => 'el disco cidata',
              SSH_KEY  => 'la llave SSH' }.reject { |path, _| File.exist?(path) }
  unless missing.empty?
    warn ''
    warn 'Falta preparar el entorno. No encuentro:'
    missing.each { |path, what| warn "  - #{what}: #{path}" }
    warn ''
    warn 'Corre primero:  .\bootstrap.ps1'
    warn ''
    exit 1
  end
end

Vagrant.configure('2') do |config|
  config.vm.box              = BOX_NAME
  config.vm.box_check_update = false
  config.vm.guest            = :arch
  config.vm.boot_timeout     = config_data['boot_timeout_seconds']

  # La instalación completa (particionar, bajar paquetes, reiniciar) tarda; el
  # timeout de arranque de arriba es el que cuenta, y es generoso a propósito.
  config.vm.synced_folder '.', '/vagrant', disabled: true

  # Sin carpetas compartidas no hay nada que persistir, y el bloque que Vagrant
  # escribe en /etc/fstab es justo lo que hacía fallar el primer 'up'.
  config.vm.allow_fstab_modification = false

  # Omarchy deja al usuario en 'wheel' pidiendo contraseña, como cualquier
  # instalación normal. Vagrant, en cambio, da por hecho el sudo sin contraseña
  # de sus cajas: sin él fallan tanto sus pasos internos como cualquier
  # provisioner con privileged: true.
  #
  # Y no se arregla con config.ssh.sudo_command: ahí Vagrant sustituye %c por el
  # *shell*, y le pasa el comando por stdin. Meter un 'echo contraseña |' delante
  # le pisa ese stdin, así que el shell recibe EOF y el comando nunca corre --
  # en silencio y con código de salida 0.
  #
  # Así que se instala la regla de sudoers, desde un provisioner sin privilegios
  # que escala él mismo. A partir de ahí la VM se comporta como una caja Vagrant
  # normal. Ponlo en false si prefieres conservar el sudo con contraseña.
  if config_data['passwordless_sudo']
    config.vm.provision 'passwordless-sudo', type: 'shell', privileged: false,
                                             inline: <<~SHELL
      set -eu
      if sudo -n true 2>/dev/null; then
        echo "sudo sin contraseña ya configurado."
        exit 0
      fi
      echo "Instalando /etc/sudoers.d/99-vagrant..."
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

  # Omarchy 4 arranca con SDDM, y tanto su greeter como la barra (omarchy-shell,
  # que es quickshell) son QtQuick. Sobre la GPU emulada de VirtualBox el
  # camino EGL/dmabuf no aguanta: el greeter salía y se cerraba en un segundo, y
  # la barra entraba en bucle de caída con "The Wayland connection experienced a
  # fatal error". Con QtQuick en software ambos funcionan. Hyprland en sí no
  # necesita esto: el compositor sobre vmwgfx va bien.
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

      # Para la sesión del usuario, no solo para el greeter.
      if ! grep -q '^QT_QUICK_BACKEND=' /etc/environment 2>/dev/null; then
        echo 'QT_QUICK_BACKEND=software' >> /etc/environment
        changed=1
      fi

      # Sólo reiniciar si algo cambió: un restart tumba la sesión gráfica abierta.
      if [ "$changed" = 1 ]; then
        echo "Aplicando renderizado por software de Qt y reiniciando SDDM..."
        systemctl restart sddm
      else
        echo "Renderizado por software de Qt ya configurado."
      fi
    SHELL
  end

  # Herramientas extra, declaradas en config.json. Los helpers de Omarchy
  # (omarchy-pkg-install, omarchy-pkg-aur-install) son TUIs de fzf y no sirven
  # aquí, así que se usan los mismos comandos que ellos ejecutan por debajo.
  #
  # Va sin privilegios a propósito: yay se niega a correr como root, y escala
  # solo gracias al provisioner de sudo de más arriba.
  pkgs    = config_data['packages']      || []
  aur     = config_data['aur_packages']  || []
  webapps = config_data['webapps']       || []

  if pkgs.any? || aur.any? || webapps.any?
    webapp_cmds = webapps.map do |w|
      'omarchy-webapp-install ' + [w['name'], w['url'], w['icon']].map { |a|
        Shellwords.escape(a.to_s)
      }.join(' ')
    end.join("\n")

    config.vm.provision 'tools', type: 'shell', privileged: false,
                                 inline: <<~SHELL
      set -eu
      PKGS=#{Shellwords.escape(pkgs.join(' '))}
      AUR=#{Shellwords.escape(aur.join(' '))}

      if [ -n "$PKGS" ] || [ -n "$AUR" ]; then
        echo "Refrescando las bases de datos de pacman..."
        sudo pacman -Sy --noconfirm >/dev/null
      fi

      if [ -n "$PKGS" ]; then
        echo "Paquetes oficiales: $PKGS"
        sudo pacman -S --needed --noconfirm $PKGS
      fi

      if [ -n "$AUR" ]; then
        echo "Paquetes del AUR: $AUR"
        # --answerclean/--answerdiff son lo que evita que yay se plante en
        # "Packages to cleanBuild?" esperando una respuesta que nunca llega.
        yay -S --needed --noconfirm --removemake \\
            --answerclean None --answerdiff None $AUR
        sudo updatedb --prune-bind-mounts=no --add-prunepaths=/.snapshots || true
      fi

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
                  # Disco primero: el disco vacío no arranca nada y cae al DVD;
                  # ya instalado, arranca del disco e ignora la ISO.
                  '--boot1', 'disk', '--boot2', 'dvd', '--boot3', 'none', '--boot4', 'none']

    unless File.exist?(INSTALLED)
      vb.customize ['storageattach', :id, '--storagectl', 'SATA',
                    '--port', '1', '--device', '0', '--type', 'dvddrive', '--medium', ISO_PATH]
      vb.customize ['storageattach', :id, '--storagectl', 'SATA',
                    '--port', '2', '--device', '0', '--type', 'dvddrive', '--medium', CIDATA]
    end
  end

  # Terminada la instalación, saca los dos medios y deja la marca.
  config.trigger.after :up do |trigger|
    trigger.name = 'Desmontar medios de instalación'
    trigger.ruby do |_env, _machine|
      next if File.exist?(INSTALLED)

      [1, 2].each do |port|
        system(vboxmanage, 'storageattach', VM_NAME, '--storagectl', 'SATA',
               '--port', port.to_s, '--device', '0',
               '--type', 'dvddrive', '--medium', 'emptydrive',
               out: File::NULL, err: File::NULL)
      end
      FileUtils.touch(INSTALLED)
      puts 'Medios de instalación desmontados. La VM ya arranca sola desde disco.'
    end
  end

  config.trigger.after :destroy do |trigger|
    trigger.name = 'Limpiar marca de instalación'
    trigger.ruby do |_env, _machine|
      File.delete(INSTALLED) if File.exist?(INSTALLED)

      # VirtualBox en Windows reescribe Logs\VBoxHardening.log justo después de
      # borrar la VM, así que la carpeta sobrevive vacía al destroy. El
      # siguiente 'up' falla al renombrar la VM importada: "Could not rename
      # the directory ... (VERR_ALREADY_EXISTS)". La quitamos, pero solo si no
      # hay nada dentro salvo los logs.
      begin
        props = IO.popen([vboxmanage, 'list', 'systemproperties'], &:read)
        base  = props[/^Default machine folder:\s+(.+)$/, 1]&.strip
        next if base.nil? || base.empty?

        dir = File.join(base, VM_NAME)
        next unless Dir.exist?(dir)

        if (Dir.children(dir) - ['Logs']).empty?
          FileUtils.rm_rf(dir)
          puts "Quitada la carpeta que VirtualBox dejó atrás: #{dir}"
        else
          puts "Ojo: #{dir} sigue ahí y no está vacía. El próximo 'vagrant up' " \
               'fallará al crear la VM hasta que la revises.'
        end
      rescue StandardError => e
        puts "No se pudo limpiar la carpeta de la VM: #{e.message}"
      end
    end
  end

  config.vm.post_up_message = <<~MSG
    Omarchy está arriba.

      Escritorio : la ventana de VirtualBox (Hyprland)
      SSH        : vagrant ssh
      Usuario    : #{config_data['username']}

    Si la sesión gráfica se queda en negro, mira la sección "Gráficos" del README.
  MSG
end
