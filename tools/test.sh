#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TESTS_DIR="$REPO_ROOT/game/tests"
PY="/usr/bin/python3"

usage() {
	cat <<'EOF'
usage: tools/test.sh (--fast | --medium | --slow | --all) [--list] [--dry-run]
       tools/test.sh --list [--fast | --medium | --slow | --all]
       tools/test.sh -h | --help

Tiers:
  --fast      Pure unit/math/logic suites (default GODOT_TIMEOUT=300)
  --medium    Suites with SubViewport, await, TestWorld/rigs, or scenes (default GODOT_TIMEOUT=900)
  --slow      main.tscn, PassengerViews, save/load, tuning/balance/snapshot suites (default GODOT_TIMEOUT=2400)
  --all       Full gdUnit4 suite in bounded batches (default GODOT_TIMEOUT=3600)

Options:
  --list      Print tier counts and file lists without running Godot
  --dry-run   Print batched tools/godot.sh commands without running Godot
  -h, --help  Show this help message
EOF
}

TIER=""
LIST_MODE=0
DRY_RUN=0

while [ "$#" -gt 0 ]; do
	case "$1" in
		--fast|--medium|--slow|--all)
			flag_tier="${1#--}"
			if [ -n "$TIER" ] && [ "$TIER" != "$flag_tier" ]; then
				echo "error: --fast, --medium, --slow, and --all are mutually exclusive" >&2
				usage >&2
				exit 2
			fi
			TIER="$flag_tier"
			shift
			;;
		--list)
			LIST_MODE=1
			shift
			;;
		--dry-run)
			DRY_RUN=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "error: unknown option: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

if [ "$LIST_MODE" -eq 1 ]; then
	if [ -n "$TIER" ]; then
		exec "$PY" "$SCRIPT_DIR/test_tiers.py" list --tests-dir "$TESTS_DIR" --tier "$TIER"
	fi
	exec "$PY" "$SCRIPT_DIR/test_tiers.py" list --tests-dir "$TESTS_DIR"
fi

if [ -z "$TIER" ]; then
	echo "error: one of --fast, --medium, --slow, or --all is required" >&2
	usage >&2
	exit 2
fi

if [ -z "${GODOT_TIMEOUT:-}" ]; then
	case "$TIER" in
		fast) GODOT_TIMEOUT=300 ;;
		medium) GODOT_TIMEOUT=900 ;;
		slow) GODOT_TIMEOUT=2400 ;;
		all) GODOT_TIMEOUT=3600 ;;
	esac
fi
export GODOT_TIMEOUT

build_batch_args() {
	local batch_idx="$1"
	local line="$2"
	local -a paths=()
	IFS=$'\t' read -r -a paths <<< "$line"
	BATCH_ARGS=(
		--headless
		--path game
		--audio-driver Dummy
		--remote-debug tcp://127.0.0.1:0
		-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd
		--ignoreHeadlessMode
		-c
		-rd "res://reports/run_${RUN_ID}/b${batch_idx}"
		-rc 20
	)
	local p
	for p in "${paths[@]}"; do
		if [ -n "$p" ]; then
			BATCH_ARGS+=(-a "$p")
		fi
	done
}

compute_base_overhead() {
	# Length of Windows Godot executable path + fixed flags + worst-case -rd path + quoting buffer.
	local sample_prefix="\"C:/Users/chulf/AppData/Local/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe\" --headless --path game --audio-driver Dummy --remote-debug tcp://127.0.0.1:0 -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -c -rd \"res://reports/run_${RUN_ID}/b999\" -rc 20"
	local len="${#sample_prefix}"
	if [ "$len" -lt 512 ]; then
		len=512
	fi
	echo "$len"
}

if [ "$DRY_RUN" -eq 1 ]; then
	RUN_ID="${TIER}_$(date -u +%Y%m%dT%H%M%SZ)_dryrun"
	REPORTS_DIR="$REPO_ROOT/game/reports/run_${RUN_ID}"
	LOG_FILE="$REPO_ROOT/game/reports/run_${RUN_ID}.log"
	BASE_OVERHEAD="$(compute_base_overhead)"
	mapfile -t BATCH_LINES < <("$PY" "$SCRIPT_DIR/test_tiers.py" batches --tier "$TIER" --tests-dir "$TESTS_DIR" --base-overhead "$BASE_OVERHEAD")
	if [ "${#BATCH_LINES[@]}" -eq 0 ]; then
		echo "error: no test suites resolved for tier '$TIER'" >&2
		exit 1
	fi
	echo "RUN_ID=$RUN_ID GODOT_TIMEOUT=$GODOT_TIMEOUT LOG_FILE=$LOG_FILE REPORTS_DIR=$REPORTS_DIR"
	for i in "${!BATCH_LINES[@]}"; do
		build_batch_args "$i" "${BATCH_LINES[$i]}"
		printf '[batch %d/%d] %q' "$i" "${#BATCH_LINES[@]}" "$SCRIPT_DIR/godot.sh"
		printf ' %q' "${BATCH_ARGS[@]}"
		printf '\n'
	done
	exit 0
fi

mkdir -p "$REPO_ROOT/game/reports"
REPORTS_DIR="$(mktemp -d "${REPO_ROOT}/game/reports/run_${TIER}_$(date -u +%Y%m%dT%H%M%SZ)_XXXXXX")"
RUN_DIR_NAME="$(basename "$REPORTS_DIR")"
RUN_ID="${RUN_DIR_NAME#run_}"
LOG_FILE="$REPO_ROOT/game/reports/run_${RUN_ID}.log"
MANIFEST_FILE="$REPORTS_DIR/expected_batches.json"
BASE_OVERHEAD="$(compute_base_overhead)"

mapfile -t BATCH_LINES < <("$PY" "$SCRIPT_DIR/test_tiers.py" batches --tier "$TIER" --tests-dir "$TESTS_DIR" --base-overhead "$BASE_OVERHEAD" --manifest-out "$MANIFEST_FILE")

if [ "${#BATCH_LINES[@]}" -eq 0 ]; then
	echo "error: no test suites resolved for tier '$TIER'" >&2
	exit 1
fi

: > "$LOG_FILE"
cd "$REPO_ROOT"

START_TS="$("$PY" -c 'import time; print(f"{time.monotonic():.6f}")')"
BATCH_CODES=()
TOTAL_BATCHES="${#BATCH_LINES[@]}"

for i in "${!BATCH_LINES[@]}"; do
	build_batch_args "$i" "${BATCH_LINES[$i]}"
	{
		echo "=== Batch ${i}/${TOTAL_BATCHES} (tier=${TIER}, run_id=${RUN_ID}) ==="
	} >> "$LOG_FILE"
	rc=0
	"$SCRIPT_DIR/godot.sh" "${BATCH_ARGS[@]}" >> "$LOG_FILE" 2>&1 || rc=$?
	echo "=== Batch ${i}/${TOTAL_BATCHES} exit=${rc} ===" >> "$LOG_FILE"
	BATCH_CODES+=("$rc")
done

WALL_SECONDS="$("$PY" -c 'import sys, time; print(f"{max(0.0, time.monotonic() - float(sys.argv[1])):.3f}")' "$START_TS")"
CODES_CSV="$(IFS=,; echo "${BATCH_CODES[*]}")"

exec "$PY" "$SCRIPT_DIR/test_tiers.py" summarize \
	--tier "$TIER" \
	--run-id "$RUN_ID" \
	--reports-dir "$REPORTS_DIR" \
	--log-file "$LOG_FILE" \
	--batch-codes "$CODES_CSV" \
	--wall-seconds "$WALL_SECONDS" \
	--expected-batches "$MANIFEST_FILE"
