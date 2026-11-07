#!/bin/bash
# Закреплённая резервная копия прогресса: ~/Library/Application Support/TenFingers.backup-<метка>-<дата>.
# Ротация build-app.sh эту папку не трогает (она чистит только TenFingers.backups).
# Использование: ./scripts/pin-backup.sh <метка>      например: ./scripts/pin-backup.sh before-phase4
#
# Исходная база открывается только для чтения (`file:...?mode=ro`), ничего в ней и в ~/.../TenFingers не меняется;
# запись идёт только в новую папку. Существующую папку с тем же именем скрипт не перезаписывает.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib-generation.sh
source "$SCRIPT_DIR/lib-generation.sh"

LABEL="${1:-}"
if [ -z "$LABEL" ] || [[ ! "$LABEL" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Использование: $0 <метка> (латиница, цифры, точка, дефис, подчёркивание)" >&2
    exit 2
fi

SUPPORT="$HOME/Library/Application Support"
STORE_DIR="$SUPPORT/TenFingers"
STORE="$STORE_DIR/TenFingers.store"
DEST="$SUPPORT/TenFingers.backup-$LABEL-$(date +%Y-%m-%d)"

[ -f "$STORE" ] || { echo "Нет базы: $STORE" >&2; exit 1; }
command -v sqlite3 >/dev/null 2>&1 || { echo "Не найден sqlite3" >&2; exit 1; }
[ ! -e "$DEST" ] || { echo "Уже существует, не перезаписываю: $DEST" >&2; exit 1; }

mkdir "$DEST"
if ! sqlite3 "file:$STORE?mode=ro" ".backup '$DEST/TenFingers.store'"; then
    rm -rf "$DEST"
    echo "sqlite3 не смог скопировать базу; копия не создана" >&2
    exit 1
fi

# Остальные файлы папки (маркер поколения и т. п.), кроме самой базы и её -wal/-shm (они уже в копии)
for item in "$STORE_DIR"/* "$STORE_DIR"/.[!.]*; do
    [ -e "$item" ] || continue
    case "$(basename "$item")" in
        TenFingers.store|*-wal|*-shm|Profiles) ;;
        *) cp -R "$item" "$DEST/" ;;
    esac
done

# Базы профилей (Profiles/<uuid>): каждая через `.backup` в ту же относительную папку, прочие файлы — как у корня
PROFILE_COPIES=()
while IFS= read -r profile_dir; do
    [ -f "$profile_dir/TenFingers.store" ] || continue
    PROFILE_DEST="$DEST/Profiles/$(basename "$profile_dir")"
    mkdir -p "$PROFILE_DEST"
    if ! sqlite3 "file:$profile_dir/TenFingers.store?mode=ro" ".backup '$PROFILE_DEST/TenFingers.store'"; then
        rm -rf "$DEST"
        echo "sqlite3 не смог скопировать базу профиля $(basename "$profile_dir"); копия не создана" >&2
        exit 1
    fi
    for item in "$profile_dir"/* "$profile_dir"/.[!.]*; do
        [ -e "$item" ] || continue
        case "$(basename "$item")" in
            TenFingers.store|*-wal|*-shm) ;;
            *) cp -R "$item" "$PROFILE_DEST/" ;;
        esac
    done
    PROFILE_COPIES+=("$PROFILE_DEST")
done < <(profile_store_dirs "$STORE_DIR")

# Проверка целостности копии
CHECK=$(sqlite3 "file:$DEST/TenFingers.store?mode=ro" "pragma integrity_check")
if [ "$CHECK" != "ok" ]; then
    echo "Копия не прошла integrity_check: $CHECK" >&2
    exit 1
fi
SESSIONS=$(sqlite3 "file:$DEST/TenFingers.store?mode=ro" "select count(*) from ZSESSIONRECORD" 2>/dev/null || echo "?")
echo "Закреплённая копия: $DEST (integrity_check: ok, сессий: $SESSIONS)"
# Каждая база профиля: та же проверка и число сессий отдельной строкой (корень остаётся первой строкой)
for copy in ${PROFILE_COPIES[@]+"${PROFILE_COPIES[@]}"}; do
    CHECK=$(sqlite3 "file:$copy/TenFingers.store?mode=ro" "pragma integrity_check")
    if [ "$CHECK" != "ok" ]; then
        echo "Копия профиля не прошла integrity_check: $copy: $CHECK" >&2
        exit 1
    fi
    SESSIONS=$(sqlite3 "file:$copy/TenFingers.store?mode=ro" "select count(*) from ZSESSIONRECORD" 2>/dev/null || echo "?")
    echo "Профиль $(basename "$copy"): integrity_check: ok, сессий: $SESSIONS"
done
