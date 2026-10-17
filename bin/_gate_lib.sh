#!/usr/bin/env bash
# shellcheck disable=SC2034
# Shared helpers for the generic gate scripts.
# One install at ${CLAUDE_PLUGIN_ROOT}/bin serves every repo. Gates run commands
# INSIDE the target repo (--repo) and write verdicts to a CENTRAL state dir, so
# the target repo is never polluted with pipeline state.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Central state root. Never inside the target repo. See _paths.sh for precedence.
. "$here/_paths.sh"
STATE_ROOT="$(resolve_state_root)"

expand_tilde() { printf '%s' "${1/#\~/$HOME}"; }

TICKET=""; REPO="."; LABEL=""; EXPECT_FAIL=0

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)        REPO="$(expand_tilde "$2")"; shift 2 ;;
      --label)       LABEL="$2"; shift 2 ;;
      --expect-fail) EXPECT_FAIL=1; shift ;;
      -*)            echo "unknown flag: $1" >&2; exit 2 ;;
      *)             if [ -z "$TICKET" ]; then TICKET="$1"; shift
                     else echo "unexpected arg: $1" >&2; exit 2; fi ;;
    esac
  done
  if [ -z "$TICKET" ]; then
    echo "usage: $(basename "$0") <ticket> --repo <path> [--label <repo-name>] [--expect-fail]" >&2
    exit 2
  fi
  if [ ! -d "$REPO" ]; then
    echo "repo path not found: $REPO" >&2; exit 2
  fi
  # Multi-repo: verdicts are namespaced per repo. Default the label to the repo dir name.
  if [ -z "$LABEL" ]; then LABEL="$(basename "$REPO")"; fi
  _safe_component ticket "$TICKET" || exit 2
  _safe_component label "$LABEL" || exit 2
}

state_dir() { echo "${STATE_ROOT}/${TICKET}"; }
gates_dir() { echo "${STATE_ROOT}/${TICKET}/gates/${LABEL}"; }

detect() { "${here}/detect-stack.sh" "$REPO"; }

# Subshell, so the cd cannot leak back to the caller and shift its relative paths.
# Callers must ensure any interpolated directory paths or flags are validated via _safe_path.
run_in_repo() { ( cd "$REPO" && eval "$1" ); }

# The verdict is the one thing downstream stages are required to trust, so a repo
# path or command containing a quote or backslash must not be able to turn it into
# unparseable JSON.
_json_esc() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  # Any other control byte would land raw inside the JSON string, which is invalid.
  # Dropping them keeps the verdict parseable; they mean nothing in a path or command.
  printf '%s' "$s" | tr -d '\001-\010\013\014\016-\037'
}

# write_verdict <gate> <status> <exit_code> <stack> <command> <log_file>
write_verdict() {
  local gate="$1" status="$2" code="$3" stack="$4" cmd="$5" log="$6"
  local dir; dir="$(gates_dir)"
  mkdir -p "$dir"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # Never invent this number: exit_code is what downstream stages trust, and coercing a
  # non-numeric value to 0 records a success that never happened. A caller passing one is
  # a bug, so fail — the missing verdict then forces a re-run rather than hiding it.
  if ! [[ "$code" =~ ^-?[0-9]+$ ]]; then
    echo "write_verdict: non-numeric exit code '$code' for gate '$gate'" >&2
    return 1
  fi
  cat > "${dir}/${gate}.json" <<JSON
{
  "gate": "$(_json_esc "$gate")",
  "label": "$(_json_esc "$LABEL")",
  "status": "$(_json_esc "$status")",
  "exit_code": ${code},
  "stack": "$(_json_esc "$stack")",
  "repo": "$(_json_esc "$REPO")",
  "command": "$(_json_esc "$cmd")",
  "log_file": "$(_json_esc "$log")",
  "timestamp": "${ts}"
}
JSON
  echo "[gate:${gate}] ${status} (exit ${code}) repo=${REPO} -> ${dir}/${gate}.json"
}
