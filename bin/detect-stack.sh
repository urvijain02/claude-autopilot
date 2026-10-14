#!/usr/bin/env bash
# Detect a repo's stack. Prints: dotnet | node | unknown
# Generic: lives once at ${CLAUDE_PLUGIN_ROOT}/bin and is pointed at any repo.
# Usage: detect-stack.sh <repo-path>
set -euo pipefail
repo="${1:-.}"
repo="${repo/#\~/$HOME}"

# No pipe into grep: grep would exit on the first match, find would die of SIGPIPE, and
# under `set -o pipefail` the whole condition then reads false — so a repo with enough
# csproj files to fill the pipe buffer was detected as `unknown`.
csproj="$(find "$repo" -maxdepth 3 -name '*.csproj' -print -quit 2>/dev/null || true)"
if ls "$repo"/*.sln >/dev/null 2>&1 || ls "$repo"/*.slnx >/dev/null 2>&1 || [ -n "$csproj" ]; then
  echo "dotnet"
elif [ -f "$repo/package.json" ]; then
  echo "node"
else
  echo "unknown"
fi
