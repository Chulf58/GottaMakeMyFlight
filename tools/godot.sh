#!/usr/bin/env bash
set -euo pipefail

BIN="/mnt/c/Users/chulf/AppData/Local/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe"
TIMEOUT="${GODOT_TIMEOUT:-180}"

if [ "$#" -eq 0 ]; then
	echo "usage: tools/godot.sh <godot args ...>" >&2
	exit 2
fi

if [ ! -x "$BIN" ]; then
	echo "godot.sh: binary not found or not executable: $BIN" >&2
	exit 127
fi

rc=0
timeout "$TIMEOUT" "$BIN" "$@" < /dev/null || rc=$?
if [ "$rc" -eq 124 ]; then
	echo "godot.sh: timed out after ${TIMEOUT}s running $BIN" >&2
	exit 124
fi
exit "$rc"
