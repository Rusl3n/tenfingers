#!/usr/bin/env bash
# Проверка стоп-листа: названия чужих продуктов не должны встречаться в отслеживаемых файлах.
# Стоп-лист — scripts/forbidden-names.txt (по строке на название, регистр не важен, пустые строки игнорируются).
# Сам стоп-лист не проверяется. Код выхода: 0 — чисто, 1 — найдено, 2 — сбой окружения.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
LIST="scripts/forbidden-names.txt"

# Регистр кириллицы grep -i учитывает только в UTF-8-локали (в локали C «Соло» и «соло» — разные слова),
# а набор локалей зависит от системы. Берём первую из доступных, где «СОЛО» находится по «соло»;
# если такой нет — падаем, чтобы проверка не пропускала названия молча.
GREP_LOCALE=""
for candidate in en_US.UTF-8 C.UTF-8 ru_RU.UTF-8; do
  if [ "$(printf 'СОЛО\n' | LC_ALL="$candidate" grep -c -i -F 'соло' 2>/dev/null || true)" = "1" ]; then
    GREP_LOCALE="$candidate"
    break
  fi
done
if [ -z "$GREP_LOCALE" ]; then
  echo "check-names: нет UTF-8-локали, в которой grep -i игнорирует регистр кириллицы" >&2
  exit 2
fi
export LC_ALL="$GREP_LOCALE"

# Пустые строки стоп-листа выкидываем: пустой шаблон совпал бы с каждой строкой.
patterns="$(mktemp)"
trap 'rm -f "$patterns"' EXIT
grep -v '^[[:space:]]*$' "$LIST" > "$patterns" || true
if [ ! -s "$patterns" ]; then
  echo "check-names: стоп-лист пуст" >&2
  exit 2
fi

# Список файлов берём заранее: сбой `git ls-files` внутри `< <(...)` не виден `set -e` и дал бы «чисто».
files="$(mktemp)"
trap 'rm -f "$patterns" "$files"' EXIT
git -c core.quotepath=false ls-files > "$files"

# -I пропускает двоичные файлы (картинки, иконки); -H печатает имя файла, -n — номер строки.
# Код grep: 0 — найдено, 1 — не найдено, больше — сбой чтения (его не выдаём за «чисто»).
found=0
while IFS= read -r file; do
  [ "$file" = "$LIST" ] && continue
  [ -f "$file" ] || continue
  status=0
  grep -H -n -I -i -F -f "$patterns" -- "$file" || status=$?
  case "$status" in
    0) found=1 ;;
    1) ;;
    *) echo "check-names: grep не смог прочитать $file (код $status)" >&2; exit 2 ;;
  esac
done < "$files"

if [ "$found" -ne 0 ]; then
  echo "check-names: найдены названия из $LIST (замените нейтральным описанием)" >&2
  exit 1
fi
echo "check-names: названий из стоп-листа нет"
