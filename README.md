# Сборка кастомных ISO Proxmox VE

Скрипты для сборки кастомных ISO Proxmox VE. Один раз подготавливается база (официальный ISO + squashfs + systemd-юниты). Дальше `build.sh`: если в `binaries/` есть файлы — для каждого собирается `proxmox-<имя_файла>.iso`; если папка пустая — один образ `proxmox-custom.iso` (имя задаётся `DEFAULT_ISO_NAME`), без кастомного `autolxc` ставится no-op stub.

## 1. prepare.sh

Запустить **один раз** на Ubuntu:

- Устанавливает `xorriso`, `squashfs-tools`, `rsync`, `wget`
- Скачивает официальный Proxmox VE 9.1-1 в `~/proxmox_iso/proxmox-ve.iso`
- Распаковывает ISO в `extract/`, `pve-base.squashfs` в `squashfs-root/`
- Добавляет в squashfs systemd-юнит `autolxc.service` и wants-симлинк
- Вшивает скрипты:
  - `/usr/local/sbin/pve-autoinstall.sh`
  - `/usr/local/sbin/pve-restore-backups.sh`
- Вшивает `stack` payload в `/opt/bootstrap-stack` внутри ISO (для bootstrap в `/mnt/stack` на установленной системе)
- Создаёт и включает (через `multi-user.target.wants`) юниты:
  - `pve-autoinstall.service`
  - `pve-restore-backups.service`
- Эти два юнита запускаются параллельно после загрузки системы
- Создаёт папку `binaries/` для исходных бинарников (используется в build.sh)

**Переменные:** `PROXMOX_ISO_ROOT` (по умолчанию `~/proxmox_iso`), `PROXMOX_ISO_URL`, `PVE_AUTOINSTALL_SRC`, `PVE_RESTORE_BACKUPS_SRC`, `STACK_SRC_DIR`

### Поиск stack (по умолчанию)

`prepare.sh` ищет `stack` в таком порядке:

1. `STACK_SRC_DIR` (если задан)
2. `../stack` (соседняя директория рядом с репозиторием `iso-maker-2`)
3. `./stack` (внутри репозитория)
4. fallback-пути рядом со скриптом/текущей директорией

## 2. build.sh

Сборка ISO (папка `binaries/` создаётся при `prepare.sh`, но не обязательна):

```bash
./build.sh
```

- Если в `PROXMOX_ISO_ROOT/binaries/` есть обычные файлы — для каждого: `dist/proxmox-<имя_файла>.iso` (бинарь копируется в `/usr/local/sbin/autolxc`).
- Если `binaries/` пустая — один образ `dist/proxmox-custom.iso` (или `DEFAULT_ISO_NAME`), в `/usr/local/sbin/autolxc` кладётся no-op скрипт, чтобы `autolxc.service` не падал.

**Переменные:** `PROXMOX_ISO_ROOT`, `DIST_DIR`, `DEFAULT_ISO_NAME`  
Сборка `squashfs` использует `xz` с уровнем сжатия `3` (`-Xcompression-level 3`).

## Порядок работы

1. Запустить `./prepare.sh` один раз  
2. (Опционально) положить бинарники в `binaries/` для нескольких вариантов ISO с разным `autolxc`  
3. Запустить `./build.sh` без аргументов  

## Поведение после установки Proxmox из собранного ISO

- `pve-autoinstall.sh` и `pve-restore-backups.sh` запускаются автоматически через systemd
- В `/mnt` используется только `stack`
- Если `/mnt/stack` отсутствует или пустой, он автоматически bootstrap-ится из `/opt/bootstrap-stack` (вшитого в ISO)
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
   # опционально: ~/proxmox_iso/binaries/<файлы для autolxc>
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
