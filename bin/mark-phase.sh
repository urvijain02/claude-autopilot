#!/usr/bin/env bash
# Record a phase timestamp in the ticket's .marks file and print the elapsed time, so the
# reporting stage has real timings rather than model-guessed ones. Writes nothing else —
# log.md has a fixed format the orchestrator owns.
# Usage:
#   mark-phase.sh <TICKET> <phase>     -> records a mark; prints elapsed since the previous one
#   mark-phase.sh <TICKET> --total     -> prints total elapsed since the first mark (no new mark)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/_paths.sh"
STATE_ROOT="$(resolve_state_root)"

ticket=""; phase=""
while [ $# -gt 0 ]; do
  case "$1" in
    --total) phase="--total"; shift ;;
    -*)      echo "unknown option: $1" >&2; exit 2 ;;
    *)       if [ -z "$ticket" ]; then ticket="$1"
             elif [ -z "$phase" ]; then phase="$1"
             else echo "unexpected argument: $1" >&2; exit 2; fi
             shift ;;
  esac
done
[ -n "$ticket" ] || { echo "usage: $(basename "$0") <TICKET> <phase|--total>" >&2; exit 2; }
[ -n "$phase" ] || phase="stage"
_safe_component ticket "$ticket" || exit 2

dir="$STATE_ROOT/$ticket"; mkdir -p "$dir"
marks="$dir/.marks"
now="$(date +%s)"

fmt() { local s=$1; if [ "$s" -ge 60 ]; then printf '%dm%02ds' $((s/60)) $((s%60)); else printf '%ds' "$s"; fi; }

if [ "$phase" = "--total" ]; then
  if [ -s "$marks" ]; then
    start="$(head -n1 "$marks" | cut -f1)"; fmt $((now-start))
  else
    printf '0s'
  fi
  exit 0
fi

if [ -s "$marks" ]; then
  prev="$(tail -n1 "$marks" | cut -f1)"
else
  prev="$now"
fi
printf '%s\t%s\n' "$now" "$phase" >> "$marks"

# stdout = stage elapsed, for the orchestrator's status line and its log.md section header
fmt $((now-prev))
