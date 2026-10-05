#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

output=$(printf '%s\n' 'ls "two words"' 'cd folder' 'ls a b' 'unknown' 'cd "unfinished' 'exit' | ./run.sh)

printf '%s\n' "$output" | grep -Fq 'ls: ["two words"]'
printf '%s\n' "$output" | grep -Fq 'cd: ["folder"]'
printf '%s\n' "$output" | grep -Fq 'неверные аргументы команды ls'
printf '%s\n' "$output" | grep -Fq 'неизвестная команда unknown'
printf '%s\n' "$output" | grep -Fq 'незакрытая кавычка'

echo "Проверки первого этапа пройдены"