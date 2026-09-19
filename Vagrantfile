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

  config.ssh.username         = config_data['username']
  config.ssh.private_key_path = SSH_KEY
  config.ssh.insert_key       = false

  (config_data['forwarded_ports'] || []).each do |fp|
    config.vm.network 'forwarded_port', guest: fp['guest'], host: fp['host']
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
