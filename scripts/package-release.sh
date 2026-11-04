#!/bin/bash
# Упаковывает собранный TenFingers.app в файлы релиза. Ничего не собирает и не публикует: ему нужен готовый .app
# (его делает scripts/make-bundle.sh), а выкладывает файлы release.yml.
# Использование: scripts/package-release.sh <путь к TenFingers.app> <папка для результата>
# В папке появляются:
#   TenFingers-<версия>.zip  — ditto -c -k --keepParent (сохраняет подпись и атрибуты);
#   TenFingers-<версия>.dmg  — .app и ссылка на /Applications, без фоновой картинки; том «TenFingers <версия>»;
#   release.json             — описание выпуска для проверки обновлений (docs/superpowers/specs/2026-11-04-phase7-distribution-design.md, §4);
#   SHA256SUMS               — контрольные суммы .zip и .dmg.
# Версия, сборка, коммит, поколение схемы и минимальная система читаются из Info.plist самого бандла, а не из исходников:
# в описании стоят ровно те числа, что внутри приложения. Код возврата не ноль при любой ошибке.
set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Использование: $0 <путь к TenFingers.app> <папка для результата>" >&2
    exit 2
fi
APP="$1"
OUTDIR="$2"
[ -d "$APP" ] || { echo "Нет приложения: $APP" >&2; exit 1; }
PLIST="$APP/Contents/Info.plist"
[ -f "$PLIST" ] || { echo "Нет Info.plist в $APP" >&2; exit 1; }
APP="$(cd "$APP" && pwd)"
PLIST="$APP/Contents/Info.plist"
mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || { echo "В Info.plist нет ключа $1" >&2; return 1; }
}

VERSION=$(plist_value CFBundleShortVersionString)
BUILD=$(plist_value CFBundleVersion)
COMMIT=$(plist_value TFGitCommit)
GENERATION=$(plist_value TFSchemaGeneration)
MIN_SYSTEM=$(plist_value LSMinimumSystemVersion)

# Значения попадают в JSON без экранирования, поэтому допускаем только простые символы
[[ "$VERSION" =~ ^[0-9A-Za-z.+-]+$ ]] || { echo "Недопустимая версия в Info.plist: $VERSION" >&2; exit 1; }
[[ "$COMMIT" =~ ^[0-9A-Za-z.-]+$ ]] || { echo "Недопустимый коммит в Info.plist: $COMMIT" >&2; exit 1; }
[[ "$MIN_SYSTEM" =~ ^[0-9.]+$ ]] || { echo "Недопустимая минимальная система в Info.plist: $MIN_SYSTEM" >&2; exit 1; }
case "$COMMIT" in
    *-dirty)
        echo "Отказ: бандл собран из незакоммиченных изменений (TFGitCommit = $COMMIT). Релиз упаковывается только из чистой сборки." >&2
        exit 1
        ;;
esac
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "Номер сборки не число: $BUILD" >&2; exit 1; }
[[ "$GENERATION" =~ ^[0-9]+$ ]] || { echo "Поколение схемы не число: $GENERATION" >&2; exit 1; }

ZIP="TenFingers-$VERSION.zip"
DMG="TenFingers-$VERSION.dmg"
rm -f "$OUTDIR/$ZIP" "$OUTDIR/$DMG" "$OUTDIR/release.json" "$OUTDIR/SHA256SUMS"

STAGING=$(mktemp -d "${TMPDIR:-/tmp}/tenfingers-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT

echo "Упаковка $VERSION (сборка $BUILD, $COMMIT, поколение схемы $GENERATION)" >&2

ditto -c -k --keepParent "$APP" "$OUTDIR/$ZIP"

# Содержимое окна .dmg: само приложение и ссылка на /Applications
ditto "$APP" "$STAGING/$(basename "$APP")"
ln -s /Applications "$STAGING/Applications"
# hdiutil на раннерах иногда отвечает «Resource busy»: один повтор через несколько секунд, потом падение
make_dmg() { hdiutil create -volname "TenFingers $VERSION" -srcfolder "$STAGING" -format UDZO -ov "$OUTDIR/$DMG" >&2; }
if ! make_dmg; then
    echo "hdiutil create не удался, повтор через 5 секунд" >&2
    sleep 5
    rm -f "$OUTDIR/$DMG"
    make_dmg || { echo "hdiutil create не удался и со второй попытки" >&2; exit 1; }
fi

size_of() { stat -f%z "$OUTDIR/$1"; }
sha_of() { shasum -a 256 "$OUTDIR/$1" | awk '{print $1}'; }

ZIP_SIZE=$(size_of "$ZIP")
DMG_SIZE=$(size_of "$DMG")
ZIP_SHA=$(sha_of "$ZIP")
DMG_SHA=$(sha_of "$DMG")

cat > "$OUTDIR/release.json" <<JSON
{
  "format": 1,
  "version": "$VERSION",
  "build": $BUILD,
  "commit": "$COMMIT",
  "schemaGeneration": $GENERATION,
  "minimumSystemVersion": "$MIN_SYSTEM",
  "zip": { "name": "$ZIP", "size": $ZIP_SIZE, "sha256": "$ZIP_SHA" },
  "dmg": { "name": "$DMG", "size": $DMG_SIZE, "sha256": "$DMG_SHA" },
  "notesURL": "https://github.com/Rusl3n/tenfingers/releases/tag/v$VERSION"
}
JSON
# Проверка, что получился разбираемый JSON с теми же числами (plutil -extract разбирает JSON; -lint его не принимает)
[ "$(plutil -extract format raw "$OUTDIR/release.json")" = "1" ] \
    || { echo "release.json не разобрался как JSON" >&2; exit 1; }
[ "$(plutil -extract schemaGeneration raw "$OUTDIR/release.json")" = "$GENERATION" ] \
    || { echo "release.json: поколение схемы не совпало" >&2; exit 1; }
[ "$(plutil -extract dmg.sha256 raw "$OUTDIR/release.json")" = "$DMG_SHA" ] \
    || { echo "release.json: сумма .dmg не совпала" >&2; exit 1; }

(cd "$OUTDIR" && shasum -a 256 "$ZIP" "$DMG" > SHA256SUMS)

echo "Готово: $OUTDIR" >&2
ls -l "$OUTDIR" >&2
