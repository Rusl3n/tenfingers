#!/bin/bash
# Собирает «Десять пальцев.app» (release), подписывает ad-hoc и устанавливает в /Applications.
# Иконка: scripts/AppIcon.icns (перерисовать: swift scripts/make-icon.swift build/icon).
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

NAME="Десять пальцев.app"
swift build -c release --product TenFingers
BIN=$(swift build -c release --show-bin-path)
APP="build/$NAME"

rm -rf build/*.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/TenFingers" "$APP/Contents/MacOS/"
cp -R "$BIN/TenFingers_TypingCore.bundle" "$APP/Contents/Resources/"
cp scripts/AppIcon.icns "$APP/Contents/Resources/"
# Переводы приложения (Localizable.strings, InfoPlist.strings): ресурсы исполняемого таргета не попадают в Bundle.main
cp -R Localization/*.lproj "$APP/Contents/Resources/"
cp scripts/Info.plist "$APP/Contents/Info.plist"

# Версия подставляется в копию Info.plist внутри .app (исходный scripts/Info.plist не меняется) и обязательно до codesign:
#   CFBundleShortVersionString — файл VERSION (семантическая версия, например 0.3.0-dev);
#   CFBundleVersion            — число коммитов (git rev-list --count HEAD);
#   TFGitCommit                — короткий хэш коммита, с суффиксом -dirty при незакоммиченных изменениях.
# Вне git-репозитория (например, из архива исходников) — сборка 0 и коммит unknown, без проверки изменений.
VERSION=$(tr -d '[:space:]' < VERSION)
[ -n "$VERSION" ] || { echo "Файл VERSION пуст" >&2; exit 1; }
if command -v git >/dev/null 2>&1 && git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    BUILD=$(git rev-list --count HEAD)
    COMMIT=$(git rev-parse --short HEAD)
    if [ -n "$(git status --porcelain)" ]; then COMMIT="$COMMIT-dirty"; fi
else
    BUILD=0
    COMMIT=unknown
    echo "Не git-репозиторий: номер сборки 0, коммит unknown" >&2
fi
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :TFGitCommit string $COMMIT" "$PLIST"
echo "Версия: $VERSION (сборка $BUILD, $COMMIT)"

codesign --force --deep --sign - "$APP"

# Резервная копия прогресса перед установкой новой сборки.
# База копируется через `sqlite3 .backup` (согласованная копия, даже если приложение запущено);
# источник открывается только для чтения, поэтому sqlite3 ничего в нём не меняет (не сливает -wal).
# Хранятся последние 10 копий и, кроме них, самая новая копия каждого дня за последние 30 дней.
# Закреплённые копии (TenFingers.backup-before-phase2, TenFingers.backup-<метка>-<дата> от scripts/pin-backup.sh)
# лежат отдельно, рядом с TenFingers.backups, и ротация их не трогает: она чистит только папки <дата>_<время> внутри.
STORE_DIR="$HOME/Library/Application Support/TenFingers"
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

# Прежние установки под старым именем и в ~/Applications больше не нужны
rm -rf ~/Applications/TenFingers.app /Applications/TenFingers.app
rm -rf "/Applications/$NAME"
cp -R "$APP" /Applications/
echo "Установлено: /Applications/$NAME"
