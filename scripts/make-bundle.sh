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

# Вывод swift build — в stderr, чтобы stdout остался предсказуемым.
# Настройки виджета (AppIntents) система читает из Metadata.appintents. SwiftPM его не делает, поэтому компилятор
# сохраняет константы типов AppIntents (.swiftconstvalues, список протоколов — scripts/appintents-protocols.json),
# а ниже appintentsmetadataprocessor из Xcode собирает из них метаданные. Флаги одинаковы для обоих продуктов,
# чтобы второй swift build не пересобирал первый.
CONST_FLAGS=(-Xswiftc -emit-const-values
    -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file
    -Xswiftc -Xfrontend -Xswiftc "$PWD/scripts/appintents-protocols.json")
swift build -c release --product TenFingers "${CONST_FLAGS[@]}" >&2
swift build -c release --product TenFingersWidget "${CONST_FLAGS[@]}" >&2
BIN=$(swift build -c release --show-bin-path "${CONST_FLAGS[@]}")
APP="$OUTPUT/$NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/TenFingers" "$APP/Contents/MacOS/"
cp -R "$BIN/TenFingers_TypingCore.bundle" "$APP/Contents/Resources/"
cp scripts/AppIcon.icns "$APP/Contents/Resources/"
# Помощник перезапуска после обновления (7b): установщик копирует его во временную папку и запускает через nohup
cp scripts/update-relaunch.sh "$APP/Contents/Resources/"
# Переводы приложения (Localizable.strings, InfoPlist.strings): ресурсы исполняемого таргета не попадают в Bundle.main
cp -R Localization/*.lproj "$APP/Contents/Resources/"
cp scripts/Info.plist "$APP/Contents/Info.plist"

# Виджет (7c): расширение WidgetKit в Contents/PlugIns. Переводы виджета лежат в Resources самого .appex (в Bundle.main приложения их нет).
APPEX="$APP/Contents/PlugIns/TenFingersWidget.appex"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
cp "$BIN/TenFingersWidget" "$APPEX/Contents/MacOS/"
cp -R Sources/TenFingersWidget/Resources/*.lproj "$APPEX/Contents/Resources/"
cp scripts/TenFingersWidget-Info.plist "$APPEX/Contents/Info.plist"
# Metadata.appintents виджета: без него «Изменить виджет» не покажет «Содержимое», «Приглашение» и «Шуточные 18+»
AI_WORK=$(mktemp -d)
trap 'rm -rf "$AI_WORK"' EXIT
find "$PWD/Sources/TenFingersWidget" -name '*.swift' | sort > "$AI_WORK/sources.txt"
echo "$BIN/TenFingersWidget.build/TenFingersWidget.swiftconstvalues" > "$AI_WORK/constvalues.txt"
[ -f "$BIN/TenFingersWidget.build/TenFingersWidget.swiftconstvalues" ] || { echo "Нет констант AppIntents виджета" >&2; exit 1; }
XCODE_BUILD=$(xcodebuild -version | awk '/Build version/ {print $3}')
# Локально DEVELOPER_DIR задан выше, в CI Xcode выбран через xcode-select
TOOLCHAIN="${DEVELOPER_DIR:-$(xcode-select -p)}/Toolchains/XcodeDefault.xctoolchain"
xcrun appintentsmetadataprocessor --output "$APPEX/Contents/Resources" \
    --toolchain-dir "$TOOLCHAIN" --module-name TenFingersWidget \
    --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" --xcode-version "$XCODE_BUILD" --platform-family macOS \
    --deployment-target 15.0 --target-triple "$(uname -m)-apple-macos15.0" \
    --source-file-list "$AI_WORK/sources.txt" --swift-const-vals-list "$AI_WORK/constvalues.txt" \
    --binary-file "$APPEX/Contents/MacOS/TenFingersWidget" >&2
[ -f "$APPEX/Contents/Resources/Metadata.appintents/extract.actionsdata" ] || { echo "Не собран Metadata.appintents виджета" >&2; exit 1; }

# Версия подставляется в копию Info.plist внутри .app (исходный scripts/Info.plist не меняется) и обязательно до codesign:
#   CFBundleShortVersionString — файл VERSION (семантическая версия, например 0.3.0-dev);
#   CFBundleVersion            — число коммитов плюс BUILD_OFFSET (git rev-list --count HEAD + 500): в публичном
#                                репозитории по коммиту на версию, а сдвиг продолжает ряд сборок до публикации (до 500);
#   TFGitCommit                — короткий хэш коммита, с суффиксом -dirty при незакоммиченных изменениях;
#   TFSchemaGeneration         — поколение схемы базы (SchemaGeneration.current), число: по нему обновление
#                                проверяет, что новая версия откроет базу.
# Вне git-репозитория (например, из архива исходников) — сборка 0 и коммит unknown, без проверки изменений.
BUILD_OFFSET=500
VERSION=$(tr -d '[:space:]' < VERSION)
[ -n "$VERSION" ] || { echo "Файл VERSION пуст" >&2; exit 1; }
if command -v git >/dev/null 2>&1 && git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    BUILD=$(( $(git rev-list --count HEAD) + BUILD_OFFSET ))
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
# Расширение получает ту же версию и номер сборки, что и приложение
APPEX_PLIST="$APPEX/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APPEX_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APPEX_PLIST"
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
