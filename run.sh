#!/bin/sh
set -eu
cd "$(dirname "$0")"
xcrun swift src/main.swift "$@"