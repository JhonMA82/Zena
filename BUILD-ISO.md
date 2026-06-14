# Guía de generación de ISO

Este documento explica cómo generar localmente la imagen ISO instaladora de Zena.

## Requisitos

- **Podman** instalado.
- **fuse-overlayfs** instalado (obligatorio en sistemas cuyo `/` es overlayfs).
- Al menos **30 GB libres en `/home`** (la imagen bootc, la ISO, los caches de osbuild/rpmmd y la imagen de BIB ocupan mucho espacio).
- Directorio de trabajo: la raíz de este repositorio.

## Problemas conocidos del entorno

En entornos live/persistencia donde `/` está montado como `overlayfs`, Podman no puede usar el driver `overlay` del kernel ni siquiera sobre btrfs. Por eso se usa `fuse-overlayfs` y se redirige todo el almacenamiento de contenedores a `/home/containers` (btrfs).

## 1. Instalar dependencias

```bash
sudo pacman -S podman fuse-overlayfs
```

## 2. Generar la ISO de Zena

```bash
sudo ./build-iso.sh \
  --fedora-version 44 \
  --storage-root /home/containers \
  --fuse-overlayfs
```

Si querés firmar el kernel localmente con una clave MOK propia:

```bash
sudo ./build-iso.sh \
  --fedora-version 44 \
  --storage-root /home/containers \
  --fuse-overlayfs \
  --mok-key /ruta/a/MOK.key
```

### Qué hace

1. Construye la imagen bootc local `localhost/zena:latest` usando `--network host` para evitar problemas de resolución DNS dentro del contenedor cuando se corre con `sudo`.
2. Etiqueta la imagen local como `ghcr.io/zena-linux/zena:latest` (origen por defecto) o como el valor de `--target-image`, y pasa esa referencia a `bootc-image-builder` para que el sistema instalado registre el origen correcto de actualizaciones.
3. Ejecuta `bootc-image-builder` usando la imagen custom del proyecto, que entiende la distro `zena`.
4. Genera la ISO en `./output/bootiso/install.iso`.

## 3. Renombrar o mover la ISO

```bash
sudo cp ./output/bootiso/install.iso "$HOME/zena.iso"
```

## 4. Reconstruir solo la ISO sin recompilar la imagen bootc

Si ya tenés la imagen `localhost/zena:latest` construida y querés regenerar solo la ISO (por ejemplo, tras cambiar el kickstart o la configuración del instalador):

```bash
sudo ./build-iso.sh \
  --storage-root /home/containers \
  --fuse-overlayfs \
  --use-image localhost/zena:latest
```

Incluso cuando usás `--use-image localhost/zena:latest`, el script etiqueta la imagen como `ghcr.io/zena-linux/zena:latest` (origen por defecto del registro) y se la pasa a `bootc-image-builder`, salvo que sobreescribas el origen con `--target-image`.

## 5. Probar la ISO en una VM (QEMU/KVM)

El repo incluye `test-iso.sh`, un script que arranca la ISO en una máquina virtual con firmware UEFI usando QEMU/KVM. Está pensado para Arch Linux, pero funciona en cualquier distro que tenga `qemu-system-x86_64`, `qemu-img` y `edk2-ovmf`.

### Instalar dependencias

```bash
sudo pacman -S qemu-full qemu-img edk2-ovmf
```

### Arrancar la ISO normalmente

```bash
./test-iso.sh
```

Esto crea automáticamente un disco virtual `./zena-test-disk.qcow2` de 64 GB (si no existe) y arranca la ISO `./output/bootiso/install.iso`.

### Probar con Secure Boot

```bash
./test-iso.sh --secure-boot
```

Usa `OVMF_CODE.secboot.fd`, así podés reproducir el escenario real donde el firmware valida firmas. Si la ISO no está firmada o la MOK no está enrolada, vas a ver el error `bad shim signature`.

### Opciones del script

| Opción | Descripción |
|--------|-------------|
| `-i, --iso PATH` | ISO a probar (por defecto: `./output/bootiso/install.iso`). |
| `-d, --disk PATH` | Disco virtual (por defecto: `./zena-test-disk.qcow2`). |
| `-s, --disk-size SIZE` | Tamaño del disco si se crea nuevo (por defecto: `64G`). |
| `-m, --memory MB` | RAM en MB (por defecto: `8192`). |
| `-c, --cpus N` | Cantidad de CPUs (por defecto: `4`). |
| `--secure-boot` | Usa OVMF con Secure Boot habilitado. |

### Después de instalar

Para arrancar el sistema instalado sin el ISO, cerrá la VM y volvé a correr el script. Detecta el disco existente y arranca desde él.

## Opciones del script

| Opción | Descripción |
|--------|-------------|
| `--storage-root DIR` | Almacenamiento de Podman en btrfs, fuera del overlayfs raíz. |
| `--fuse-overlayfs` | Usa `fuse-overlayfs` como programa de montaje overlay. |
| `--fedora-version VER` | Versión base de Fedora (por defecto 43, usamos 44). |
| `--use-image IMAGE` | Saltea el build y usa una imagen ya existente. |
| `--target-image IMAGE` | Referencia que `bootc-image-builder` usará como origen de actualización del sistema instalado (por defecto: `ghcr.io/zena-linux/zena:latest`). |
| `--mok-key PATH` | Ruta a la clave privada MOK para firmar el kernel en builds locales (se pasa como secreto de Buildah/Podman; no se copia en la imagen). |
| `--bib IMAGE` | Imagen de `bootc-image-builder` a usar. La imagen upstream genérica no entiende `ID=zena`, por eso se usa la imagen custom del proyecto. |
| `--storage-driver vfs` | Alternativa a fuse-overlayfs, **pero BIB no la soporta**. No usar para generar ISO. |

## Solución de problemas

### `overlay' is not supported over overlayfs`

Aparece cuando `/var/lib/containers` está sobre overlayfs. Solución: usar `--storage-root /home/containers --fuse-overlayfs`.

### `kernel does not support overlay fs`

El kernel no permite crear whiteouts de overlay. Solución: instalar `fuse-overlayfs` y usar `--fuse-overlayfs`.

### `could not access container storage, did you forget -v /var/lib/containers/storage:...?`

BIB valida que exista `/var/lib/containers/storage/overlay`. El script monta el storage en ambos paths necesarios.

### `database static dir "/home/containers/storage/libpod" does not match our static dir "/var/lib/containers/storage/libpod"`

El script ya monta el storage tanto en `/var/lib/containers/storage` como en `/home/containers/storage` para que coincidan las rutas absolutas de la base de datos de Podman.

### `no space left on device` al descargar paquetes

El script monta `/store`, `/rpmmd` y `/tmp` del contenedor de BIB sobre subdirectorios de `/home/containers`. Si aún falla, liberá espacio en `/home`.

### `could not find def file for distro zena-44`

Usá la imagen custom de BIB del proyecto:

```bash
--bib ghcr.io/zena-linux/bootc-image-builder:latest
```

La imagen upstream `quay.io/centos-bootc/bootc-image-builder:latest` no tiene definiciones para la distro `zena`.

### El instalador arranca en inglés

Aunque el kickstart configure `lang es_ES.UTF-8`, Anaconda necesita que el módulo `Localization` esté habilitado. Verificá que `iso/zena.toml` (o `iso/zena-nvidia.toml`) incluya:

```toml
[customizations.installer.modules]
enable = [
  "org.fedoraproject.Anaconda.Modules.Storage",
  "org.fedoraproject.Anaconda.Modules.Runtime",
  "org.fedoraproject.Anaconda.Modules.Localization"
]
```

Después regenerá la ISO.

### El sistema no arranca después de instalar (`bad shim signature` / `Default Boot Device Missing`)

El instalador de Zena ya no muta el sistema con `bootc switch` después de la instalación; `bootc-image-builder` instala la imagen Zena directamente. Si después de reiniciar aparece `bad shim signature` o el firmware no encuentra el dispositivo de arranque, el problema suele ser **Secure Boot**:

- **Builds locales**: podés firmar el kernel pasando la clave privada MOK con `--mok-key /ruta/a/MOK.key`. Si no tenés la clave, desactivá Secure Boot en la BIOS/UEFI. La clave nunca se copia a una capa de imagen: se inyecta como secreto de Buildah/Podman. El método anterior de colocar `MOK.key` en `system-files/common/secureboot/` fue eliminado porque filtraba la clave privada en el historial de la imagen.
- **Builds de CI/publicadas**: el kernel está firmado con la MOK de Zena, pero esa MOK debe estar enrolada en el firmware. Durante la primera instalación, desactivá Secure Boot, arrancá el sistema instalado, enrolá la MOK con `sudo mokutil --import /secureboot/MOK.der`, reiniciá y asegurate de elegir *Enroll MOK* en el MOK Manager. Después podés volver a activar Secure Boot.

Si el Boot Manager muestra una entrada vieja (por ejemplo, `mint`), borrá las entradas de arranque obsoletas desde la BIOS/UEFI o con `efibootmgr` desde un Live USB.

## Notas

- El build de Zena con Fedora 44 puede tardar entre 30 y 60 minutos o más, según la conexión y el disco.
- El contenedor de build comparte el namespace de red del host (`--network host`) para evitar problemas de resolución DNS al correr con `sudo`. Usalo solo en redes de confianza.
- Por defecto, cuando se construye la imagen localmente, la ISO instala el sistema con origen de actualización `ghcr.io/zena-linux/zena:latest` (o `ghcr.io/zena-linux/zena-nvidia:latest`). Esto sigue siendo cierto incluso si usás `--use-image localhost/...`; solo `bootc upgrade` fallará si sobreescribís el origen con `--target-image localhost/...` o si instalaste desde una imagen local sin origen de registro. En ese caso, ejecutá manualmente `bootc switch --transport registry ghcr.io/zena-linux/zena:latest` (o `zena-nvidia:latest`).
- La firma de Secure Boot en builds locales requiere pasar la clave privada con `--mok-key /ruta/a/MOK.key`; la clave se inyecta como secreto de Buildah/Podman y nunca se copia a una capa de imagen. Si no tenés la clave, las ISO locales requieren Secure Boot desactivado. En CI la clave se inyecta mediante el secreto `SECUREBOOT_KEY`.
- Las ISO publicadas por CI firman el kernel con la MOK del proyecto, pero el usuario debe enrolar esa MOK manualmente antes de que Secure Boot funcione.

## Nota sobre el idioma del instalador

Para que Anaconda arranque en español, el kickstart configura `lang es_ES.UTF-8` y se habilita explícitamente el módulo `org.fedoraproject.Anaconda.Modules.Localization`. Sin ese módulo, el instalador ignora el idioma y arranca en inglés.
