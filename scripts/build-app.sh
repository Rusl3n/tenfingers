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
codesign --force --deep --sign - "$APP"

# Прежние установки под старым именем и в ~/Applications больше не нужны
rm -rf ~/Applications/TenFingers.app /Applications/TenFingers.app
rm -rf "/Applications/$NAME"
cp -R "$APP" /Applications/
echo "Установлено: /Applications/$NAME"
