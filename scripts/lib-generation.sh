#!/bin/bash
# Общая функция для make-bundle.sh и build-app.sh (подключается через `source`, сама ничего не запускает).
# schema_generation печатает SchemaGeneration.current из исходников — число — или возвращает код 1.
# Корень репозитория берётся от расположения этого файла, текущая папка не важна.

# Путь считается при подключении, пока относительные пути ещё верны (после `cd` в скрипте они бы сломались)
TF_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

schema_generation() {
    local file value
    file="$TF_REPO_ROOT/Sources/TenFingers/Persistence/SchemaGeneration.swift"
    value=$(sed -n 's/^[[:space:]]*static let current = \([0-9][0-9]*\).*$/\1/p' "$file" 2>/dev/null | head -n1) || true
    if [ -z "$value" ]; then
        echo "Не удалось прочитать SchemaGeneration.current из Sources/TenFingers/Persistence/SchemaGeneration.swift" >&2
        return 1
    fi
    echo "$value"
}

# Проверка поколения одной базы (спецификация §10.3): маркер <папка>/TenFingers.store.generation новее сборки —
# печатает отказ в stderr и возвращает 1. Маркера нет или он не читается — 0 (приложение разберётся при открытии).
# $1 — папка базы, $2 — SchemaGeneration.current сборки. Каждая база проверяется отдельно: корневая и профилей.
check_store_generation() {
    local dir="$1" build="$2" marker stored
    marker="$dir/TenFingers.store.generation"
    if [ -f "$marker" ] && [ -r "$marker" ]; then
        stored=$(tr -d '[:space:]' < "$marker" || true)
        if [[ "$stored" =~ ^[0-9]{1,9}$ ]] && [ "$((10#$stored))" -gt "$build" ]; then
            echo "Установка отменена: база прогресса записана более новой версией приложения." >&2
            echo "  Поколение схемы базы:   $((10#$stored)) ($marker)" >&2
            echo "  Поколение схемы сборки: $build (SchemaGeneration.current)" >&2
            echo "Эта сборка не откроет базу. Соберите ветку с поколением не ниже $((10#$stored))." >&2
            echo "Установленное приложение и база не тронуты." >&2
            return 1
        fi
    fi
    return 0
}

# Папки баз неосновных профилей: <папка приложения>/Profiles/<uuid> (только существующие папки с базой или маркером).
profile_store_dirs() {
    local root="$1" dir
    for dir in "$root"/Profiles/*/; do
        [ -d "$dir" ] || continue
        dir="${dir%/}"
        if [ -f "$dir/TenFingers.store" ] || [ -f "$dir/TenFingers.store.generation" ]; then
            printf '%s\n' "$dir"
        fi
    done
}
