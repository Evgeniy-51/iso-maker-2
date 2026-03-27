# Сборка кастомных ISO Proxmox VE

Скрипты для сборки кастомных ISO Proxmox VE. Один раз подготавливается база (официальный ISO + squashfs + systemd-юниты), затем для каждого бинарника из папки `binaries/` собирается образ `proxmox-<имя_файла>.iso`.

## 1. prepare.sh

Запустить **один раз** на Ubuntu:

- Устанавливает `xorriso`, `squashfs-tools`, `rsync`, `wget`
- Скачивает официальный Proxmox VE 9.1-1 в `~/proxmox_iso/proxmox-ve.iso`
- Распаковывает ISO в `extract/`, `pve-base.squashfs` в `squashfs-root/`
- Добавляет в squashfs systemd-юнит `autolxc.service` и wants-симлинк
- Вшивает скрипты:
  - `/usr/local/sbin/pve-autoinstall.sh`
  - `/usr/local/sbin/pve-restore-backups.sh`
- Создаёт и включает (через `multi-user.target.wants`) юниты:
  - `pve-autoinstall.service`
  - `pve-restore-backups.service`
- Эти два юнита запускаются параллельно после загрузки системы
- Создаёт папку `binaries/` для исходных бинарников (используется в build.sh)

**Переменные:** `PROXMOX_ISO_ROOT` (по умолчанию `~/proxmox_iso`), `PROXMOX_ISO_URL`

## 2. build.sh

Сборка ISO по бинарникам из папки `binaries/` (создаётся при prepare):

```bash
./build.sh
```

Цикл по всем файлам в `PROXMOX_ISO_ROOT/binaries/`. Один файл — один образ. Готовые ISO: `dist/proxmox-<имя_файла>.iso` (или `DIST_DIR`).

**Переменные:** `PROXMOX_ISO_ROOT`, `DIST_DIR`

## Порядок работы

1. Запустить `./prepare.sh` один раз  
2. Положить бинарники в `binaries/`  
3. Запустить `./build.sh` без аргументов  

## Поведение после установки Proxmox из собранного ISO

- `pve-autoinstall.sh` и `pve-restore-backups.sh` запускаются автоматически через systemd
- В `/mnt` используется только `stack`
- Директория бэкапов создаётся автоматически внутри stack: `/mnt/stack/backup`
- `pve-restore-backups.sh` скачивает backup-архивы в `/mnt/stack/backup` и выполняет `qmrestore`

---

## Запуск на машине сборки (Ubuntu)

1. Перенести скрипты на машину сборки 

2. Дать право на исполнение:
   ```bash
   chmod +x prepare.sh build.sh
   ```

3. Запуск (из каталога со скриптами):
   ```bash
   ./prepare.sh
   # положить бинарники в ~/proxmox_iso/binaries/
   ./build.sh
   ```

   Либо задать корень сборки:
   ```bash
   PROXMOX_ISO_ROOT=/path/to/proxmox_iso ./prepare.sh
   PROXMOX_ISO_ROOT=/path/to/proxmox_iso ./build.sh
   ```
---

## Переносы строк (CRLF / LF)

В репозитории для `*.sh` заданы Unix-переносы (LF) через `.gitattributes` — при клонировании на Ubuntu файлы уже с LF и должны запускаться без доработок.

Если скрипты копировали не через git и при `./prepare.sh` появляется ошибка **«bash\r»** или **«No such file or directory»** в shebang — один раз выполнить:

```bash
sed -i 's/\r$//' prepare.sh build.sh
```
