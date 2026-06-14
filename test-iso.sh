#!/usr/bin/env bash
set -euo pipefail

# Test a Zena ISO in a QEMU/KVM virtual machine with UEFI firmware.
# Optimized for Arch Linux hosts, but works on any distro that provides
# qemu-system-x86_64, qemu-img and OVMF (edk2-ovmf).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO="${SCRIPT_DIR}/output/bootiso/install.iso"
DISK="${SCRIPT_DIR}/zena-test-disk.qcow2"
OVMF_CODE=""
OVMF_VARS=""
OVMF_VARS_COPY="${SCRIPT_DIR}/OVMF_VARS.fd"
MEMORY="8192"
CPUS="4"
DISK_SIZE="64G"
SECURE_BOOT=0

# Common OVMF firmware paths across distros.
OVMF_CODE_PATHS=(
    "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd"
    "/usr/share/OVMF/x64/OVMF_CODE.fd"
    "/usr/share/OVMF/OVMF_CODE.fd"
    "/usr/share/qemu/OVMF_CODE.fd"
)
OVMF_CODE_SB_PATHS=(
    "/usr/share/edk2-ovmf/x64/OVMF_CODE.secboot.fd"
    "/usr/share/OVMF/x64/OVMF_CODE.secboot.fd"
    "/usr/share/OVMF/OVMF_CODE.secboot.fd"
    "/usr/share/qemu/OVMF_CODE.secboot.fd"
)
OVMF_VARS_PATHS=(
    "/usr/share/edk2-ovmf/x64/OVMF_VARS.fd"
    "/usr/share/OVMF/x64/OVMF_VARS.fd"
    "/usr/share/OVMF/OVMF_VARS.fd"
    "/usr/share/qemu/OVMF_VARS.fd"
)

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Test a Zena ISO in a QEMU/KVM virtual machine with UEFI firmware.

Options:
  -i, --iso PATH        ISO to test (default: ./output/bootiso/install.iso)
  -d, --disk PATH       Disk image path (default: ./zena-test-disk.qcow2)
  -s, --disk-size SIZE  Disk size for a new disk (default: 64G)
  -m, --memory MB       RAM in MB (default: 8192)
  -c, --cpus N          Number of CPUs (default: 4)
      --secure-boot     Use OVMF with Secure Boot enabled
  -h, --help            Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --secure-boot --iso ./zena.iso
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--iso)
                ISO="${2:-}"
                if [[ -z "$ISO" ]]; then
                    echo "Error: --iso requires a path" >&2
                    exit 1
                fi
                shift 2
                ;;
            -d|--disk)
                DISK="${2:-}"
                if [[ -z "$DISK" ]]; then
                    echo "Error: --disk requires a path" >&2
                    exit 1
                fi
                shift 2
                ;;
            -s|--disk-size)
                DISK_SIZE="${2:-}"
                if [[ -z "$DISK_SIZE" ]]; then
                    echo "Error: --disk-size requires a value" >&2
                    exit 1
                fi
                shift 2
                ;;
            -m|--memory)
                MEMORY="${2:-}"
                if [[ -z "$MEMORY" ]]; then
                    echo "Error: --memory requires a value" >&2
                    exit 1
                fi
                shift 2
                ;;
            -c|--cpus)
                CPUS="${2:-}"
                if [[ -z "$CPUS" ]]; then
                    echo "Error: --cpus requires a value" >&2
                    exit 1
                fi
                shift 2
                ;;
            --secure-boot)
                SECURE_BOOT=1
                shift
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

find_first_file() {
    for path in "$@"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}

check_deps() {
    local missing=()
    for cmd in qemu-system-x86_64 qemu-img; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: missing dependencies: ${missing[*]}" >&2
        echo "Install them with: sudo pacman -S qemu-full qemu-img edk2-ovmf" >&2
        exit 1
    fi

    local code_paths=("${OVMF_CODE_PATHS[@]}")
    if [[ "$SECURE_BOOT" -eq 1 ]]; then
        code_paths=("${OVMF_CODE_SB_PATHS[@]}")
    fi

    OVMF_CODE="$(find_first_file "${code_paths[@]}")" || {
        echo "Error: OVMF firmware not found" >&2
        if [[ "$SECURE_BOOT" -eq 1 ]]; then
            echo "Looked for Secure Boot variants: ${OVMF_CODE_SB_PATHS[*]}" >&2
        else
            echo "Looked for: ${OVMF_CODE_PATHS[*]}" >&2
        fi
        echo "Install it with: sudo pacman -S edk2-ovmf" >&2
        exit 1
    }

    OVMF_VARS="$(find_first_file "${OVMF_VARS_PATHS[@]}")" || {
        echo "Error: OVMF variables template not found" >&2
        echo "Looked for: ${OVMF_VARS_PATHS[*]}" >&2
        exit 1
    }
}

prepare_disk() {
    if [[ ! -f "$DISK" ]]; then
        echo "==> Creating virtual disk: $DISK ($DISK_SIZE)"
        qemu-img create -f qcow2 "$DISK" "$DISK_SIZE"
    fi
}

prepare_ovmf_vars() {
    if [[ ! -f "$OVMF_VARS_COPY" ]]; then
        echo "==> Copying OVMF variables: $OVMF_VARS_COPY"
        cp "$OVMF_VARS" "$OVMF_VARS_COPY"
    fi
}

main() {
    parse_args "$@"
    check_deps
    prepare_disk
    prepare_ovmf_vars

    if [[ ! -f "$ISO" ]]; then
        echo "Error: ISO not found: $ISO" >&2
        echo "Generate it first with: ./build-iso.sh ..." >&2
        exit 1
    fi

    echo "==> Starting VM"
    echo "    ISO:         $ISO"
    echo "    Disk:        $DISK"
    echo "    UEFI code:   $OVMF_CODE"
    echo "    UEFI vars:   $OVMF_VARS_COPY"
    echo "    Memory:      ${MEMORY} MB"
    echo "    CPUs:        $CPUS"
    echo "    Secure Boot: $SECURE_BOOT"

    qemu-system-x86_64 \
        -enable-kvm \
        -m "$MEMORY" \
        -smp "$CPUS" \
        -cpu host \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$OVMF_VARS_COPY" \
        -cdrom "$ISO" \
        -drive file="$DISK",format=qcow2,if=virtio \
        -boot d
}

main "$@"
