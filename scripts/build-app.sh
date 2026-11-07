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
# Поколение проверяется у каждой базы: корневой и баз профилей (Profiles/<uuid>).
check_store_generation "$STORE_DIR" "$BUILD_GENERATION" || exit 1
while IFS= read -r profile_dir; do
    check_store_generation "$profile_dir" "$BUILD_GENERATION" || exit 1
done < <(profile_store_dirs "$STORE_DIR")

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
                TenFingers.store|*-wal|*-shm|Profiles) ;;
                *) cp -R "$item" "$DEST/" ;;
            esac
        done
    else
        for item in "$STORE_DIR"/* "$STORE_DIR"/.[!.]*; do
            [ -e "$item" ] || continue
            [ "$(basename "$item")" = "Profiles" ] || cp -R "$item" "$DEST/"
        done
    fi
    # Базы профилей: каждая тоже через `.backup` в ту же относительную папку копии, прочие файлы профиля — как у корня.
    while IFS= read -r profile_dir; do
        PROFILE_DEST="$DEST/Profiles/$(basename "$profile_dir")"
        mkdir -p "$PROFILE_DEST"
        PROFILE_DB=0
        if [ -f "$profile_dir/TenFingers.store" ] && command -v sqlite3 >/dev/null 2>&1; then
            if sqlite3 "file:$profile_dir/TenFingers.store?mode=ro" ".backup '$PROFILE_DEST/TenFingers.store'"; then
                PROFILE_DB=1
            else
                rm -f "$PROFILE_DEST/TenFingers.store"
                echo "sqlite3 не смог скопировать базу профиля $(basename "$profile_dir"), копирую файлы как есть" >&2
            fi
        fi
        for item in "$profile_dir"/* "$profile_dir"/.[!.]*; do
            [ -e "$item" ] || continue
            case "$(basename "$item")" in
                TenFingers.store|*-wal|*-shm) [ "$PROFILE_DB" = 1 ] || cp -R "$item" "$PROFILE_DEST/" ;;
                *) cp -R "$item" "$PROFILE_DEST/" ;;
            esac
        done
    done < <(profile_store_dirs "$STORE_DIR")
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
# Старый процесс виджета тоже: иначе система спросит описание виджета у него, а не у нового бандла
pkill -x TenFingersWidget || true
rm -rf "/Applications/$NAME"
cp -R "$APP" /Applications/
rm -rf "/Applications/$OLD_NAME"
# Промежуточный бандл в build/ больше не нужен: иначе Spotlight и Launchpad показывают второе приложение.
rm -rf "$APP"
# Старый процесс виджета мог успеть перезапуститься во время замены и держать прежнее описание: завершаем его ещё раз
# и заново регистрируем приложение и расширение, чтобы система перечитала описание и настройки виджета.
# Ошибки не критичны (виджета может не быть, pluginkit может отказать): установку они не роняют.
pkill -x TenFingersWidget || true
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "/Applications/$NAME" || true
WIDGET_APPEX="/Applications/$NAME/Contents/PlugIns/TenFingersWidget.appex"
if [ -d "$WIDGET_APPEX" ]; then
    pluginkit -a "$WIDGET_APPEX" || true
fi
echo "Установлено: /Applications/$NAME"
