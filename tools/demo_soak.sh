#!/usr/bin/env bash
# Demo soak (board D7): runs game/spike/memory_soak_probe.gd for N fresh seeds,
# each in its own headless Godot process and its own log, and prints each run's
# PROBE_SEED_DONE line and exit code. Never windowed, so it does not take the
# windowed slot. Usage: tools/demo_soak.sh [seeds=3] [days=5] [log_dir]
# Run from the repo (or worktree) root.
set -u
SEEDS="${1:-3}"
DAYS="${2:-5}"
LOG_DIR="${3:-tools/blender/out/demo_soak}"
GODOT="${GODOT:-/mnt/c/Users/chulf/AppData/Local/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe}"
PROJECT="$(wslpath -m "$(pwd)")/game"
mkdir -p "$LOG_DIR"

pids=()
for i in $(seq 1 "$SEEDS"); do
	log="$LOG_DIR/soak_$i.log"
	(
		timeout 3000 "$GODOT" --headless --audio-driver Dummy --path "$PROJECT" \
			-s res://spike/memory_soak_probe.gd -- --days="$DAYS" < /dev/null >"$log" 2>&1
		echo "exit $?" >>"$log"
	) &
	pids+=($!)
done
wait "${pids[@]}"

status=0
for i in $(seq 1 "$SEEDS"); do
	log="$LOG_DIR/soak_$i.log"
	echo "== $log"
	grep -E "^PROBE_SEED_DONE|^PROBE_INVALID|^PROBE_FAIL|^PROBE hung|^PROBE stuck_too_long|^exit " "$log"
	grep -q "^exit 0$" "$log" || status=1
done
exit "$status"
