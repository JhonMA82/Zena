set -ouex pipefail

shopt -s nullglob

KVER=$(ls /usr/lib/modules | head -n1)
KIMAGE="/usr/lib/modules/$KVER/vmlinuz"

if [[ ! -f "/run/secrets/mok.key" ]]; then
  echo "Error: MOK private key not found at /run/secrets/mok.key" >&2
  exit 1
fi

MOK_KEY="/run/secrets/mok.key"
MOK_CERT_DIR="/secureboot"

dnf5 -y install sbsigntools zstd

sbsign \
  --key "$MOK_KEY" \
  --cert "$MOK_CERT_DIR/MOK.pem" \
  --output "${KIMAGE}.signed" \
  "$KIMAGE"
mv "${KIMAGE}.signed" "$KIMAGE"

find "/lib/modules/$KVER" -type f \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' -o -name '*.ko.gz' \) -print0 | while IFS= read -r -d '' comp; do
  case "$comp" in
    *.ko.xz)
      uncompressed="${comp%.xz}"
      decompress=(xz -d --keep)
      compress=(xz -z)
      ;;
    *.ko.zst)
      uncompressed="${comp%.zst}"
      decompress=(zstd -d --keep)
      compress=(zstd)
      ;;
    *.ko.gz)
      uncompressed="${comp%.gz}"
      decompress=(gunzip --keep)
      compress=(gzip -9)
      ;;
    *.ko)
      uncompressed="$comp"
      decompress=()
      compress=()
      ;;
    *)
      echo "Warning: unrecognized module file: $comp, skipping"
      continue
      ;;
  esac

  if [[ ${#decompress[@]} -gt 0 ]]; then
    if "${decompress[@]}" "$comp"; then
      echo "Decompressed $comp -> $uncompressed"
    else
      echo "Warning: failed to decompress $comp, skipping"
      continue
    fi
  fi

  /usr/src/kernels/"$KVER"/scripts/sign-file \
    sha512 "$MOK_KEY" "$MOK_CERT_DIR/MOK.pem" "$uncompressed"

  if [[ "$comp" != "$uncompressed" ]]; then
    rm -f "$comp"
  fi

  if [[ ${#compress[@]} -gt 0 ]]; then
    if "${compress[@]}" "$uncompressed"; then
      echo "Signed and compressed $uncompressed"
    else
      echo "Warning: failed to compress $uncompressed"
    fi
  else
    echo "Signed $uncompressed"
  fi
done
