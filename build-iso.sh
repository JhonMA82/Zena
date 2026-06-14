#!/usr/bin/env bash
set -euo pipefail

# Build the Zena bootc container image and generate an Anaconda ISO.
# Usage:
#   ./build-iso.sh                          # build zena.iso
#   ./build-iso.sh nvidia                   # build zena-nvidia.iso
#   ./build-iso.sh --storage-root /path     # custom Podman storage root
#   ./build-iso.sh --fuse-overlayfs         # use fuse-overlayfs for overlay mounts
#   ./build-iso.sh --storage-driver vfs     # use VFS storage driver (slow but safe)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAVOR="zena"
OUTPUT_DIR="${SCRIPT_DIR}/output"
STORAGE_ROOT=""
STORAGE_DRIVER="overlay"
USE_FUSE_OVERLAYFS=0
USE_IMAGE=""
TARGET_IMAGE=""
MOK_KEY_PATH=""
FEDORA_VERSION="${FEDORA_VERSION:-43}"
BIB_IMAGE="${BIB_IMAGE:-ghcr.io/zena-linux/bootc-image-builder:latest}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [flavor] [options]

Flavors:
  zena        Build the standard Zena ISO (default)
  nvidia      Build the NVIDIA variant ISO

Options:
  --output DIR         Output directory for the ISO (default: ./output)
  --storage-root DIR   Custom Podman storage root (useful on overlayfs roots)
  --storage-driver DRV Podman storage driver: overlay or vfs (default: overlay)
  --fuse-overlayfs     Use fuse-overlayfs as the overlay mount program
  --fedora-version VER Fedora version to use as base (default: ${FEDORA_VERSION})
  --use-image IMAGE    Skip build and use an existing container image for ISO
  --target-image IMAGE Image reference used as the BIB install origin (default:
                       ghcr.io/zena-linux/${FLAVOR}:latest)
  --mok-key PATH       Path to a MOK private key for Secure Boot signing
                       (passed as a Buildah/Podman secret; default: none)
  --bib IMAGE          bootc-image-builder container image (default: ${BIB_IMAGE})
  -h, --help           Show this help message

Environment variables:
  FEDORA_VERSION  Fedora version to use as base (default: ${FEDORA_VERSION})
  BIB_IMAGE       Override the bootc-image-builder image
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            nvidia)
                FLAVOR="zena-nvidia"
                shift
                ;;
            zena)
                FLAVOR="zena"
                shift
                ;;
            --output)
                OUTPUT_DIR="${2:-}"
                if [[ -z "$OUTPUT_DIR" ]]; then
                    echo "Error: --output requires a directory" >&2
                    exit 1
                fi
                shift 2
                ;;
            --storage-root)
                STORAGE_ROOT="${2:-}"
                if [[ -z "$STORAGE_ROOT" ]]; then
                    echo "Error: --storage-root requires a directory" >&2
                    exit 1
                fi
                shift 2
                ;;
            --storage-driver)
                STORAGE_DRIVER="${2:-}"
                if [[ "$STORAGE_DRIVER" != "overlay" && "$STORAGE_DRIVER" != "vfs" ]]; then
                    echo "Error: --storage-driver must be 'overlay' or 'vfs'" >&2
                    exit 1
                fi
                shift 2
                ;;
            --fuse-overlayfs)
                USE_FUSE_OVERLAYFS=1
                shift
                ;;
            --fedora-version)
                FEDORA_VERSION="${2:-}"
                if [[ -z "$FEDORA_VERSION" ]]; then
                    echo "Error: --fedora-version requires a version number" >&2
                    exit 1
                fi
                shift 2
                ;;
            --use-image)
                USE_IMAGE="${2:-}"
                if [[ -z "$USE_IMAGE" ]]; then
                    echo "Error: --use-image requires an image reference" >&2
                    exit 1
                fi
                shift 2
                ;;
            --target-image)
                TARGET_IMAGE="${2:-}"
                if [[ -z "$TARGET_IMAGE" ]]; then
                    echo "Error: --target-image requires an image reference" >&2
                    exit 1
                fi
                shift 2
                ;;
            --mok-key)
                MOK_KEY_PATH="${2:-}"
                if [[ -z "$MOK_KEY_PATH" ]]; then
                    echo "Error: --mok-key requires a file path" >&2
                    exit 1
                fi
                if [[ ! -f "$MOK_KEY_PATH" ]]; then
                    echo "Error: MOK key file not found: $MOK_KEY_PATH" >&2
                    exit 1
                fi
                shift 2
                ;;
            --bib)
                BIB_IMAGE="${2:-}"
                if [[ -z "$BIB_IMAGE" ]]; then
                    echo "Error: --bib requires an image reference" >&2
                    exit 1
                fi
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                usage >&2
                exit 1
                ;;
        esac
    done
}

prepare_storage_config() {
    local config_dir="$1"
    local graphroot="$2"
    local config_file="${config_dir}/storage.conf"

    cat > "$config_file" <<EOF
[storage]
driver = "${STORAGE_DRIVER}"
graphroot = "${graphroot}"
runroot = "/run/containers"
EOF

    if [[ "$STORAGE_DRIVER" == "overlay" && "$USE_FUSE_OVERLAYFS" -eq 1 ]]; then
        cat >> "$config_file" <<EOF

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
EOF
    fi

    echo "$config_file"
}

main() {
    parse_args "$@"

    local image_tag="localhost/${FLAVOR}:latest"
    local bib_image_arg="$image_tag"
    local iso_config="${SCRIPT_DIR}/iso/${FLAVOR}.toml"
    local podman_storage_args=()
    local build_secret_args=()
    local bib_volume_args=()
    local bib_device_args=()
    local bib_env_args=()
    local tmp_config_dir=""

    if [[ ! -f "$iso_config" ]]; then
        echo "Error: ISO config not found: $iso_config" >&2
        exit 1
    fi

    if [[ "$USE_FUSE_OVERLAYFS" -eq 1 && "$STORAGE_DRIVER" == "overlay" ]]; then
        if ! command -v fuse-overlayfs >/dev/null 2>&1; then
            echo "Error: fuse-overlayfs requested but not found. Install it with:" >&2
            echo "  sudo pacman -S fuse-overlayfs" >&2
            exit 1
        fi
    fi

    mkdir -p "$OUTPUT_DIR"

    if [[ -n "$STORAGE_ROOT" ]]; then
        mkdir -p "${STORAGE_ROOT}/storage"
        mkdir -p "${STORAGE_ROOT}/osbuild-store"
        mkdir -p "${STORAGE_ROOT}/rpmmd-cache"
        mkdir -p "${STORAGE_ROOT}/tmp"
        podman_storage_args=(--root "${STORAGE_ROOT}/storage")
        # Mount to both the standard BIB validation path and the original
        # path so that the libpod database static-dir matches.
        bib_volume_args=(
            -v "${STORAGE_ROOT}/storage:/var/lib/containers/storage"
            -v "${STORAGE_ROOT}/storage:${STORAGE_ROOT}/storage"
            -v "${STORAGE_ROOT}/osbuild-store:/store"
            -v "${STORAGE_ROOT}/rpmmd-cache:/rpmmd"
            -v "${STORAGE_ROOT}/tmp:/tmp"
        )
        bib_env_args+=(-e "STORAGE_DRIVER=${STORAGE_DRIVER}")
        echo "==> Using custom Podman storage root: ${STORAGE_ROOT}/storage"
        echo "==> Using btrfs-backed osbuild store, rpmmd cache and tmp: ${STORAGE_ROOT}"
    fi

    if [[ "$USE_FUSE_OVERLAYFS" -eq 1 ]]; then
        podman_storage_args+=(--storage-opt "overlay.mount_program=/usr/bin/fuse-overlayfs")
        bib_env_args+=(-e "STORAGE_OPTS=overlay.mount_program=/usr/bin/fuse-overlayfs")
        tmp_config_dir="$(mktemp -d)"
        local bib_storage_config
        bib_storage_config="$(prepare_storage_config "$tmp_config_dir" "${STORAGE_ROOT}/storage")"
        bib_volume_args+=(-v "${bib_storage_config}:/etc/containers/storage.conf:ro")
        bib_device_args=(--device /dev/fuse)
        echo "==> Using fuse-overlayfs as overlay mount program"
    fi

    if [[ "$STORAGE_DRIVER" == "vfs" ]]; then
        podman_storage_args+=(--storage-driver vfs)
        tmp_config_dir="$(mktemp -d)"
        local bib_storage_config
        bib_storage_config="$(prepare_storage_config "$tmp_config_dir" "${STORAGE_ROOT}/storage")"
        bib_volume_args+=(-v "${bib_storage_config}:/etc/containers/storage.conf:ro")
        echo "==> Using VFS storage driver (slower, but works everywhere)"
    fi

    if [[ -n "$MOK_KEY_PATH" ]]; then
        build_secret_args=(--secret "id=mok,src=${MOK_KEY_PATH}")
    fi

    if [[ -n "$USE_IMAGE" ]]; then
        image_tag="$USE_IMAGE"
        echo "==> Skipping build, using existing image: $image_tag"
    else
        echo "==> Building bootc image: $image_tag (flavor: $FLAVOR)"
        podman build \
            "${podman_storage_args[@]}" \
            "${build_secret_args[@]}" \
            --network host \
            --build-arg "FEDORA_VERSION=${FEDORA_VERSION}" \
            --build-arg "IMAGE=${FLAVOR}" \
            -t "$image_tag" \
            "$SCRIPT_DIR"
    fi

    if [[ -z "$TARGET_IMAGE" ]]; then
        TARGET_IMAGE="ghcr.io/zena-linux/${FLAVOR}:latest"
    fi
    if [[ "$image_tag" != "$TARGET_IMAGE" ]]; then
        echo "==> Tagging image for BIB install origin: $TARGET_IMAGE"
        podman tag \
            "${podman_storage_args[@]}" \
            "$image_tag" "$TARGET_IMAGE"
    fi
    bib_image_arg="$TARGET_IMAGE"

    echo "==> Generating Anaconda ISO with bootc-image-builder"
    podman run \
        "${podman_storage_args[@]}" \
        --rm \
        --privileged \
        --pull=newer \
        --network host \
        --security-opt label=type:unconfined_t \
        "${bib_device_args[@]}" \
        "${bib_volume_args[@]}" \
        "${bib_env_args[@]}" \
        -v "${OUTPUT_DIR}:/output" \
        -v "${iso_config}:/config.toml:ro" \
        "$BIB_IMAGE" \
        --type anaconda-iso \
        --rootfs btrfs \
        --config /config.toml \
        --use-librepo=True \
        "$bib_image_arg"

    if [[ -n "$tmp_config_dir" && -d "$tmp_config_dir" ]]; then
        rm -rf "$tmp_config_dir"
    fi

    echo "==> ISO generation complete"
    echo "    Output directory: $OUTPUT_DIR"
    find "$OUTPUT_DIR" -name '*.iso' -printf '    ISO: %p\n'
}

main "$@"
