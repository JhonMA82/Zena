# Mapa de archivos del proyecto Zena

Este documento explica qué hace cada archivo y directorio del repositorio Zena. Zena es una distribución Linux inmutable basada en Fedora `bootc` que produce instaladores ISO.

## Navegación rápida

- [Archivos de nivel superior](#archivos-de-nivel-superior)
- [Scripts de compilación](#scripts-de-compilación)
- [Archivos de sistema](#archivos-de-sistema)
- [Configuraciones ISO](#configuraciones-iso)
- [Parches](#parches)
- [Metadatos de GitHub](#metadatos-de-github)
- [Flujo de compilación](#flujo-de-compilación)
- [Diferencias entre variantes](#diferencias-entre-variantes)
- [Advertencias conocidas](#advertencias-conocidas)

---

## Archivos de nivel superior

| Archivo | Propósito |
|---------|-----------|
| `Containerfile` | Receta de compilación OCI. Parte de `quay.io/fedora/fedora-bootc:${FEDORA_VERSION}`, copia la capa superpuesta del sistema de archivos base y ejecuta `/ctx/build.sh`. |
| `build-iso.sh` | Script local para construir la imagen bootc y generar la ISO de Anaconda en un solo paso. Soporta storage custom, `fuse-overlayfs`, versión de Fedora, reutilización de imágenes, origen de actualizaciones (`--target-image`) y firma local con MOK (`--mok-key`). |
| `test-iso.sh` | Script local para probar la ISO en una máquina virtual QEMU/KVM con firmware UEFI, con soporte opcional para Secure Boot. |
| `BUILD-ISO.md` | Guía paso a paso para generar la ISO localmente, incluyendo solución de problemas comunes. |
| `README.md` | Documentación para el usuario final: características, pasos de instalación, configuración del primer arranque, `zix`, `gaming`, `systemd-homed`, Secure Boot. |
| `LICENSE` | Licencia Apache 2.0. |
| `CODE_OF_CONDUCT.md` | Código de conducta Contributor Covenant. |
| `.gitignore` | Excluye `cosign.key`, `system-files/common/secureboot/MOK.key`, `.flox`, `.venv`, `output/`. |
| `.containerignore` | Excluye `system-files/common/secureboot/MOK.key` del contexto de build para evitar que la clave privada MOK se copie a una capa de imagen. |
| `cosign.pub` | Clave pública de cosign usada para verificar las firmas de las imágenes de contenedor publicadas. |

---

## Scripts de compilación

### `build-scripts/build.sh`

Orquestador principal de la compilación. Lee el argumento de compilación `IMAGE` (`zena` o `zena-nvidia`), copia las capas superpuestas de `system-files` correspondientes y ejecuta los scripts de los módulos en un orden fijo. El módulo `sign` solo se ejecuta si existe el secreto `/run/secrets/mok.key`; en builds locales sin la clave privada se omite la firma de Secure Boot.

### `build-scripts/modules/`

| Módulo | Ruta de archivo | Propósito |
|--------|-----------------|-----------|
| `base.dnf` | `base/dnf.sh` | Habilita los repositorios y COPR requeridos por el resto de la compilación. |
| `base.kernel` | `base/kernel.sh` | Reemplaza el kernel de Fedora por el kernel CachyOS LTO. |
| `base.packages` | `base/packages.sh` | Instala el conjunto base de paquetes, incluidas las dependencias de la GUI del primer arranque. |
| `base.system` | `base/system.sh` | Personaliza la marca del sistema operativo, configura `rpm-ostreed`, Plymouth, sudoers y Flathub. |
| `base.services` | `base/services.sh` | Habilita o enmascara las unidades principales de systemd. |
| `de.wm.packages` | `de/wm/packages.sh` | Instala el entorno de escritorio Dank Material Shell / niri / MangoWC. |
| `de.wm.services` | `de/wm/services.sh` | Habilita unidades de systemd para el escritorio y presets. |
| `integrations.homed` | `integrations/homed.sh` | Carga la política SELinux para `systemd-homed` y habilita el servicio. |
| `integrations.nix` | `integrations/nix.sh` | Instala Nix, el wrapper `zix`, y prepara el archivo de `/var/lib/nix`. |
| `integrations.virtualization` | `integrations/virtualization.sh` | Instala QEMU, libvirt, virt-manager y Waydroid. |
| `integrations.nvidia` | `integrations/nvidia.sh` | Agrega los controladores NVIDIA y el toolkit de contenedores (solo variante NVIDIA). |
| `sign` | `sign.sh` | Firma el kernel y los módulos del kernel con la clave MOK de Zena. |
| `initramfs` | `initramfs.sh` | Regenera el initramfs de dracut para el kernel CachyOS instalado. |

---

## Archivos de sistema

Todas las entradas bajo `system-files/` son capas superpuestas del sistema de archivos que terminan copiándose en la imagen destino.

### `system-files/common/`

Archivos copiados en cada imagen antes de que `build.sh` se ejecute.

#### Archivos de configuración

| Archivo | Propósito |
|---------|-----------|
| `etc/chrony.conf` | Configuración NTP. |
| `etc/environment` | Variables de entorno a nivel del sistema (Nix, sugerencias de Wayland). |
| `etc/profile.d/zx-ssh-socket.sh` | Establece `SSH_AUTH_SOCK` en la ruta de ejecución del usuario. |
| `etc/profile.d/zz-shell.sh` | Permite a los usuarios elegir su shell preferida mediante `~/.config/shell`. |
| `etc/sudoers.d/00-zena` | Reglas sudo para `wheel` y configuración del tiempo de espera. |
| `etc/systemd/system/nix.mount` | Monta `/var/lib/nix` como bind en `/nix`. |
| `etc/systemd/system/nix-setup.service` | Extrae `/etc/nix-setup.tar` en `/var/lib/nix` en el primer arranque. |
| `etc/systemd/system/podman-tcp.service` | Expone la API de Podman en `127.0.0.1:37017`. |
| `etc/systemd/system/preload.service` | Servicio de precarga readahead. |
| `etc/systemd/system/zena-setup.service` | Ejecuta la configuración TUI del primer arranque. |
| `etc/systemd/user/flathub-setup.service` | Agrega el remoto de Flathub del usuario. |
| `etc/udev/rules.d/59-vial.rules` | Regla de udev para acceso a teclados Vial. |
| `etc/udev/rules.d/92-viia.rules` | Regla de udev para acceso a teclados VIA. |
| `etc/xdg/xdg-terminals.list` | Define `xdg-terminal-exec` para que use Alacritty por defecto. |
| `etc/zena-setup/niri.kdl` | Configuración mínima de niri para la TUI del primer arranque. |

#### Binarios y datos

| Archivo | Propósito |
|---------|-----------|
| `usr/lib/bootc/kargs.d/00-splash.toml` | Agrega los argumentos de kernel `quiet splash`. |
| `usr/libexec/run-zena-setup.sh` | Ejecutor de la configuración del primer arranque invocado por `zena-setup.service`. |
| `usr/local/bin/bash` | Wrapper para ejecutar bash con `SKIP_PREFERRED_SHELL=1`. |
| `usr/local/bin/fastfetch` | Wrapper de fastfetch usando el logo ASCII de Zena. |
| `usr/local/bin/gaming` | CLI en Python que gestiona el contenedor opt-in `Gaming` de Distrobox. |
| `usr/local/bin/homectl` | Wrapper que agrega ayudantes para la gestión de UID/GID subordinados de `systemd-homed`. |
| `usr/share/icons/cachyos.svg` | Logo de CachyOS usado para la marca del sistema operativo. |
| `usr/share/icons/logo.txt` | Logo ASCII usado por `fastfetch`. |

#### Secure Boot

| Archivo | Propósito |
|---------|-----------|
| `secureboot/MOK.pem` | Certificado MOK público en formato PEM. |
| `secureboot/MOK.der` | Certificado MOK público en formato DER para `mokutil`. |

### `system-files/wm/`

Capa superpuesta del entorno de escritorio copiada tanto para `zena` como para `zena-nvidia`.

| Archivo | Propósito |
|---------|-----------|
| `etc/dconf/db/local.d/00-icon-theme` | Establece el tema de iconos Papirus. |
| `etc/environment` | Agrega variables de entorno para temas Qt/Wayland. |
| `etc/gnupg/gpg-agent.conf` | Usa `pinentry-gnome3` para las frases de paso de GPG. |
| `etc/greetd/config.toml` | Configuración del gestor de pantalla greetd. |
| `etc/greetd/niri.kdl` | Configuración de niri para la sesión del greeter. |
| `etc/nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-wayland-compositors.json` | Ajuste del perfil NVIDIA para `niri`. |
| `etc/polkit-1/rules.d/10-dms-greeter-sync.rules` | Permite a usuarios sin privilegios activar la sincronización del greeter. |
| `etc/skel/.config/alacritty/alacritty.toml` | Configuración base de Alacritty. |
| `etc/skel/.config/DankMaterialShell/.firstlaunch` | Marcador de primer lanzamiento de DMS. |
| `etc/skel/.config/mango/config.conf` | Configuración por defecto de MangoWC. |
| `etc/skel/.config/niri/config.kdl` | Configuración completa de niri con integración DMS. |
| `etc/systemd/journald.conf.d/00-no-forward.conf` | Deshabilita el reenvío del journal a consola/kmsg/syslog/wall. |
| `etc/systemd/system/dms-greeter-sync.service` | Copia la configuración y el fondo de pantalla de DMS al caché del greeter. |
| `etc/systemd/system/flatpak-theme.service` | Otorga a Flatpak acceso de lectura a la configuración GTK del host. |
| `etc/systemd/user/dms-greeter-sync-trigger.service` | Activa el servicio de sincronización del greeter desde la sesión del usuario. |
| `etc/systemd/user/dms-watch.path` | Observa los archivos de configuración de DMS y activa la sincronización ante cambios. |
| `etc/systemd/user/mango-session.target` | Target de usuario que agrupa las unidades de sesión de MangoWC. |
| `etc/systemd/user/wm-setup.service` | Configuración del primer inicio de sesión por usuario. |
| `usr/libexec/dms-greeter-sync.sh` | Implementación de la sincronización del greeter. |
| `usr/libexec/dms-greeter-sync-trigger.sh` | Escribe la ruta del fondo de pantalla actual y activa la sincronización. |
| `usr/libexec/openssh/ssh-askpass` | Ayudante ssh-askpass usando Zenity. |
| `usr/libexec/wm-setup.sh` | Copia archivos del esqueleto y crea configuraciones stub de DMS/MangoWC. |
| `usr/local/bin/mango-session` | Inicia el target de sesión de usuario de MangoWC. |

### `system-files/nvidia/`

Capa superpuesta copiada solo para la variante `zena-nvidia`.

| Archivo | Propósito |
|---------|-----------|
| `usr/lib/bootc/kargs.d/00-nvidia.toml` | Agrega a la lista negra `nouveau` y habilita el modo de configuración de NVIDIA. |
| `usr/lib/dracut/dracut.conf.d/99-nvidia.conf` | Fuerza la inclusión de los controladores NVIDIA/i915/amdgpu en el initramfs. |
| `usr/lib/modprobe.d/00-nouveau-blacklist.conf` | Agrega `nouveau` a la lista negra. |
| `usr/lib/modprobe.d/nvidia-modeset.conf` | Habilita `nvidia-drm modeset=1`. |
| `usr/lib/systemd/system/nvctk-cdi.service` | Genera la configuración CDI de NVIDIA para los tiempos de ejecución de contenedores. |

### `system-files/assets/`

| Archivo | Propósito |
|---------|-----------|
| `logos/watermark.png` | Marca de agua del splash de arranque de Plymouth. |
| `logos/zena-logo.png` | Recurso del logo del proyecto. |

---

## Configuraciones ISO

| Archivo | Propósito |
|---------|-----------|
| `iso/zena.toml` | Configuración de image-builder para la ISO estándar. Configura idioma español (`es_ES.UTF-8`) y teclado español (`es`), y habilita el módulo `Localization` de Anaconda. La imagen Zena se instala directamente porque `bootc-image-builder` la recibe como argumento; la referencia pasada a BIB se convierte en el origen de actualización del deployment. El kickstart ya no contiene un bloque `%post` con `bootc switch`. |
| `iso/zena-nvidia.toml` | Igual para la variante NVIDIA. |

Ambas configuraciones habilitan los módulos de Almacenamiento, Tiempo de ejecución y Localización de Anaconda, deshabilitando los módulos de Red, Seguridad, Servicios, Usuarios, Suscripción y Zona horaria.

---

## Parches

| Archivo | Propósito |
|---------|-----------|
| `patches/homed-patch-01.pp` | Módulo de política SELinux compilado cargado por `integrations/homed.sh` para soportar `systemd-homed`. |

---

## Metadatos de GitHub

### Workflows

| Archivo | Propósito |
|---------|-----------|
| `.github/workflows/build.yml` | Compila la imagen de contenedor con `buildah`, inyecta la clave privada MOK como secreto de build (`--secret id=mok`), falla en builds que no sean PR si el secreto falta, la redivide en capas, la firma con cosign y la publica en GHCR. |
| `.github/workflows/build-disk.yml` | Compila la ISO de Anaconda con `bootc-image-builder`, la comprime, la sube al almacenamiento y publica los metadatos de la release. |

### Otros archivos

| Archivo | Propósito |
|---------|-----------|
| `.github/dependabot.yml` | Actualizaciones semanales de versiones de GitHub Actions. |
| `.github/FUNDING.yml` | Configuración de GitHub Sponsors. |
| `.github/renovate.json5` | Configuración de Renovate con presets de buenas prácticas. |

---

## Flujo de compilación

```
Containerfile
    │
    ├── COPY system-files/common /          # capa superpuesta del sistema de archivos base
    ├── COPY build-scripts, patches, assets # contexto de compilación
    │
    └── RUN /ctx/build.sh
            │
            ├── cp system-files/wm /        # capa superpuesta del escritorio
            ├── cp system-files/nvidia /    # solo variante NVIDIA
            │
            └── ejecuta los módulos en orden:
                    base.dnf
                    base.kernel
                    base.packages
                    base.system
                    base.services
                    de.wm.packages
                    de.wm.services
                    integrations.homed
                    integrations.nix
                    integrations.virtualization
                    integrations.nvidia       # solo variante NVIDIA
                    sign
                    initramfs
            │
            └── limpia repositorios que no sean de Fedora, dnf5 clean

GitHub Actions build.yml
    └── buildah build Containerfile
        └── legacy-rechunk → cosign sign → push a GHCR

GitHub Actions build-disk.yml
    └── bootc-image-builder (anaconda-iso)
        ├── config: iso/zena.toml o iso/zena-nvidia.toml
        └── sube la ISO comprimida al almacenamiento
```

---

## Diferencias entre variantes

| Aspecto | `zena` | `zena-nvidia` |
|---------|--------|---------------|
| Argumento de compilación `IMAGE` | `zena` | `zena-nvidia` |
| system-files copiados | `common` + `wm` | `common` + `wm` + `nvidia` |
| Módulo de compilación extra | ninguno | `integrations.nvidia` |
| Argumentos del kernel | `quiet splash` | `quiet splash` + lista negra de nouveau + modo de configuración de NVIDIA |
| Imagen destino de la ISO | `ghcr.io/zena-linux/zena:latest` | `ghcr.io/zena-linux/zena-nvidia:latest` |
| Configuración ISO | `iso/zena.toml` | `iso/zena-nvidia.toml` |

---

## Advertencias conocidas

- `system-files/common/etc/systemd/system/preload.service` referencia `/usr/local/sbin/preload`, pero no se instala ningún paquete preload. Esta unidad probablemente esté obsoleta.
- La clave privada de Secure Boot (`MOK.key`) no está en el repositorio. En CI y en builds locales firmados se inyecta como secreto de `buildah`/`podman` (`--secret id=mok`) y nunca se copia a una capa de imagen. El método anterior de leer `/secureboot/MOK.key` fue eliminado porque filtraba la clave en el historial de la imagen.
- Nix se instala en tiempo de compilación, pero el directorio `/nix` se vacía y se recrea en el primer arranque a partir de `/etc/nix-setup.tar` bajo `/var/lib/nix`, lo que hace que el store sea mutable entre actualizaciones de bootc.

(Fin del archivo - 254 líneas en total)
