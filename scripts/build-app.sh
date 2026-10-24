#!/bin/bash
# Собирает TenFingers.app (release), подписывает ad-hoc и устанавливает в /Applications.
# Имя в Finder и Dock локализовано (Localization/*/InfoPlist.strings): «Десять пальцев» / «TenFingers».
# Старый бандл «Десять пальцев.app» при установке удаляется (если он запущен, сначала закрывается).
# Иконка: scripts/AppIcon.icns (перерисовать: swift scripts/make-icon.swift build/icon).
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

STORE_DIR="$HOME/Library/Application Support/TenFingers"

# Защита от отката (спецификация §20): если базу уже записала версия с более новым поколением схемы,
# эту сборку не ставим — она базу не откроет. Проверка идёт до сборки, резервной копии, закрытия
# приложения и удаления бандлов, поэтому при отказе ничего не меняется. Маркера нет или он не читается —
# ставим как раньше: приложение само разберётся при открытии базы.
BUILD_GENERATION=$(sed -n 's/^[[:space:]]*static let current = \([0-9][0-9]*\).*$/\1/p' \
    Sources/TenFingers/Persistence/SchemaGeneration.swift)
[ -n "$BUILD_GENERATION" ] || {
    echo "Не удалось прочитать SchemaGeneration.current из Sources/TenFingers/Persistence/SchemaGeneration.swift" >&2
    exit 1
}
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
echo "Установлено: /Applications/$NAME"
