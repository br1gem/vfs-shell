#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

minimal=$(printf 'vfs-info\nexit\n' | ./run.sh --vfs examples/minimal.xml)
printf '%s\n' "$minimal" | grep -Fq 'VFS загружена: examples/minimal.xml'
printf '%s\n' "$minimal" | grep -Fq ':~$ /'

multiple=$(./run.sh --vfs examples/multiple.xml \
    --script examples/startup_vfs.txt)
printf '%s\n' "$multiple" | grep -Fq '/hello.txt (5 байт)'
printf '%s\n' "$multiple" | grep -Fq '/docs/guide.txt (5 байт)'
printf '%s\n' "$multiple" | grep -Fq 'ls: ["two words"]'
printf '%s\n' "$multiple" | grep -Fq 'cd: ["docs"]'

deep=$(./run.sh --config examples/config.ini \
    --script examples/startup_vfs.txt)
printf '%s\n' "$deep" | grep -Fq '/docs/archive/old/note.txt (4 байт)'

echo "Варианты VFS проверены"