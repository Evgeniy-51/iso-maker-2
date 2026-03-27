#!/usr/bin/env bash
set -euo pipefail

# Подготовка машины Ubuntu и базы для сборки кастомных ISO Proxmox VE.
# Запускать один раз: ставит пакеты, скачивает официальный ISO 9.1-1,
# распаковывает его и pve-base.squashfs, добавляет systemd-юнит autolxc.service.
# Бинарник не кладётся — его подставляет build.sh.

PROXMOX_ISO_ROOT="${PROXMOX_ISO_ROOT:-$HOME/proxmox_iso}"
PROXMOX_ISO_URL="${PROXMOX_ISO_URL:-https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso}"
ISO_FILE="$PROXMOX_ISO_ROOT/proxmox-ve.iso"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PVE_AUTOINSTALL_SRC="$PROJECT_ROOT/pve-autoinstall.sh"
PVE_RESTORE_BACKUPS_SRC="$PROJECT_ROOT/pve-restore-backups.sh"

echo "[prepare] root: $PROXMOX_ISO_ROOT"

# Пакеты
sudo apt-get update
sudo apt-get install -y xorriso squashfs-tools rsync wget

# Каталоги (binaries/ — источник бинарников для build.sh)
mkdir -p "$PROXMOX_ISO_ROOT"/{mnt,extract,squashfs-root,binaries}
cd "$PROXMOX_ISO_ROOT"

# Скачать ISO (если ещё нет)
if [[ ! -f "$ISO_FILE" ]]; then
  wget -O "$ISO_FILE" "$PROXMOX_ISO_URL"
fi
ls -lh "$ISO_FILE"

# Распаковать ISO в extract/
sudo mount -o loop "$ISO_FILE" "$PROXMOX_ISO_ROOT/mnt"
sudo rsync -a "$PROXMOX_ISO_ROOT/mnt/" "$PROXMOX_ISO_ROOT/extract/"
sudo umount "$PROXMOX_ISO_ROOT/mnt"

# Распаковать pve-base.squashfs в squashfs-root
sudo rm -rf "$PROXMOX_ISO_ROOT/squashfs-root"
sudo unsquashfs -d "$PROXMOX_ISO_ROOT/squashfs-root" "$PROXMOX_ISO_ROOT/extract/pve-base.squashfs"

# Юнит autolxc.service в установленной системе (без бинарника — подставит build.sh)
sudo tee "$PROXMOX_ISO_ROOT/squashfs-root/etc/systemd/system/autolxc.service" << 'EOF'
[Unit]
Description=Auto-create LXC after Proxmox install
After=network-online.target pve-cluster.service pvedaemon.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/autolxc
StandardOutput=journal
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF

sudo mkdir -p "$PROXMOX_ISO_ROOT/squashfs-root/etc/systemd/system/multi-user.target.wants"
sudo ln -sf ../autolxc.service "$PROXMOX_ISO_ROOT/squashfs-root/etc/systemd/system/multi-user.target.wants/autolxc.service"

# Каталог для бинарника (build.sh сюда копирует)
sudo mkdir -p "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/sbin"

# Вшиваем post-install скрипты Proxmox в ISO
if [[ ! -f "$PVE_AUTOINSTALL_SRC" ]]; then
  echo "[prepare] error: missing script: $PVE_AUTOINSTALL_SRC"
  exit 1
fi
if [[ ! -f "$PVE_RESTORE_BACKUPS_SRC" ]]; then
  echo "[prepare] error: missing script: $PVE_RESTORE_BACKUPS_SRC"
  exit 1
fi
sudo cp "$PVE_AUTOINSTALL_SRC" "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/sbin/pve-autoinstall.sh"
sudo cp "$PVE_RESTORE_BACKUPS_SRC" "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/sbin/pve-restore-backups.sh"
sudo chmod 755 "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/sbin/pve-autoinstall.sh"
sudo chmod 755 "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/sbin/pve-restore-backups.sh"

# Юнит pve-autoinstall.service в установленной системе
sudo tee "$PROXMOX_ISO_ROOT/squashfs-root/etc/systemd/system/pve-autoinstall.service" << 'EOF'
[Unit]
Description=PVE autoinstall
After=network-online.target pve-cluster.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pve-autoinstall.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Юнит pve-restore-backups.service в установленной системе
sudo tee "$PROXMOX_ISO_ROOT/squashfs-root/etc/systemd/system/pve-restore-backups.service" << 'EOF'
[Unit]
Description=PVE restore backups
After=network-online.target pve-cluster.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pve-restore-backups.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Тестовая директория для SCP в контейнер 
sudo mkdir -p "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/share/autolxc-prod/test-dir"
echo -n "test" | sudo tee "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/share/autolxc-prod/test-dir/test.txt" > /dev/null

# Автостарт сервисов после установки системы
sudo ln -sf ../pve-autoinstall.service "$PROXMOX_ISO_ROOT/squashfs-root/etc/systemd/system/multi-user.target.wants/pve-autoinstall.service"
sudo ln -sf ../pve-restore-backups.service "$PROXMOX_ISO_ROOT/squashfs-root/etc/systemd/system/multi-user.target.wants/pve-restore-backups.service"

echo "[prepare] done. Put binaries in $PROXMOX_ISO_ROOT/binaries/ and run build.sh."
