# omarchy-vagrant

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
| `username`, `password` | `omarchy` | El usuario debe cumplir las reglas de Omarchy: minúsculas, empieza por letra o `_` |
| `full_name`, `email_address` | vacío | Se usan para la identidad de git dentro de la VM |
| `timezone`, `keyboard` | `UTC` / `us` | |
| `boot_timeout_seconds` | 3600 | Cubre toda la instalación, no solo el arranque |
| `forwarded_ports` | `[]` | Lista de `{guest, host}` |

Después de tocar la configuración:

```powershell
vagrant destroy -f
.\bootstrap.ps1 -SkipIso -Force   # regenera cidata y caja sin rebajar los 6 GB
vagrant up
```

## Gráficos

Hyprland necesita un dispositivo DRM. En VirtualBox eso significa VMSVGA con el
driver `vmwgfx` del kernel, que es lo que este Vagrantfile configura (VMSVGA,
128 MB de VRAM, aceleración 3D). Aun así es el punto más frágil de todo el
montaje: es hardware emulado y Hyprland no lo tiene entre sus plataformas de
primera.

Si la sesión gráfica arranca en negro:

1. Entra por `vagrant ssh` (eso sigue funcionando aunque el escritorio no).
2. Prueba a forzar el renderizado por software:
   ```bash
   echo 'export WLR_RENDERER_ALLOW_SOFTWARE=1' >> ~/.bashrc
   ```
3. Si el 3D emulado es el problema, apágalo: `"accelerate_3d": false` en
   `config.local.json`, luego `vagrant reload`.

Si lo que quieres es *probar* Omarchy en Windows y no automatizarlo, el propio
proyecto publica [try-omarchy-windows](https://github.com/omacom/try-omarchy-windows),
que usa QEMU con virgl/Venus y da mejor aceleración gráfica que VirtualBox. Este
repo es para cuando quieres la VM **reproducible y descriptible en código**.

## Qué no hay

- **Carpetas compartidas.** Omarchy no trae las Guest Additions, así que
  `/vagrant` está deshabilitado a propósito. Usa `vagrant ssh` con `scp`, o un
  `forwarded_port`.
- **Cifrado de disco.** Una instalación cifrada pide la frase LUKS en cada
  arranque, lo que rompe lo desatendido. El manual dice lo mismo.
- **Provisioners.** La instalación de Omarchy ya es el provisioning; si quieres
  añadir tuyos, un bloque `config.vm.provision "shell"` normal funciona.

## Seguridad

`cidata.iso` lleva el hash SHA-512 de la contraseña del usuario. Por eso:

- vive en `.build\`, que está en `.gitignore`;
- el Vagrantfile lo desmonta de la VM en cuanto la instalación termina, y deja
  una marca en `.build\installed-<vm>` para no volver a montarlo. Si ese paso
  falla, `scripts\Eject-InstallMedia.ps1` lo hace a mano.

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

## Licencia

MIT. Omarchy es de Basecamp/omacom y tiene su propia licencia.
