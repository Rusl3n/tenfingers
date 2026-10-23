#!/bin/bash
# Готовит words-ru.txt и words-en.txt из частотных списков hermitdave/FrequencyWords (CC BY-SA 4.0).
# Запускается один раз; результат коммитится в репозиторий.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=Sources/TypingCore/Resources
TMP=$(mktemp -d)
BASE=https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018

curl -fsSL "$BASE/ru/ru_50k.txt" -o "$TMP/ru.txt"
curl -fsSL "$BASE/en/en_50k.txt" -o "$TMP/en.txt"

# Первая колонка — слово. Оставляем только буквы алфавита, длина 2–12, без дублей, первые 20000.
awk '{print $1}' "$TMP/ru.txt" | LC_ALL=en_US.UTF-8 grep -E '^[а-яё]{2,12}$' \
    | awk '!seen[$0]++' | awk 'NR<=20000' > "$OUT/words-ru.txt"
awk '{print $1}' "$TMP/en.txt" | LC_ALL=C grep -E '^[a-z]{2,12}$' \
    | awk '!seen[$0]++' | awk 'NR<=20000' > "$OUT/words-en.txt"

rm -rf "$TMP"
wc -l "$OUT"/words-*.txt
