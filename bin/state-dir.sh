#!/usr/bin/env bash
# Print a ticket's state dir, or the state root when called with no ticket.
# The single place $STATE is derived. An agent that reads state_root out of config itself
# is a second implementation of this, and the two disagree the moment either changes.
# Usage: state-dir.sh [<TICKET>]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/_paths.sh"
root="$(resolve_state_root)"
if [ -n "${1:-}" ]; then
  _safe_component ticket "$1" || exit 2
  printf '%s/%s\n' "$root" "$1"
else
  printf '%s\n' "$root"
fi
