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
  --fuse-overlayfs \
  --bib ghcr.io/zena-linux/bootc-image-builder:latest
```

### Qué hace

1. Construye la imagen bootc local `localhost/zena:latest`.
2. Ejecuta `bootc-image-builder` usando la imagen custom del proyecto, que entiende la distro `zena`.
3. Genera la ISO en `./output/bootiso/install.iso`.

## 3. Renombrar o mover la ISO

```bash
sudo cp ./output/bootiso/install.iso /home/juan/zena.iso
```

## 4. Reconstruir solo la ISO sin recompilar la imagen bootc

Si ya tenés la imagen `localhost/zena:latest` construida y querés regenerar solo la ISO (por ejemplo, tras cambiar el kickstart o la configuración del instalador):

```bash
sudo ./build-iso.sh \
  --storage-root /home/containers \
  --fuse-overlayfs \
  --use-image localhost/zena:latest \
  --bib ghcr.io/zena-linux/bootc-image-builder:latest
```

## Opciones del script

| Opción | Descripción |
|--------|-------------|
| `--storage-root DIR` | Almacenamiento de Podman en btrfs, fuera del overlayfs raíz. |
| `--fuse-overlayfs` | Usa `fuse-overlayfs` como programa de montaje overlay. |
| `--fedora-version VER` | Versión base de Fedora (por defecto 43, usamos 44). |
| `--use-image IMAGE` | Saltea el build y usa una imagen ya existente. |
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

## Notas

- El build de Zena con Fedora 44 puede tardar entre 30 y 60 minutos o más, según la conexión y el disco.
- La firma de Secure Boot no se realiza en builds locales porque la clave privada `MOK.key` no está en el repositorio; se inyecta en CI mediante el secreto `SECUREBOOT_KEY`. La ISO local funciona sin Secure Boot.

## Nota sobre el idioma del instalador

Para que Anaconda arranque en español, el kickstart configura `lang es_ES.UTF-8` y se habilita explícitamente el módulo `org.fedoraproject.Anaconda.Modules.Localization`. Sin ese módulo, el instalador ignora el idioma y arranca en inglés.
