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
# Рекомендуемый layout: рядом с каталогом iso-maker-2 лежат stack/ и pve-*.sh.
# Если prepare.sh в Custom-iso-maker/, «общий» каталог — родитель iso-maker-2.
# Если prepare.sh в корне iso-maker-2/, общий каталог — родитель репозитория (тот же уровень, что и iso-maker-2).
if [[ "$(basename "$SCRIPT_DIR")" == "Custom-iso-maker" ]]; then
  LAYOUT_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
else
  LAYOUT_ROOT="$PROJECT_ROOT"
fi

resolve_script_path() {
  local filename="$1"
  local explicit_path="${2:-}"
  local cwd_parent
  cwd_parent="$(cd "$PWD/.." && pwd)"
  local candidates=(
    "$explicit_path"
    "$LAYOUT_ROOT/$filename"
    "$PROJECT_ROOT/$filename"
    "$SCRIPT_DIR/$filename"
    "$PWD/$filename"
    "$cwd_parent/$filename"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

resolve_stack_path() {
  local explicit_path="${1:-}"
  local cwd_parent
  cwd_parent="$(cd "$PWD/.." && pwd)"
  local candidates=(
    "$explicit_path"
    "$LAYOUT_ROOT/stack"
    "$PROJECT_ROOT/stack"
    "$SCRIPT_DIR/stack"
    "$PWD/stack"
    "$cwd_parent/stack"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    if [[ -d "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

PVE_AUTOINSTALL_SRC="${PVE_AUTOINSTALL_SRC:-}"
if [[ -z "$PVE_AUTOINSTALL_SRC" ]]; then
  PVE_AUTOINSTALL_SRC="$(resolve_script_path "pve-autoinstall.sh" "" || true)"
fi

PVE_RESTORE_BACKUPS_SRC="${PVE_RESTORE_BACKUPS_SRC:-}"
if [[ -z "$PVE_RESTORE_BACKUPS_SRC" ]]; then
  PVE_RESTORE_BACKUPS_SRC="$(resolve_script_path "pve-restore-backups.sh" "" || true)"
fi
STACK_SRC_DIR="${STACK_SRC_DIR:-}"
if [[ -z "$STACK_SRC_DIR" ]]; then
  STACK_SRC_DIR="$(resolve_stack_path "" || true)"
fi

echo "[prepare] root: $PROXMOX_ISO_ROOT"
echo "[prepare] layout dir (рядом iso-maker-2, stack, pve-*.sh): $LAYOUT_ROOT"

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
if [[ -z "${PVE_AUTOINSTALL_SRC:-}" ]] || [[ ! -f "$PVE_AUTOINSTALL_SRC" ]]; then
  echo "[prepare] error: missing script: pve-autoinstall.sh"
  echo "[prepare] hint: положите файл рядом с iso-maker-2 и stack (каталог $LAYOUT_ROOT) или задайте PVE_AUTOINSTALL_SRC=/absolute/path/pve-autoinstall.sh"
  exit 1
fi
if [[ -z "${PVE_RESTORE_BACKUPS_SRC:-}" ]] || [[ ! -f "$PVE_RESTORE_BACKUPS_SRC" ]]; then
  echo "[prepare] error: missing script: pve-restore-backups.sh"
  echo "[prepare] hint: положите файл рядом с iso-maker-2 и stack (каталог $LAYOUT_ROOT) или задайте PVE_RESTORE_BACKUPS_SRC=/absolute/path/pve-restore-backups.sh"
  exit 1
fi
sudo cp "$PVE_AUTOINSTALL_SRC" "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/sbin/pve-autoinstall.sh"
sudo cp "$PVE_RESTORE_BACKUPS_SRC" "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/sbin/pve-restore-backups.sh"
sudo chmod 755 "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/sbin/pve-autoinstall.sh"
sudo chmod 755 "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/sbin/pve-restore-backups.sh"

# Вшиваем stack payload в ISO (будет развернут в /mnt/stack на первом запуске)
if [[ ! -d "$STACK_SRC_DIR" ]]; then
  echo "[prepare] error: missing stack dir: $STACK_SRC_DIR"
  echo "[prepare] hint: положите каталог stack рядом с iso-maker-2 (ожидается $LAYOUT_ROOT/stack) или задайте STACK_SRC_DIR=/absolute/path/stack"
  exit 1
fi
STACK_ISO_DIR="$PROXMOX_ISO_ROOT/squashfs-root/opt/bootstrap-stack"
echo "[prepare] embedding stack from: $STACK_SRC_DIR"
sudo rm -rf "$STACK_ISO_DIR"
sudo mkdir -p "$STACK_ISO_DIR"
sudo rsync -a --delete "$STACK_SRC_DIR"/ "$STACK_ISO_DIR"/

# Юнит pve-autoinstall.service в установленной системе
sudo tee "$PROXMOX_ISO_ROOT/squashfs-root/etc/systemd/system/pve-autoinstall.service" << 'EOF'
[Unit]
Description=PVE autoinstall
After=network-online.target pve-cluster.service apt-daily.service apt-daily-upgrade.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pve-autoinstall.sh
RemainAfterExit=yes

[Install]
WantedBy=
EOF

# Таймер для устойчивого старта pve-autoinstall после загрузки
sudo tee "$PROXMOX_ISO_ROOT/squashfs-root/etc/systemd/system/pve-autoinstall.timer" << 'EOF'
[Unit]
Description=Delay start pve-autoinstall

[Timer]
OnBootSec=5min
Unit=pve-autoinstall.service
Persistent=true

[Install]
WantedBy=timers.target
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
WantedBy=
EOF

# Таймер для устойчивого старта pve-restore-backups после загрузки
sudo tee "$PROXMOX_ISO_ROOT/squashfs-root/etc/systemd/system/pve-restore-backups.timer" << 'EOF'
[Unit]
Description=Delay start pve-restore-backups

[Timer]
OnBootSec=5min
Unit=pve-restore-backups.service
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Тестовая директория для SCP в контейнер 
sudo mkdir -p "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/share/autolxc-prod/test-dir"
echo -n "test" | sudo tee "$PROXMOX_ISO_ROOT/squashfs-root/usr/local/share/autolxc-prod/test-dir/test.txt" > /dev/null

# Автостарт сервисов после установки системы
sudo mkdir -p "$PROXMOX_ISO_ROOT/squashfs-root/etc/systemd/system/timers.target.wants"
sudo ln -sf ../pve-autoinstall.timer "$PROXMOX_ISO_ROOT/squashfs-root/etc/systemd/system/timers.target.wants/pve-autoinstall.timer"
sudo ln -sf ../pve-restore-backups.timer "$PROXMOX_ISO_ROOT/squashfs-root/etc/systemd/system/timers.target.wants/pve-restore-backups.timer"

echo "[prepare] done. Put binaries in $PROXMOX_ISO_ROOT/binaries/ and run build.sh."
