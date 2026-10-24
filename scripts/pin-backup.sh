#!/bin/bash
# Закреплённая резервная копия прогресса: ~/Library/Application Support/TenFingers.backup-<метка>-<дата>.
# Ротация build-app.sh эту папку не трогает (она чистит только TenFingers.backups).
# Использование: ./scripts/pin-backup.sh <метка>      например: ./scripts/pin-backup.sh before-phase4
#
# Исходная база открывается только для чтения (`file:...?mode=ro`), ничего в ней и в ~/.../TenFingers не меняется;
# запись идёт только в новую папку. Существующую папку с тем же именем скрипт не перезаписывает.
set -euo pipefail

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
        TenFingers.store|*-wal|*-shm) ;;
        *) cp -R "$item" "$DEST/" ;;
    esac
done

# Проверка целостности копии
CHECK=$(sqlite3 "file:$DEST/TenFingers.store?mode=ro" "pragma integrity_check")
if [ "$CHECK" != "ok" ]; then
    echo "Копия не прошла integrity_check: $CHECK" >&2
    exit 1
fi
SESSIONS=$(sqlite3 "file:$DEST/TenFingers.store?mode=ro" "select count(*) from ZSESSIONRECORD" 2>/dev/null || echo "?")
echo "Закреплённая копия: $DEST (integrity_check: ok, сессий: $SESSIONS)"
