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
