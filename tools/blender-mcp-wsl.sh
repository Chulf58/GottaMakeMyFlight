#!/usr/bin/env bash
set -euo pipefail

HOST="$(ip route | awk '/^default/ {print $3; exit}')"
[ -n "$HOST" ] || { echo "blender-mcp-wsl: no default route, cannot find the Windows host" >&2; exit 1; }
export BLENDER_MCP_HOST="${BLENDER_MCP_HOST:-$HOST}"

exec /home/chulf/.local/bin/uv --directory /mnt/c/Users/chulf/Tools/blender_mcp/mcp run blender-mcp "$@"
