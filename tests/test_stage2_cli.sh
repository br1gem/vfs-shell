#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

output=$(./run.sh --vfs cli.xml --script examples/startup_ok.txt)

printf '%s\n' "$output" | grep -Fq 'VFS: cli.xml'
printf '%s\n' "$output" | grep -Fq 'Стартовый скрипт: examples/startup_ok.txt'
printf '%s\n' "$output" | grep -Fq 'ls: ["two words"]'
printf '%s\n' "$output" | grep -Fq 'cd: ["folder"]'

if ./run.sh --unknown value >/dev/null 2>&1; then
    echo "Ошибка: неизвестный параметр был принят"
    exit 1
fi

if ./run.sh --vfs --script >/dev/null 2>&1; then
    echo "Ошибка: параметр без пути был принят"
    exit 1
fi

echo "Проверки параметров командной строки пройдены"