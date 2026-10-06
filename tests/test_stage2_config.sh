#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

output=$(./run.sh --config examples/config.ini \
    --vfs examples/minimal.xml --script examples/startup_ok.txt)

printf '%s\n' "$output" | grep -Fq 'VFS: examples/minimal.xml'
printf '%s\n' "$output" | grep -Fq 'Стартовый скрипт: examples/startup_ok.txt'

if output=$(./run.sh --config examples/config.ini); then
    echo "Ошибка: скрипт с неизвестной командой завершился успешно"
    exit 1
fi

printf '%s\n' "$output" | grep -Fq 'Ошибка исполнения стартового скрипта: строка 3'

if printf '%s\n' "$output" | grep -Fq 'ls after-error'; then
    echo "Ошибка: команда после сбоя была выполнена"
    exit 1
fi

if ./run.sh --config examples/missing.ini >/dev/null 2>&1; then
    echo "Ошибка: отсутствующий INI-файл был принят"
    exit 1
fi

echo "Проверки INI и стартового скрипта пройдены"