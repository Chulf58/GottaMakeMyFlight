#!/usr/bin/env bash
# Build and verify the "Windows Desktop" 1.0 release export (board f929fa07, decision c5664a34).
# Usage: tools/build_release.sh [--skip-soak] [--skip-tests] [--zip] [--check-only] [--out-dir <dir>]
# Run from the repo or worktree root.
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: tools/build_release.sh [--skip-soak] [--skip-tests] [--zip] [--check-only] [--out-dir <dir>]
EOF
}

SKIP_SOAK=0
SKIP_TESTS=0
MAKE_ZIP=0
CHECK_ONLY=0
OUT_DIR="tools/blender/out/release_win64"

while [ "$#" -gt 0 ]; do
	case "$1" in
	--skip-soak)
		SKIP_SOAK=1
		shift
		;;
	--skip-tests)
		SKIP_TESTS=1
		shift
		;;
	--zip)
		MAKE_ZIP=1
		shift
		;;
	--check-only)
		CHECK_ONLY=1
		shift
		;;
	--out-dir)
		if [ "$#" -lt 2 ] || [ -z "$2" ]; then
			echo "build_release.sh: --out-dir requires a directory argument" >&2
			exit 2
		fi
		OUT_DIR="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "build_release.sh: unknown option: $1" >&2
		usage >&2
		exit 2
		;;
	esac
done

ROOT="$(pwd)"
if [ ! -f "$ROOT/game/project.godot" ] || [ ! -f "$ROOT/game/export_presets.cfg" ]; then
	echo "build_release.sh: run from the repo or worktree root (missing game/project.godot or game/export_presets.cfg)" >&2
	exit 2
fi

GODOT="${GODOT:-/mnt/c/Users/chulf/AppData/Local/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe}"

# Step 1: Version parity check
VERSION="$(
	python3 - "$ROOT/game/project.godot" "$ROOT/game/export_presets.cfg" <<'PY'
import re
import sys

project_path, presets_path = sys.argv[1], sys.argv[2]

def parse_godot_cfg(path):
    sections = {}
    cur = None
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith(";") or line.startswith("#"):
                continue
            if line.startswith("[") and line.endswith("]"):
                cur = line[1:-1].strip()
                sections.setdefault(cur, {})
                continue
            if "=" in line and cur is not None:
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip()
                if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
                    v = v[1:-1]
                sections[cur][k] = v
    return sections

proj = parse_godot_cfg(project_path)
version = proj.get("application", {}).get("config/version", "")
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    sys.stderr.write(f"ERROR: invalid or missing config/version in {project_path}: {version!r}\n")
    sys.exit(1)

expected_win_ver = f"{version}.0"
presets = parse_godot_cfg(presets_path)

errors = []
for sec in ("preset.0.options", "preset.1.options"):
    opts = presets.get(sec)
    if opts is None:
        errors.append(f"missing [{sec}] in {presets_path}")
        continue
    for key in ("application/file_version", "application/product_version"):
        actual = opts.get(key, "")
        if actual != expected_win_ver:
            errors.append(f"[{sec}] {key}={actual!r} != expected {expected_win_ver!r}")

p0 = presets.get("preset.0")
if p0 is None:
    errors.append(f"missing [preset.0] in {presets_path}")
else:
    if p0.get("name") != "Windows Desktop":
        errors.append(f"[preset.0] name={p0.get('name')!r} != 'Windows Desktop'")
    if p0.get("custom_features") != "":
        errors.append(f"[preset.0] custom_features={p0.get('custom_features')!r} != ''")

if errors:
    for err in errors:
        sys.stderr.write(f"ERROR: {err}\n")
    sys.exit(1)

print(version)
PY
)"
echo "[step 1] Version parity OK: project=${VERSION}, presets=${VERSION}.0, preset.0='Windows Desktop' (custom_features=)"

if [ "$CHECK_ONLY" -eq 1 ]; then
	exit 0
fi

if [ ! -x "$GODOT" ]; then
	echo "build_release.sh: Godot binary not found or not executable: $GODOT" >&2
	exit 127
fi

PROJECT="$(wslpath -m "$ROOT")/game"

if [ ! -f "$ROOT/game/.godot/global_script_class_cache.cfg" ]; then
	echo "[init] Missing game/.godot/global_script_class_cache.cfg; running headless --import..."
	timeout 180 "$GODOT" --headless --audio-driver Dummy --path "$PROJECT" --import < /dev/null
fi

TMP_LOG=""
cleanup() {
	if [ -n "$TMP_LOG" ] && [ -f "$TMP_LOG" ]; then
		rm -f "$TMP_LOG"
	fi
}
trap cleanup EXIT

# Step 2: Fast pre-export gate (gdUnit4 Stage 2/3 release suites)
if [ "$SKIP_TESTS" -eq 0 ]; then
	STEP2_SUITES=(
		"res://tests/core/test_achievements.gd"
		"res://tests/core/test_sandbox_mode.gd"
		"res://tests/test_airport_certification.gd"
		"res://tests/rating/test_airport_awards.gd"
		"res://tests/ui/test_locale_settings.gd"
	)
	echo "[step 2] Running ${#STEP2_SUITES[@]} Stage 2/3 gdUnit4 suites..."
	SUITE_ARGS=()
	for s in "${STEP2_SUITES[@]}"; do
		SUITE_ARGS+=(-a "$s")
	done
	TMP_LOG="$(mktemp)"
	rc=0
	timeout 180 "$GODOT" --headless --audio-driver Dummy --path "$PROJECT" \
		--remote-debug tcp://127.0.0.1:0 \
		-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
		"${SUITE_ARGS[@]}" -c --ignoreHeadlessMode < /dev/null 2>&1 | tee "$TMP_LOG" || rc=${PIPESTATUS[0]}
	if [ "$rc" -ne 0 ]; then
		echo "ERROR: Stage 2/3 gdUnit4 gate failed with exit code $rc" >&2
		exit "$rc"
	fi
	python3 - "$TMP_LOG" <<'PY'
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as f:
    text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", f.read())

if not re.search(r"\b0 errors\b", text) or not re.search(r"\b0 failures\b", text):
    sys.stderr.write("ERROR: gdUnit4 output did not confirm '0 errors' and '0 failures'\n")
    sys.exit(1)
PY
	echo "[step 2] Release gate tests OK (0 errors, 0 failures)"
else
	echo "[step 2] Skipped (--skip-tests)"
fi

# Step 3: Soak gate (2 seeds x 10 days covering Year-1 Annual Awards rollover)
if [ "$SKIP_SOAK" -eq 0 ]; then
	echo "[step 3] Running tools/demo_soak.sh 2 10..."
	bash "$ROOT/tools/demo_soak.sh" 2 10
	echo "[step 3] Soak gate OK"
else
	echo "[step 3] Skipped (--skip-soak)"
fi

# Step 4: Clean staging export
if [ -z "$OUT_DIR" ]; then
	echo "ERROR: refusing empty --out-dir" >&2
	exit 2
fi
ABS_OUT_DIR="$(
	python3 - "$OUT_DIR" "$ROOT" "${HOME:-}" <<'PY'
import os
import sys

out_arg, root_arg, home_arg = sys.argv[1], sys.argv[2], sys.argv[3]
out_real = os.path.realpath(out_arg)
root_real = os.path.realpath(root_arg)
game_real = os.path.realpath(os.path.join(root_real, "game"))
forbidden = {"/", root_real, game_real}
if home_arg:
    forbidden.add(os.path.realpath(home_arg))

if out_real in forbidden:
    sys.stderr.write(f"ERROR: refusing unsafe --out-dir: {out_arg!r} (resolved: {out_real!r})\n")
    sys.exit(2)

rel_to_out = os.path.relpath(root_real, out_real)
if rel_to_out == "." or not rel_to_out.startswith(".."):
    sys.stderr.write(
        f"ERROR: refusing --out-dir ancestor of repo root: {out_arg!r} (resolved: {out_real!r})\n"
    )
    sys.exit(2)

print(out_real)
PY
)"
echo "[step 4] Exporting 'Windows Desktop' to $ABS_OUT_DIR..."
rm -rf "$ABS_OUT_DIR"
mkdir -p "$ABS_OUT_DIR"
OUT_EXE="$ABS_OUT_DIR/GottaMakeMyFlight.exe"
WIN_OUT_EXE="$(wslpath -m "$ABS_OUT_DIR")/GottaMakeMyFlight.exe"

rc=0
timeout 300 "$GODOT" --headless --audio-driver Dummy --path "$PROJECT" \
	--export-release "Windows Desktop" "$WIN_OUT_EXE" < /dev/null || rc=$?
if [ "$rc" -ne 0 ]; then
	echo "ERROR: Godot export-release failed with exit code $rc" >&2
	exit "$rc"
fi

if [ ! -f "$OUT_EXE" ]; then
	echo "ERROR: exported exe missing: $OUT_EXE" >&2
	exit 1
fi
EXE_SIZE="$(stat -c%s "$OUT_EXE")"
if [ "$EXE_SIZE" -le 10485760 ]; then
	echo "ERROR: exported exe too small ($EXE_SIZE bytes <= 10485760): $OUT_EXE" >&2
	exit 1
fi
echo "[step 4] Export OK: $OUT_EXE ($EXE_SIZE bytes)"

# Step 5: Embedded PCK audit
echo "[step 5] Auditing embedded PCK in $OUT_EXE..."
PCK_COUNT="$(
	python3 - "$OUT_EXE" <<'PY'
import os
import re
import struct
import sys

exe_path = sys.argv[1]
file_size = os.path.getsize(exe_path)

with open(exe_path, "rb") as f:
    if file_size < 16:
        sys.stderr.write("ERROR: file too small to hold embedded PCK\n")
        sys.exit(1)
    f.seek(file_size - 12)
    pck_size, trailer_magic = struct.unpack("<Q4s", f.read(12))
    if trailer_magic != b"GDPC":
        sys.stderr.write(f"ERROR: missing trailing GDPC magic (got {trailer_magic!r})\n")
        sys.exit(1)

    pck_start = file_size - 12 - pck_size
    if pck_start < 0:
        sys.stderr.write(f"ERROR: invalid pck_size {pck_size} for file_size {file_size}\n")
        sys.exit(1)
    f.seek(pck_start)
    hdr_magic = f.read(4)
    if hdr_magic != b"GDPC":
        sys.stderr.write(f"ERROR: missing header GDPC magic at offset {pck_start} (got {hdr_magic!r})\n")
        sys.exit(1)

    pack_version, ver_major, ver_minor, ver_patch = struct.unpack("<4I", f.read(16))
    pack_flags, file_base = struct.unpack("<IQ", f.read(12))
    if pack_version in (3, 4):
        dir_offset = struct.unpack("<Q", f.read(8))[0]
        f.seek(pck_start + dir_offset)
    elif pack_version == 2:
        f.seek(64, os.SEEK_CUR)
    else:
        sys.stderr.write(f"ERROR: unsupported PCK pack_version {pack_version}\n")
        sys.exit(1)

    file_count = struct.unpack("<I", f.read(4))[0]
    if file_count == 0:
        sys.stderr.write("ERROR: PCK contains 0 files\n")
        sys.exit(1)

    paths = []
    for _ in range(file_count):
        path_len = struct.unpack("<I", f.read(4))[0]
        raw_path = f.read(path_len)
        entry_path = raw_path.split(b"\x00", 1)[0].decode("utf-8")
        if not entry_path.startswith("res://"):
            entry_path = "res://" + entry_path.lstrip("/")
        _offset, _size = struct.unpack("<QQ", f.read(16))
        _md5 = f.read(16)
        _flags = struct.unpack("<I", f.read(4))[0]
        paths.append(entry_path)

path_set = set(paths)

required_scripts = {
    "achievements": ("res://core/achievements.gdc", "res://core/achievements.gd"),
    "steam_bridge": ("res://core/steam_bridge.gdc", "res://core/steam_bridge.gd"),
    "game_rules": ("res://core/game_rules.gdc", "res://core/game_rules.gd"),
    "airport_certification": ("res://rating/airport_certification.gdc", "res://rating/airport_certification.gd"),
    "airport_awards": ("res://rating/airport_awards.gdc", "res://rating/airport_awards.gd"),
}
missing_scripts = [
    name for name, candidates in required_scripts.items()
    if not any(c in path_set for c in candidates)
]
if missing_scripts:
    sys.stderr.write(f"ERROR: missing required 1.0 scripts in PCK: {', '.join(missing_scripts)}\n")
    sys.exit(1)

required_locales = ("en", "zh_CN", "ja", "ko", "de", "fr", "es", "pt_BR", "ru", "pl")
missing_locales = []
for code in required_locales:
    imported_pat = re.compile(rf"^res://\.godot/imported/{re.escape(code)}\.po-[0-9a-f]+\.translation$")
    direct_paths = {f"res://locale/{code}.po", f"res://locale/{code}.translation"}
    if not any(imported_pat.match(p) or p in direct_paths for p in paths):
        missing_locales.append(code)
if missing_locales:
    sys.stderr.write(f"ERROR: missing required Core Steam 10 locale translations in PCK: {', '.join(missing_locales)}\n")
    sys.exit(1)

excluded_prefixes = ("res://spike/", "res://tests/", "res://addons/gdUnit4/")
excluded_suffixes = ("_probe.gd", "_probe.gdc", "_plates_probe.gd", "_plates_probe.gdc")
bad = [
    p for p in paths
    if p.startswith(excluded_prefixes) or p.endswith(excluded_suffixes)
]
if bad:
    sys.stderr.write(f"ERROR: excluded paths found in embedded PCK ({len(bad)}):\n")
    for p in bad[:20]:
        sys.stderr.write(f"  {p}\n")
    sys.exit(1)

sys.stderr.write(
    f"[step 5] PCK audit OK: format=v{pack_version} (Godot {ver_major}.{ver_minor}.{ver_patch}), "
    f"files={len(paths)}, scripts={len(required_scripts)}/5, locales={len(required_locales)}/10, excluded=0\n"
)
print(len(paths))
PY
)"

# Step 6: Manifest & optional zip
SAVE_VERSION="$(
	python3 - "$ROOT/game/core/save_game.gd" <<'PY'
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    text = f.read()
m = re.search(r"^\s*const\s+SAVE_VERSION\s*:=\s*(\d+)\s*$", text, re.MULTILINE)
if not m:
    sys.stderr.write("ERROR: could not parse SAVE_VERSION from save_game.gd\n")
    sys.exit(1)
print(m.group(1))
PY
)"

GIT_HEAD="$(git -C "$ROOT" rev-parse HEAD)"
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
	GIT_DIRTY="true"
else
	GIT_DIRTY="false"
fi
BUILT_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

MANIFEST="$ABS_OUT_DIR/build_manifest.txt"
cat >"$MANIFEST" <<EOF
version=$VERSION
save_version=$SAVE_VERSION
git_head=$GIT_HEAD
git_dirty=$GIT_DIRTY
preset=Windows Desktop
features=full
pck_file_count=$PCK_COUNT
built_at_utc=$BUILT_UTC
EOF
echo "[step 6] Wrote $MANIFEST"

if [ "$MAKE_ZIP" -eq 1 ]; then
	mkdir -p "$ROOT/tools/blender/out"
	ZIP_PATH="$ROOT/tools/blender/out/GottaMakeMyFlight-${VERSION}-win64.zip"
	python3 - "$ABS_OUT_DIR" "$ZIP_PATH" <<'PY'
import os
import sys
import zipfile

src_dir, zip_path = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for root, _dirs, files in os.walk(src_dir):
        for name in sorted(files):
            full = os.path.join(root, name)
            rel = os.path.relpath(full, src_dir)
            zf.write(full, arcname=rel)
print(f"wrote {zip_path} ({os.path.getsize(zip_path)} bytes)")
PY
	echo "[step 6] Created zip: $ZIP_PATH"
fi
