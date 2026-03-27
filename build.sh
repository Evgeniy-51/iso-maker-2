#!/usr/bin/env bash
set -euo pipefail

# Сборка кастомных ISO Proxmox VE по бинарникам из папки binaries/.
# Запуск без аргументов: цикл по всем файлам в PROXMOX_ISO_ROOT/binaries/.
# Для каждого файла — образ proxmox-<имя_файла>.iso в dist/.
# Требует предварительного запуска prepare.sh.

PROXMOX_ISO_ROOT="${PROXMOX_ISO_ROOT:-$HOME/proxmox_iso}"
BINARIES_DIR="$PROXMOX_ISO_ROOT/binaries"
DIST_DIR="${DIST_DIR:-$PROXMOX_ISO_ROOT/dist}"
SQUASHFS_OPTS="-comp xz -noappend -no-xattrs -b 1M"
ISO_VOLUME_ID="PVE"

build_one() {
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

  cd "$PROXMOX_ISO_ROOT"
  sudo mksquashfs squashfs-root extract/pve-base.squashfs $SQUASHFS_OPTS

  cd "$PROXMOX_ISO_ROOT/extract"
  sudo xorriso -as mkisofs \
    -o "$iso_out" \
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

# ---

if [[ ! -d "$PROXMOX_ISO_ROOT/squashfs-root" ]] || [[ ! -d "$PROXMOX_ISO_ROOT/extract" ]]; then
  echo "[build] error: run prepare.sh first (squashfs-root or extract missing)"
  exit 1
fi

if [[ ! -d "$BINARIES_DIR" ]]; then
  echo "[build] error: binaries dir missing: $BINARIES_DIR (run prepare.sh)"
  exit 1
fi

mkdir -p "$DIST_DIR"
DIST_DIR="$(cd "$DIST_DIR" && pwd)"

count=0
for f in "$BINARIES_DIR"/*; do
  [[ -e "$f" ]] || continue
  build_one "$f"
  (( count++ )) || true
done

if [[ $count -eq 0 ]]; then
  echo "[build] no files in $BINARIES_DIR — put binaries there and run again"
  exit 1
fi
