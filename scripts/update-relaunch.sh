#!/bin/sh
# Помощник перезапуска после обновления (спецификация фазы 7 §5.3 шаг 7, решение 7).
# Запускает приложение: /usr/bin/nohup /bin/sh <копия скрипта> <pid> <путь .app>
# Ждёт завершения старого процесса (до 30 с, шаг 0,2 с) и открывает новый бандл. Если старый процесс так и не
# завершился, новый не открывается: база не должна быть открыта двумя процессами. В конце удаляет свою копию.
PID="$1"
APP="$2"
SELF="$0"
if [ -z "$PID" ] || [ -z "$APP" ]; then
    echo "usage: $0 <pid> <app path>" >&2
    exit 2
fi

i=0
while kill -0 "$PID" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 150 ]; then
        rm -f "$SELF"
        rmdir "$(dirname "$SELF")" 2>/dev/null
        exit 1
    fi
    sleep 0.2
done

/usr/bin/open -n "$APP"
rm -f "$SELF"
rmdir "$(dirname "$SELF")" 2>/dev/null
exit 0
