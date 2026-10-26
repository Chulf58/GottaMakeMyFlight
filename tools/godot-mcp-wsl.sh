#!/usr/bin/env bash
# Launch godot-mcp-runtime (npm, MIT) from WSL on WINDOWS node, not Linux node.
#
# Why Windows node: the server spawns Godot with `--path <resolve(projectPath)>`
# and its runtime bridge dials 127.0.0.1. Under Linux node the path would be a
# /mnt/c/... path the Windows Godot exe cannot read, and WSL2 in NAT mode
# cannot reach the Windows loopback. Windows node fixes both.
#
# ⚠ Tool calls must pass the WINDOWS project path: "C:/Users/chulf/Gotta-make-my-flight/game".
# ⚠ The bridge writes game/.mcp/ and creates game/.gitignore if absent; neither
#   is removed on stop_project. Screenshots land in game/.mcp/godot-runtime/screenshots/.
# ⚠ A running game holds the project's single windowed Godot slot.
set -euo pipefail

NODE_EXE="/mnt/c/Program Files/nodejs/node.exe"
NPX_CLI='C:\Program Files\nodejs\node_modules\npm\bin\npx-cli.js'
[ -x "$NODE_EXE" ] || { echo "godot-mcp-wsl: Windows node not found at $NODE_EXE" >&2; exit 1; }

export GODOT_PATH="${GODOT_PATH:-C:/Users/chulf/AppData/Local/Programs/Godot/Godot_v4.7.2-stable_win64.exe}"
# WSLENV carries these variables across into the Windows process.
# GODOT_MCP_DISABLE_ELICITATION is forwarded only when the caller set it: the
# Codex entry in ~/.codex/config.toml sets it (user ruling 2026-09-23, "Set it
# for Codex"), the Claude Code entry in .mcp.json does not.
# GMMF_PLAYTEST opts every MCP-launched game into the dev-only playtest hook
# (game/debug/playtest_hook.gd; decision ai-playtester-a-dev-only-debug-hook-
# event-log-state-queries-a). The user's own editor runs do not set it.
export GMMF_PLAYTEST="${GMMF_PLAYTEST:-1}"
export WSLENV="${WSLENV:+$WSLENV:}GODOT_PATH:GMMF_PLAYTEST${DEBUG:+:DEBUG}${GODOT_MCP_DISABLE_ELICITATION:+:GODOT_MCP_DISABLE_ELICITATION}"

# A Windows process needs a Windows-visible cwd; the repo root is one.
cd "/mnt/c/Users/chulf/Gotta-make-my-flight"
exec "$NODE_EXE" "$NPX_CLI" -y godot-mcp-runtime@3.8.1 "$@"
