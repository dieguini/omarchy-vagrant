# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
versionado según [SemVer](https://semver.org/lang/es/).

Como esto automatiza software de terceros, la versión habla del repo, no de
Omarchy. La versión de Omarchy que se instala se elige en `config.json`
(`omarchy_version`), y cada release dice contra cuál se verificó.

## [1.0.1] - 2026-09-19

### Corregido

- **El desmontaje de los medios de instalación no funcionaba y además mentía.**
  El escritorio automonta la ISO y el `cidata` con `udiskie`, y con el guest
  teniéndolos montados VirtualBox responde `VERR_PDM_MEDIA_LOCKED`. El trigger
  ignoraba ese error, imprimía que los había desmontado y ponía la marca de
  hecho, así que el `cidata` — que lleva el hash de la contraseña — se quedaba
  adjunto y montado en `/run/media/<usuario>/cidata`.

  Ahora se usa `--forceunmount`, y la marca solo se pone si de verdad se
  desmontaron; si no, avisa y el siguiente arranque lo reintenta. Lo mismo en
  `scripts\Eject-InstallMedia.ps1`, que ya falla en vez de callarse.

## [1.0.0] - 2026-09-19

Primera versión. Verificada de punta a punta contra **Omarchy 4.0.4** en
VirtualBox 7.2.6 y Vagrant 2.4.9 sobre Windows 11: instalación desatendida,
escritorio Hyprland funcionando y herramientas instaladas.

### Añadido

- Instalación desatendida por disco `cidata`, el método que documenta el manual
  de Omarchy. `bootstrap.ps1` descarga y verifica la ISO, genera el `cidata` y
  un par de llaves SSH dedicado, y fabrica la caja Vagrant vacía con EFI.
- Generación de la ISO `cidata` con IMAPI2, sin dependencias externas en
  Windows.
- Provisioner `passwordless-sudo`: instala la regla de sudoers que Vagrant da
  por hecha.
- Provisioner `qt-software-rendering`: pone QtQuick en software para el greeter
  de SDDM y para la sesión, sin lo cual no hay escritorio en una VM.
- Provisioner `display`: fija resolución y escala en `monitors.lua`.
- Provisioner `tools`: cuatro listas declarativas — `omarchy_installs`,
  `packages`, `aur_packages` y `webapps`.
- Desmontaje automático de la ISO y del `cidata` al terminar la instalación: el
  `cidata` lleva el hash de la contraseña.
- Limpieza, en el trigger de `destroy`, de la carpeta que VirtualBox deja atrás
  en Windows.

### Notas

- Sin carpetas compartidas: Omarchy no trae Guest Additions.
- Sin cifrado de disco: pediría la frase LUKS en cada arranque y rompería lo
  desatendido.
- El rendimiento gráfico es el que es. Para solo probar Omarchy,
  [try-omarchy-windows](https://github.com/omacom/try-omarchy-windows) usa QEMU
  con virgl y rinde mejor.

[1.0.1]: https://github.com/dieguini/omarchy-vagrant/releases/tag/v1.0.1
[1.0.0]: https://github.com/dieguini/omarchy-vagrant/releases/tag/v1.0.0
