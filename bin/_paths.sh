#!/usr/bin/env bash
# Single source of truth for the two directories a run needs, so the gate
# scripts, provisioning, cleanup, mark-phase and the usage hook can never
# disagree about where things live.
#
# Resolution order for each:
#   1. $AUTOPILOT_STATE_DIR / $AUTOPILOT_WORKSPACE_DIR
#   2. "state_root" / "workspace_root" in ~/.claude/autopilot/config.json
#   3. ~/.claude/autopilot/state  /  ~/.claude/autopilot/work
#
# Sourced, not executed.

AUTOPILOT_HOME="${AUTOPILOT_HOME:-$HOME/.claude/autopilot}"
AUTOPILOT_HOME="$(printf '%s' "$AUTOPILOT_HOME" | tr '\\' '/')"

_expand_tilde() { printf '%s' "${1/#\~/$HOME}"; }

# A resolved root is interpolated into the command string run_in_repo passes to eval, so a
# shell-active character in it would be reparsed as syntax. Spaces are legal and expected.
# $1 = what it is (for the message), $2 = the value.
_safe_path() {
  local what="$1" val="$2" c
  for c in '"' "'" '\' '$' '`' ';' '&' '|' '<' '>' '(' ')' '*' '?'; do
    case "$val" in
      *"$c"*)
        echo "invalid $what: '$val' contains '$c' — a path used by the gates must not carry shell metacharacters" >&2
        return 1 ;;
    esac
  done
  case "$val" in
    *$'\n'*) echo "invalid $what: '$val' contains a newline" >&2; return 1 ;;
  esac
  return 0
}

# Ticket keys and labels arrive from the command line and end up inside `rm -rf` targets,
# where a `..` or a slash would delete a parent instead of the intended directory.
_safe_component() {
  case "${2:-}" in
    ""|.|..|*/*)
      echo "invalid $1: '${2:-}' — must be a plain name" >&2; return 1 ;;
    *[!A-Za-z0-9._-]*)
      echo "invalid $1: '$2' — letters, digits, dot, dash and underscore only" >&2; return 1 ;;
  esac
  return 0
}

# python3 is probed by running it: a Mac without Command Line Tools ships a stub that
# satisfies `command -v` and fails on exec. Without either parser only a plain one-line
# `"key": "value"` can be read safely, and a misread here would send gate output to a
# directory the orchestrator never reads — so an unreadable value stops the run.
# Centralized JSON Engine Resolver: checks jq -> python3 -> python -> node -> none.
# Probed securely across POSIX, Windows, and macOS environments.
resolve_json_engine() {
  if [ -n "${AUTOPILOT_JSON_ENGINE:-}" ]; then
    case "$AUTOPILOT_JSON_ENGINE" in
      jq|python3|python|node|node.exe)
        printf '%s' "$AUTOPILOT_JSON_ENGINE"
        return 0
        ;;
      *)
        echo "Warning: Unsupported AUTOPILOT_JSON_ENGINE='$AUTOPILOT_JSON_ENGINE'; falling back to auto-detection." >&2
        ;;
    esac
  fi
  if command -v jq >/dev/null 2>&1; then
    printf 'jq'
  elif command -v python3 >/dev/null 2>&1 && python3 -c '' >/dev/null 2>&1; then
    printf 'python3'
  elif command -v python >/dev/null 2>&1 && python -c '' >/dev/null 2>&1; then
    printf 'python'
  elif command -v node >/dev/null 2>&1; then
    printf 'node'
  elif command -v node.exe >/dev/null 2>&1; then
    printf 'node.exe'
  else
    printf 'none'
  fi
}

_have_python() {
  local eng
  eng="$(resolve_json_engine)"
  [ "$eng" = "python3" ] || [ "$eng" = "python" ]
}

_config_value() {
  local cfg="$AUTOPILOT_HOME/config.json" key="$1"
  [ -f "$cfg" ] || return 0

  local engine
  engine="$(resolve_json_engine)"
  case "$engine" in
    jq)
      jq -r --arg k "$key" '.[$k] | if type == "string" then . else empty end' "$cfg" 2>/dev/null || true
      return 0
      ;;
    python3|python)
      "$engine" -c 'import json, sys
try:
    v = json.load(open(sys.argv[1], encoding="utf-8")).get(sys.argv[2], "")
except Exception:
    v = ""
sys.stdout.write(v if isinstance(v, str) else "")' "$cfg" "$key" 2>/dev/null || true
      return 0
      ;;
    node|node.exe)
      "$engine" -e '
const fs = require("fs");
try {
  const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const v = cfg[process.argv[2]];
  if (typeof v === "string") process.stdout.write(v);
} catch {}
' "$cfg" "$key" 2>/dev/null || true
      return 0
      ;;
  esac

  _plain_string_value "$key" "$cfg"
}

# A plain one-line `"key": "value"`. Anchored so a nested key of the same name can't match.
_plain_string_value() {
  sed -nE "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]*)\"[[:space:]]*,?[[:space:]]*$/\1/p" "$2" 2>/dev/null | head -n1
}

resolve_state_root() {
  local root="${AUTOPILOT_STATE_DIR:-}"
  [ -n "$root" ] || root="$(_config_value state_root)"
  [ -n "$root" ] || root="$AUTOPILOT_HOME/state"
  root="$(printf '%s' "$root" | tr '\\' '/')"
  _expand_tilde "$root"
}

resolve_workspace_root() {
  local root="${AUTOPILOT_WORKSPACE_DIR:-}"
  [ -n "$root" ] || root="$(_config_value workspace_root)"
  [ -n "$root" ] || root="$AUTOPILOT_HOME/work"
  root="$(printf '%s' "$root" | tr '\\' '/')"
  _expand_tilde "$root"
}

# Checked here, at source time, and not inside resolve_*: those run in command
# substitution, where a non-zero return is swallowed by the very default-fallback chain it
# would need to interrupt — so a misread value would silently send gate output to a
# directory the orchestrator never reads.
_paths_preflight() {
  local cfg="$AUTOPILOT_HOME/config.json" k

  # Readability: only a concern when there is a config and no real parser to read it with.
  if [ -f "$cfg" ] && [ "$(resolve_json_engine)" = "none" ]; then
    for k in state_root workspace_root; do
      # An env override means the config value is never consulted, so it needn't be readable.
      if [ "$k" = state_root ] && [ -n "${AUTOPILOT_STATE_DIR:-}" ]; then continue; fi
      if [ "$k" = workspace_root ] && [ -n "${AUTOPILOT_WORKSPACE_DIR:-}" ]; then continue; fi
      if ! grep -qE "\"$k\"[[:space:]]*:" "$cfg" 2>/dev/null; then continue; fi
      if [ -n "$(_plain_string_value "$k" "$cfg")" ]; then continue; fi
      echo "autopilot: cannot read \"$k\" from $cfg without jq or python3 — install either," >&2
      echo "           or set AUTOPILOT_STATE_DIR / AUTOPILOT_WORKSPACE_DIR instead." >&2
      return 1
    done
  fi

  # Always. Checked here for the same reason as above: resolve_* run in command
  # substitution, where a non-zero return cannot stop the caller.
  _safe_path "state root" "$(resolve_state_root)" || return 1
  _safe_path "workspace root" "$(resolve_workspace_root)" || return 1
  return 0
}
_paths_preflight || exit 1
