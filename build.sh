#!/usr/bin/env bash
set -euo pipefail

# Сборка кастомных ISO Proxmox VE.
# С binaries/: для каждого файла в PROXMOX_ISO_ROOT/binaries/ — proxmox-<имя>.iso
# Без binaries/: один образ DEFAULT_ISO_NAME (по умолчанию proxmox-custom.iso), autolxc — no-op stub.
# Требует предварительного запуска prepare.sh.

PROXMOX_ISO_ROOT="${PROXMOX_ISO_ROOT:-$HOME/proxmox_iso}"
BINARIES_DIR="$PROXMOX_ISO_ROOT/binaries"
DIST_DIR="${DIST_DIR:-$PROXMOX_ISO_ROOT/dist}"
DEFAULT_ISO_NAME="${DEFAULT_ISO_NAME:-proxmox-custom.iso}"
# Portable across squashfs-tools: older mksquashfs has no -Xcompression-level for xz.
# Override: SQUASHFS_OPTS='-comp xz -noappend -no-xattrs -b 1M -Xdict-size 75%' ./build.sh
SQUASHFS_OPTS="${SQUASHFS_OPTS:--comp xz -noappend -no-xattrs -b 1M}"
ISO_VOLUME_ID="PVE"

install_autolxc_noop_stub() {
  echo "[build] no autolxc binary: installing no-op stub at /usr/local/sbin/autolxc"
  sudo tee "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/sbin/autolxc" << 'EOF'
#!/bin/sh
# No custom autolxc in this build (binaries/ empty). autolxc.service exits successfully.
exit 0
EOF
  sudo chmod 755 "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/sbin/autolxc"
}

pack_and_mkiso() {
  local iso_out="$1"

  cd "$PROXMOX_ISO_ROOT"
  sudo mksquashfs squashfs-root extract/pve-base.squashfs $SQUASHFS_OPTS

  cd "$PROXMOX_ISO_ROOT/extract"
  sudo xorriso -as mkisofs \
    -o "$iso_out" \
    -iso-level 3 \
    -R -J -V "$ISO_VOLUME_ID" \
    -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --grub2-boot-info \
    -eltorito-alt-boot \
    -e efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    .

  echo "[build] done: $iso_out"
}

build_one_with_binary() {
  local bin_src="$1"
  local name
  name="$(basename "$bin_src")"
  local iso_name="proxmox-${name}.iso"
  local iso_out="$DIST_DIR/$iso_name"

  if [[ ! -f "$bin_src" ]]; then
    echo "[build] skip (not a file): $bin_src"
    return 0
  fi

  echo "[build] binary: $bin_src -> $iso_name"

  sudo cp "$bin_src" "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/sbin/autolxc"
  sudo chmod 755 "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/sbin/autolxc"

  pack_and_mkiso "$iso_out"
}

# ---

if [[ ! -d "$PROXMOX_ISO_ROOT/squashfs-root" ]] || [[ ! -d "$PROXMOX_ISO_ROOT/extract" ]]; then
  echo "[build] error: run prepare.sh first (squashfs-root or extract missing)"
  exit 1
fi

mkdir -p "$BINARIES_DIR"
mkdir -p "$DIST_DIR"
DIST_DIR="$(cd "$DIST_DIR" && pwd)"

binary_count=0
for f in "$BINARIES_DIR"/*; do
  [[ -e "$f" ]] || continue
  [[ -f "$f" ]] || continue
  binary_count=$((binary_count + 1))
done

if [[ "$binary_count" -eq 0 ]]; then
  echo "[build] no files in $BINARIES_DIR — building single ISO without custom autolxc ($DEFAULT_ISO_NAME)"
  install_autolxc_noop_stub
  pack_and_mkiso "$DIST_DIR/$DEFAULT_ISO_NAME"
  exit 0
fi

for f in "$BINARIES_DIR"/*; do
  [[ -e "$f" ]] || continue
  build_one_with_binary "$f"
done
