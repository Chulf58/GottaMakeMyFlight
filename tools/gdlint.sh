#!/usr/bin/env bash
set -euo pipefail

BIN="/mnt/c/Users/chulf/.local/bin/gdlint.exe"
TIMEOUT="${GDTOOLKIT_TIMEOUT:-60}"

if [ "$#" -eq 0 ]; then
	echo "usage: tools/gdlint.sh <path> [path ...]" >&2
	exit 2
fi

if [ ! -x "$BIN" ]; then
	echo "gdlint.sh: binary not found or not executable: $BIN" >&2
	exit 127
fi

rc=0
timeout "$TIMEOUT" "$BIN" "$@" < /dev/null || rc=$?
if [ "$rc" -eq 124 ]; then
	echo "gdlint.sh: timed out after ${TIMEOUT}s running $BIN" >&2
	exit 124
fi
exit "$rc"
