#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

for fixture in examples/invalid.xml examples/invalid_base64.xml
do
    if [ ! -f "$fixture" ]; then
        echo "Отсутствует тестовый файл: $fixture"
        exit 1
    fi
done

for path in examples/missing.xml examples/invalid.xml \
    examples/invalid_base64.xml
do
    if output=$(./run.sh --vfs "$path" </dev/null 2>&1); then
        echo "Ошибка: неверная VFS принята: $path"
        exit 1
    fi

    printf '%s\n' "$output" | grep -Fq 'Ошибка загрузки VFS:'
done

echo "Ошибки загрузки VFS проверены"