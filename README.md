# omarchy-vagrant

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?style=flat&logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/g0l14t)

[Omarchy](https://omarchy.org/) — el Arch + Hyprland de DHH — levantado en una VM
de VirtualBox con un `vagrant up`, sin tocar el asistente de instalación.

## Cómo funciona

Omarchy 4 ya **no** se instala con un script sobre un Arch existente: se instala
desde su propia ISO. Lo que sí soporta, y es el camino que usa este repo, es el
[unattended install](https://learn.omacom.io/2/the-omarchy-manual/51/unattended-installs)
del manual:

> Si el instalador encuentra un segundo disco etiquetado `cidata` con sus
> archivos de configuración, los copia, se salta el asistente entero y reinicia
> solo en el sistema terminado.

`cidata` es la etiqueta NoCloud de cloud-init, así que es exactamente el mismo
mecanismo que se usa en Proxmox o Packer. Aquí se traduce a tres piezas que
`bootstrap.ps1` fabrica antes del primer arranque:

| Pieza | Qué es |
|---|---|
| `.build\omarchy-<ver>.iso` | La ISO oficial, descargada y verificada contra su SHA-256 publicado |
| `.build\cidata.iso` | Una ISO diminuta con `user_configuration.json`, `user_credentials.json` y tu `authorized_keys` |
| Caja `omarchy-empty-<N>g` | Una caja Vagrant **vacía**: EFI, controladora SATA y un disco virgen |

La caja vacía existe porque Vagrant necesita algo que arrancar y no hay caja de
Omarchy. El orden de arranque pone el disco primero: vacío no arranca nada y cae
al DVD, y una vez instalado arranca del disco e ignora la ISO. Es el mismo truco
que el ejemplo de Proxmox del manual.

Como `cidata` incluye `authorized_keys`, el instalador habilita `sshd` y abre el
firewall — cosa que una instalación normal de Omarchy no hace — y por eso
`vagrant ssh` funciona al terminar.

## Requisitos

- Windows con **VirtualBox 7** y **Vagrant**
- **Git para Windows** (aporta el `openssl` que genera el hash SHA-512 de la contraseña)
- ~15 GB libres: 6 GB de ISO más lo que crezca el disco de la VM
- Virtualización activada en la BIOS, y Hyper-V apagado si VirtualBox se queja

## Uso

```powershell
git clone <este-repo> omarchy-vagrant
cd omarchy-vagrant
.\bootstrap.ps1
vagrant up
```

`bootstrap.ps1` baja la ISO (~6 GB, con reanudación: si se corta, vuelve a
correrlo), arma el `cidata`, genera un par de llaves ed25519 dedicado y registra
la caja base. `vagrant up` abre la ventana de VirtualBox, el instalador corre
solo, la VM reinicia y Vagrant espera por SSH — en total unos 10-20 minutos según
tu conexión.

Cuando termina:

```powershell
vagrant ssh          # shell en la VM
vagrant halt         # apagar
vagrant up           # volver a encender
vagrant destroy -f   # borrar y empezar de cero
```

El escritorio Hyprland vive en la ventana de VirtualBox; SSH es para trabajar
desde la terminal de Windows.

## Configuración

`config.json` trae los valores por defecto. **No lo edites**: crea un
`config.local.json` al lado con solo las claves que quieras cambiar. Ese archivo
está en `.gitignore`, así que tu contraseña y tu identidad no acaban en git.

```json
{
  "username": "diego",
  "password": "algo-mejor-que-el-default",
  "full_name": "Diego Jauregui",
  "email_address": "diego@example.com",
  "timezone": "America/Mexico_City",
  "keyboard": "latam",
  "memory_mb": 12288,
  "cpus": 6,
  "disk_gb": 96,
  "forwarded_ports": [{ "guest": 3000, "host": 3000 }]
}
```

Claves disponibles, con sus defaults en `config.json`:

| Clave | Default | Notas |
|---|---|---|
| `omarchy_version` | `4.0.4` | Determina la URL de la ISO |
| `iso_url`, `iso_sha256` | vacío | Para fijar una ISO propia; si están vacíos se derivan de la versión |
| `vm_name`, `hostname` | `omarchy` | |
| `cpus`, `memory_mb`, `disk_gb` | 4 / 8192 / 64 | `disk_gb` queda grabado en la caja base |
| `gui` | `true` | Ponlo en `false` y te quedas solo con SSH |
| `accelerate_3d`, `vram_mb` | `true` / 128 | Ver "Gráficos" |
| `resolution`, `scale`, `gdk_scale` | `1920x1080@60` / 1 / 1 | Ver "Resolución". Deja `resolution` vacío para no tocar nada |
| `software_rendering` | `true` | Pone QtQuick en software, sin lo cual no hay escritorio. Ver "Gráficos" |
| `passwordless_sudo` | `true` | Instala la regla de sudoers que Vagrant da por hecha. Ver "Seguridad" |
| `username`, `password` | `omarchy` | El usuario debe cumplir las reglas de Omarchy: minúsculas, empieza por letra o `_` |
| `full_name`, `email_address` | vacío | Se usan para la identidad de git dentro de la VM |
| `timezone`, `keyboard` | `UTC` / `us` | |
| `boot_timeout_seconds` | 3600 | Cubre toda la instalación, no solo el arranque |
| `forwarded_ports` | `[]` | Lista de `{guest, host}` |

### Instalar herramientas

Cuatro listas en `config.local.json` declaran qué lleva la VM además de lo que
trae Omarchy. Se aplican en cada `vagrant up`, y son idempotentes:

```json
{
  "packages": ["httpie", "jq"],
  "aur_packages": ["visual-studio-code-bin"],
  "omarchy_installs": ["editor vscode", "dev-env node", "browser brave"],
  "webapps": [
    { "name": "Claude", "url": "https://claude.ai", "icon": "claude" }
  ]
}
```

- `packages` → `pacman`, repos oficiales (y los de Omarchy).
- `aur_packages` → `yay`. El provisioner pasa `--answerclean None --answerdiff
  None`, que es lo que evita que `yay` se plante en *"Packages to cleanBuild?"*
  esperando una respuesta que en un provisioner no llega nunca.
- `omarchy_installs` → `omarchy install …`, los instaladores curados de Omarchy.
  **Prefiere esta lista cuando exista una entrada para lo que quieres**, porque
  no solo instalan: `editor vscode` apaga la autoactualización de VS Code (las
  actualizaciones las lleva Omarchy), lo apunta a `gnome-libsecret` y le aplica
  el tema del sistema. Mira el catálogo con `vagrant ssh -c 'omarchy install --help'`:
  hay `editor`, `browser`, `dev-env` (ruby, node, bun, go, python, rust, java…),
  `ai`, `docker dbs` y más.
- `webapps` → `omarchy-webapp-install`, que crea el lanzador de una web como si
  fuera una app. El `icon` puede ser un nombre de icono o la URL de uno.

Las dos primeras listas son la vía de escape para lo que no tenga instalador
curado. El orden de ejecución es el de arriba.

Para aplicarlas sin reiniciar la VM:

```powershell
vagrant provision --provision-with tools
```

Un apunte de Arch: el provisioner hace `pacman -Sy` para refrescar las bases de
datos, no `-Syu`. Es a propósito — un `-Syu` dentro de un `vagrant up` puede
convertirse en una actualización de media hora y hasta pedir reinicio. La
contrapartida es el riesgo clásico de actualización parcial, así que si la VM
lleva tiempo viva, actualízala antes con `vagrant ssh -c omarchy-update`.

Después de tocar la configuración:

```powershell
vagrant destroy -f
.\bootstrap.ps1 -SkipIso -Force   # regenera cidata y caja sin rebajar los 6 GB
vagrant up
```

## Gráficos

Hyprland corre bien sobre la GPU emulada: VirtualBox da VMSVGA, el kernel carga
`vmwgfx`, aparece `/dev/dri/card0` y el compositor modesetea sin problema.

Lo que **no** aguanta ese camino es QtQuick. Omarchy 4 arranca con SDDM, y tanto
su greeter como la barra (`omarchy-shell`, que es quickshell) son QtQuick sobre
EGL/dmabuf. Sin arreglar, el resultado es una pantalla negra en dos actos: el
greeter arranca y se cierra al segundo (`Greeter stopped` en el journal de
`sddm`), y si entras igualmente, la barra queda en bucle de caída con
`The Wayland connection experienced a fatal error: Invalid argument`.

El Vagrantfile lo resuelve con un provisioner que pone QtQuick en software, en
los dos sitios que hacen falta:

- `/etc/sddm.conf.d/99-vagrant-vm-rendering.conf` → `GreeterEnvironment=QT_QUICK_BACKEND=software`, para el greeter;
- `QT_QUICK_BACKEND=software` en `/etc/environment`, para la sesión del usuario.

Hyprland en sí no necesita nada de esto. Si prefieres desactivarlo — por ejemplo
para probar sobre otro hipervisor — pon `"software_rendering": false`.

Si aun así la pantalla se queda en negro, `vagrant ssh` sigue funcionando; mira
`journalctl -b -u sddm` y el log del compositor en `/run/user/<uid>/hypr/*/hyprland.log`.
Apagar el 3D emulado (`"accelerate_3d": false` y `vagrant reload`) es lo
siguiente que probaría.

Si lo que quieres es *probar* Omarchy en Windows y no automatizarlo, el propio
proyecto publica [try-omarchy-windows](https://github.com/omacom/try-omarchy-windows),
que usa QEMU con virgl/Venus y da mejor aceleración gráfica que VirtualBox. Este
repo es para cuando quieres la VM **reproducible y descriptible en código**.

## Resolución

Sin Guest Additions no hay auto-resize de la ventana, y lo que Omarchy elige
solo dentro de una VM se queda corto: modo `preferred` da **1280x800** y la
escala automática se va a **2**, o sea un escritorio efectivo de 640x400 donde
ni sus propios diálogos caben. El síntoma es texto enorme y ventanas cortadas.

El provisioner `display` lo arregla escribiendo `~/.config/hypr/monitors.lua`
con lo que digan `resolution`, `scale` y `gdk_scale`. Omarchy 4 configura
Hyprland en Lua, así que ese es el sitio; `hyprctl keyword` no sirve y responde
*"can't work with non-legacy parsers"*.

La GPU emulada acepta modos hasta 4096x2160. Para ver la lista:

```powershell
vagrant ssh -c 'hyprctl monitors all'
```

Cambia `resolution` y aplícalo sin reiniciar la VM:

```powershell
vagrant provision --provision-with display
```

Ese archivo se reescribe en cada `vagrant up`, así que configura la resolución
desde `config.local.json`, no editándolo a mano. Si prefieres gestionarlo tú,
pon `"resolution": ""` y el provisioner no se ejecuta.

Si el escritorio se queda más grande que la ventana de VirtualBox, en el menú
**View** tienes *Scaled Mode* y los ajustes de escala de la ventana.

## Cuando algo se queda a medias

Un `vagrant up` interrumpido — un Ctrl+C, o un error de VirtualBox a mitad —
deja rastro en dos sitios, y el siguiente intento falla con un mensaje que no
apunta a la causa.

**"another process is already executing an action on the machine"**, sin ningún
proceso de Vagrant vivo. Es un candado huérfano: Vagrant escribe un archivo
`action_<nombre>` en `.vagrant\machines\default\virtualbox\` mientras ejecuta
cada acción, y si el proceso muere no lo borra. Comprueba primero que de verdad
no hay nada corriendo, y luego bórralo:

```powershell
Get-Process ruby,vagrant -ErrorAction SilentlyContinue
Remove-Item .\.vagrant\machines\default\virtualbox\action_*
```

**"Could not rename the directory ... (VERR_ALREADY_EXISTS)"** al crear la VM.
VirtualBox dejó atrás la carpeta de una VM anterior. El trigger de `destroy` se
encarga de esto, pero si llegas a verlo, mira qué hay dentro y quítala:

```powershell
Get-ChildItem "$env:USERPROFILE\VirtualBox VMs\omarchy" -Recurse
Remove-Item "$env:USERPROFILE\VirtualBox VMs\omarchy" -Recurse
```

Ese error además deja una VM a medio importar y registrada, con un nombre tipo
`omarchy-empty-64g-builder_<números>`. Quítala también:

```powershell
VBoxManage list vms
VBoxManage unregistervm "<ese-nombre>" --delete
```

Después de limpiar, `vagrant status` te dice desde dónde sigues: `not created`
significa empezar de nuevo con `vagrant up`, y `poweroff` que la VM sobrevivió y
`vagrant up` la retoma donde estaba.

## Qué no hay

- **Carpetas compartidas.** Omarchy no trae las Guest Additions, así que
  `/vagrant` está deshabilitado a propósito. Usa `vagrant ssh` con `scp`, o un
  `forwarded_port`.
- **Cifrado de disco.** Una instalación cifrada pide la frase LUKS en cada
  arranque, lo que rompe lo desatendido. El manual dice lo mismo.
- **Bloque de Vagrant en `/etc/fstab`.** Sin carpetas compartidas no hay nada que
  persistir, y ese paso es justo el que hacía fallar el primer `vagrant up`, así
  que está desactivado con `allow_fstab_modification = false`.

Sí puedes añadir tus propios `config.vm.provision "shell"`, con o sin
`privileged: true`: los dos provisioners que trae el repo dejan la VM en un
estado donde eso funciona como en cualquier caja Vagrant.

## Seguridad

Omarchy deja al usuario en `wheel` pidiendo contraseña, como cualquier
instalación normal. Vagrant da por hecho el sudo sin contraseña de sus cajas: sin
él fallan sus propios pasos y cualquier provisioner con `privileged: true`. Por
eso un provisioner instala `/etc/sudoers.d/99-vagrant` con `NOPASSWD`, que es la
convención de todas las cajas Vagrant. Es una VM de desarrollo desechable; si no
te vale, `"passwordless_sudo": false` y lo dejas como lo instaló Omarchy.

Omarchy trae su propio `omarchy sudo passwordless`, pero no sirve para esto: es
un *toggle* que concede el permiso 15 minutos por defecto y arma un timer de
systemd para retirarlo. Está pensado para una sesión interactiva, no para dejar
la máquina en un estado estable.

Ojo con un detalle contraintuitivo: esto **no** se arregla con
`config.ssh.sudo_command`. Ahí Vagrant sustituye `%c` por el *shell*, y le pasa
el comando por stdin. Anteponer `echo contraseña |` pisa ese stdin, el shell
recibe EOF, y el provisioner no corre — en silencio y devolviendo 0.


`cidata.iso` lleva el hash SHA-512 de la contraseña del usuario. Por eso:

- vive en `.build\`, que está en `.gitignore`;
- el Vagrantfile lo desmonta de la VM en cuanto la instalación termina, y deja
  una marca en `.build\installed-<vm>` para no volver a montarlo. Si ese paso
  falla, avisa y **no** pone la marca, para que el siguiente arranque lo
  reintente; `scripts\Eject-InstallMedia.ps1` lo hace a mano.

El desmontaje va con `--forceunmount`, y no es opcional: el escritorio de
Omarchy automonta los dos medios con `udiskie`, y con el guest teniéndolos
montados VirtualBox responde `VERR_PDM_MEDIA_LOCKED` y se niega a expulsarlos.
Si alguna vez ves el `cidata` en `/run/media/<usuario>/cidata`, es que ese paso
no se completó.

La contraseña viaja también dentro del provisioner de sudo, en el script que
Vagrant sube a `/tmp/vagrant-shell`. Otra razón para no reutilizar en esta VM
una contraseña que uses en otro sitio.

La llave SSH de `.build\ssh\` es exclusiva de esta VM: no se usa la llave
insegura de Vagrant.

## Estructura

```
bootstrap.ps1                    Orquesta los tres pasos de preparación
config.json                      Defaults (versionado)
config.local.json                Tus overrides (ignorado por git)
Vagrantfile                      Define la VM, monta los medios, desmonta al final
scripts/
  lib.ps1                        Config, rutas, creación de ISO con IMAPI2
  Get-OmarchyIso.ps1             Descarga + verificación SHA-256
  New-CidataIso.ps1              Genera los archivos del instalador y la ISO cidata
  New-EmptyBox.ps1               Fabrica y registra la caja Vagrant vacía
  Eject-InstallMedia.ps1         Desmonta ISO y cidata a mano
```

La plantilla de `user_configuration.json` sale del configurador de la ISO
([omacom/omarchy-iso](https://github.com/omacom/omarchy-iso), en
`configs/airootfs/root/configurator`). Si Omarchy cambia ese formato en una
versión futura, ahí es donde hay que mirar.

## Versiones

El historial de cambios está en [CHANGELOG.md](CHANGELOG.md). Cada release
indica contra qué versión de Omarchy se verificó.

## Licencia

MIT. Omarchy es de Basecamp/omacom y tiene su propia licencia.
