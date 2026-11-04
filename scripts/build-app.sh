#!/bin/bash
# Собирает TenFingers.app (release) через scripts/make-bundle.sh (сборка, версия, подпись ad-hoc) и устанавливает в /Applications.
# Имя в Finder и Dock локализовано (Localization/*/InfoPlist.strings): «Десять пальцев» / «TenFingers».
# Старый бандл «Десять пальцев.app» при установке удаляется (если он запущен, сначала закрывается).
# Иконка: scripts/AppIcon.icns (перерисовать: swift scripts/make-icon.swift build/icon).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib-generation.sh
source "$SCRIPT_DIR/lib-generation.sh"
cd "$SCRIPT_DIR/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

STORE_DIR="$HOME/Library/Application Support/TenFingers"

# Защита от отката (спецификация §20): если базу уже записала версия с более новым поколением схемы,
# эту сборку не ставим — она базу не откроет. Проверка идёт до сборки, резервной копии, закрытия
# приложения и удаления бандлов, поэтому при отказе ничего не меняется. Маркера нет или он не читается —
# ставим как раньше: приложение само разберётся при открытии базы.
BUILD_GENERATION=$(schema_generation) || exit 1
MARKER="$STORE_DIR/TenFingers.store.generation"
if [ -f "$MARKER" ] && [ -r "$MARKER" ]; then
    STORE_GENERATION=$(tr -d '[:space:]' < "$MARKER" || true)
    if [[ "$STORE_GENERATION" =~ ^[0-9]{1,9}$ ]] && [ "$((10#$STORE_GENERATION))" -gt "$BUILD_GENERATION" ]; then
        echo "Установка отменена: база прогресса записана более новой версией приложения." >&2
        echo "  Поколение схемы базы:   $((10#$STORE_GENERATION)) ($MARKER)" >&2
        echo "  Поколение схемы сборки: $BUILD_GENERATION (SchemaGeneration.current)" >&2
        echo "Эта сборка не откроет базу. Соберите ветку с поколением не ниже $((10#$STORE_GENERATION))." >&2
        echo "Установленное приложение и база не тронуты." >&2
        exit 1
    fi
fi

NAME="TenFingers.app"
OLD_NAME="Десять пальцев.app"
# Сборка, версия и подпись — в make-bundle.sh (общий с CI). Последняя строка его stdout — путь к .app,
# остальное (строка «Версия: ...») показываем как раньше.
# Старые бандлы в build/ (в том числе «Десять пальцев.app») убираем здесь: make-bundle.sh удаляет только свой.
rm -rf build/*.app
BUNDLE_OUT=$("$SCRIPT_DIR/make-bundle.sh")
printf '%s\n' "$BUNDLE_OUT" | sed '$d'
APP=$(printf '%s\n' "$BUNDLE_OUT" | tail -n1)
[ -d "$APP" ] || { echo "make-bundle.sh не вернул путь к бандлу: $APP" >&2; exit 1; }

# Резервная копия прогресса перед установкой новой сборки.
# База копируется через `sqlite3 .backup` (согласованная копия, даже если приложение запущено);
# источник открывается только для чтения, поэтому sqlite3 ничего в нём не меняет (не сливает -wal).
# Хранятся последние 10 копий и, кроме них, самая новая копия каждого дня за последние 30 дней.
# Закреплённые копии (TenFingers.backup-before-phase2, TenFingers.backup-<метка>-<дата> от scripts/pin-backup.sh)
# лежат отдельно, рядом с TenFingers.backups, и ротация их не трогает: она чистит только папки <дата>_<время> внутри.
BACKUPS="$HOME/Library/Application Support/TenFingers.backups"
if [ -d "$STORE_DIR" ]; then
    DEST="$BACKUPS/$(date +%Y-%m-%d_%H-%M-%S)"
    mkdir -p "$DEST"
    STORE="$STORE_DIR/TenFingers.store"
    COPIED_DB=0
    if [ -f "$STORE" ] && command -v sqlite3 >/dev/null 2>&1; then
        if sqlite3 "file:$STORE?mode=ro" ".backup '$DEST/TenFingers.store'"; then
            COPIED_DB=1
        else
            rm -f "$DEST/TenFingers.store"
            echo "sqlite3 не смог скопировать базу, копирую файлы как есть" >&2
        fi
    fi
    if [ "$COPIED_DB" = 1 ]; then
        # Остальные файлы папки, кроме самой базы и её -wal/-shm (они уже в копии базы)
        for item in "$STORE_DIR"/* "$STORE_DIR"/.[!.]*; do
            [ -e "$item" ] || continue
            case "$(basename "$item")" in
                TenFingers.store|*-wal|*-shm) ;;
                *) cp -R "$item" "$DEST/" ;;
            esac
        done
    else
        cp -R "$STORE_DIR"/. "$DEST/"
    fi
    echo "Резервная копия прогресса: $DEST"

    CUTOFF=$(date -v-30d +%Y-%m-%d)
    SEEN_DAYS=" "
    INDEX=0
    for dir in $(cd "$BACKUPS" && ls -1d [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_* 2>/dev/null | sort -r); do
        DAY="${dir%%_*}"
        KEEP=0
        [ "$INDEX" -lt 10 ] && KEEP=1
        case "$SEEN_DAYS" in
            *" $DAY "*) ;;
            *)
                SEEN_DAYS="$SEEN_DAYS$DAY "
                # Самая новая копия дня за последние 30 дней остаётся всегда
                if [[ ! "$DAY" < "$CUTOFF" ]]; then KEEP=1; fi
                ;;
        esac
        if [ "$KEEP" = 0 ]; then rm -rf "${BACKUPS:?}/$dir"; fi
        INDEX=$((INDEX + 1))
    done
fi

# Прежние установки в ~/Applications больше не нужны
rm -rf ~/Applications/TenFingers.app
# Запущенное старое приложение закрываем до удаления
if pgrep -f "/Applications/$OLD_NAME/Contents/MacOS/TenFingers" >/dev/null; then
    pkill -f "/Applications/$OLD_NAME/Contents/MacOS/TenFingers" || true
    sleep 1
fi
rm -rf "/Applications/$NAME"
cp -R "$APP" /Applications/
rm -rf "/Applications/$OLD_NAME"
# Промежуточный бандл в build/ больше не нужен: иначе Spotlight и Launchpad показывают второе приложение.
rm -rf "$APP"
echo "Установлено: /Applications/$NAME"
