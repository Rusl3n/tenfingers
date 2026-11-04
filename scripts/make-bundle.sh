#!/bin/bash
# Собирает TenFingers.app (release) и подписывает ad-hoc. Ничего не устанавливает: не трогает /Applications,
# базу прогресса и резервные копии. Его вызывают build-app.sh (локально) и CI (релиз).
# Использование: scripts/make-bundle.sh [--output DIR]   (по умолчанию build/)
# Последняя строка stdout — абсолютный путь к собранному .app; остальной вывод (версия) идёт раньше,
# вывод swift build — в stderr. Код возврата не ноль при любой ошибке.
# Имя в Finder и Dock локализовано (Localization/*/InfoPlist.strings): «Десять пальцев» / «TenFingers».
# Иконка: scripts/AppIcon.icns (перерисовать: swift scripts/make-icon.swift build/icon).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib-generation.sh
source "$SCRIPT_DIR/lib-generation.sh"

OUTPUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --output)
            [ $# -ge 2 ] || { echo "После --output нужен путь к папке" >&2; exit 2; }
            OUTPUT="$2"
            shift 2
            ;;
        *)
            echo "Использование: $0 [--output DIR]" >&2
            exit 2
            ;;
    esac
done
# Относительный путь --output считается от текущей папки вызова, поэтому разбираем его до cd в корень репозитория
if [ -z "$OUTPUT" ]; then OUTPUT="$SCRIPT_DIR/../build"; fi
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"

cd "$SCRIPT_DIR/.."
# Xcode: заданный DEVELOPER_DIR (например, выбранный в CI через xcode-select) не трогаем. Иначе, если активны только
# Command Line Tools (или xcode-select не отвечает), берём /Applications/Xcode.app; иначе оставляем выбранный Xcode.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    SELECTED_DIR=$(xcode-select -p 2>/dev/null || true)
    case "$SELECTED_DIR" in
        ""|*/CommandLineTools*) export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ;;
    esac
fi

NAME="TenFingers.app"
GENERATION=$(schema_generation)

# Вывод swift build — в stderr, чтобы stdout остался предсказуемым
swift build -c release --product TenFingers >&2
BIN=$(swift build -c release --show-bin-path)
APP="$OUTPUT/$NAME"

rm -rf "$APP"
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
#   TFGitCommit                — короткий хэш коммита, с суффиксом -dirty при незакоммиченных изменениях;
#   TFSchemaGeneration         — поколение схемы базы (SchemaGeneration.current), число: по нему обновление
#                                проверяет, что новая версия откроет базу.
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
/usr/libexec/PlistBuddy -c "Add :TFSchemaGeneration integer $GENERATION" "$PLIST"
echo "Версия: $VERSION (сборка $BUILD, $COMMIT, поколение схемы $GENERATION)"

# Подпись ad-hoc, каждая часть отдельно (без рекурсивной подписи вложенного): сначала каждое расширение (Contents/PlugIns/*.appex) со своими entitlements
# (scripts/<имя без .appex>.entitlements), потом само приложение. Нет папки PlugIns — шаг пропускается.
if [ -d "$APP/Contents/PlugIns" ]; then
    for appex in "$APP/Contents/PlugIns"/*.appex; do
        [ -e "$appex" ] || continue
        EXT_NAME="$(basename "$appex" .appex)"
        ENTITLEMENTS="scripts/$EXT_NAME.entitlements"
        [ -f "$ENTITLEMENTS" ] || { echo "Нет файла entitlements: $ENTITLEMENTS" >&2; exit 1; }
        codesign --force --sign - --entitlements "$ENTITLEMENTS" "$appex" >&2
    done
fi
codesign --force --sign - "$APP" >&2
codesign --verify --strict "$APP" >&2

# Последняя строка stdout — путь к бандлу
echo "$APP"
