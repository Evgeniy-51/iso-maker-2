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

### Рекомендуемый каталог на машине сборки

Все артефакты, которые не входят в git `iso-maker-2`, держите **на одном уровне** с каталогом клона:

```text
<workspace>/
  iso-maker-2/                    # git clone (репозиторий)
    Custom-iso-maker/
      prepare.sh
      build.sh
  stack/                          # payload для ISO
  pve-autoinstall.sh
  pve-restore-backups.sh
```

То есть `stack`, `pve-autoinstall.sh` и `pve-restore-backups.sh` — **соседи** `iso-maker-2`, не внутри репозитория.

`prepare.sh` вычисляет каталог `LAYOUT_ROOT`: если скрипт лежит в `iso-maker-2/Custom-iso-maker/`, то `LAYOUT_ROOT` = родитель `iso-maker-2`; если `prepare.sh` лежит в корне `iso-maker-2/`, то `LAYOUT_ROOT` = родитель `iso-maker-2` (тот же уровень, что и сам каталог репозитория).

### Поиск stack и pve-скриптов (по умолчанию)

`prepare.sh` ищет в таком порядке:

**pve-autoinstall.sh / pve-restore-backups.sh**

1. `PVE_AUTOINSTALL_SRC` / `PVE_RESTORE_BACKUPS_SRC` (если заданы)
2. `$LAYOUT_ROOT/pve-autoinstall.sh` и т.д. (рядом с `iso-maker-2`)
3. внутри репозитория и fallback-пути (`$PWD`, родитель cwd и т.д.)

**stack**

1. `STACK_SRC_DIR` (если задан)
2. `$LAYOUT_ROOT/stack`
3. `stack/` внутри репозитория и остальные fallback-пути

## 2. build.sh

Сборка ISO (папка `binaries/` создаётся при `prepare.sh`, но не обязательна):

```bash
./build.sh
```

- Если в `PROXMOX_ISO_ROOT/binaries/` есть обычные файлы — для каждого: `dist/proxmox-<имя_файла>.iso` (бинарь копируется в `/usr/local/sbin/autolxc`).
- Если `binaries/` пустая — один образ `dist/proxmox-custom.iso` (или `DEFAULT_ISO_NAME`), в `/usr/local/sbin/autolxc` кладётся no-op скрипт, чтобы `autolxc.service` не падал.

**Переменные:** `PROXMOX_ISO_ROOT`, `DIST_DIR`, `DEFAULT_ISO_NAME`, `SQUASHFS_OPTS`  
Сборка `squashfs`: по умолчанию `xz` без `-Xcompression-level` (старые `squashfs-tools` его не поддерживают). Свои опции: `SQUASHFS_OPTS='-comp xz -noappend -no-xattrs -b 1M -Xdict-size 75%' ./build.sh`  
Сборка ISO выполняется с `xorriso -iso-level 3` (поддержка больших файлов в образе).

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

1. Собрать layout: рядом с `iso-maker-2` положить `stack/`, `pve-autoinstall.sh`, `pve-restore-backups.sh` (см. раздел «Рекомендуемый каталог»).

2. Дать право на исполнение:
   ```bash
   chmod +x iso-maker-2/Custom-iso-maker/prepare.sh iso-maker-2/Custom-iso-maker/build.sh
   chmod +x pve-autoinstall.sh pve-restore-backups.sh
   ```

3. Запуск из каталога со скриптами сборки (обычно `iso-maker-2/Custom-iso-maker/`; если `prepare.sh` лежит в корне репозитория — `cd iso-maker-2`):
   ```bash
   cd iso-maker-2/Custom-iso-maker
   ./prepare.sh
   ./build.sh
   ```

   Опционально: `~/proxmox_iso/binaries/<файлы для autolxc>` — если нужны варианты ISO с разным `autolxc`.

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
