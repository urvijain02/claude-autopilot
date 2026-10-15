#!/usr/bin/env bash
# Run the test suite in a target repo; record an un-fakeable verdict centrally.
# Usage: gate-tests.sh <ticket> --repo <path> [--expect-fail]
#   --expect-fail : TDD mode. Tests SHOULD fail (new failing tests, not yet implemented).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${here}/_gate_lib.sh"
parse_args "$@"

# A non-zero exit alone doesn't prove a new failing test exists: a missing test script or
# an unbuildable repo exits non-zero too. Git is deterministic where the log is not — in
# .NET a test written before its production code legitimately fails to compile, so nothing
# in the log separates that from a broken build. Matching is broad on purpose: a false
# match only lets a gate pass, a false miss would reject real work.
touched_a_test() {
  local paths
  paths="$(git -C "$REPO" status --porcelain -uall 2>/dev/null | sed 's/^...//' || true)"
  printf '%s' "$paths" | grep -qiE '(^|[._/-])(tests?|specs?|__tests__)([._/-]|$)|[a-z0-9_]Tests?\.(cs|fs|vb|java)$'
}

stack="$(detect)"
log="$(gates_dir)/tests.log"
mkdir -p "$(gates_dir)"
# Truncated once, then appended to, so the restore trail shares the verdict's log.
: > "$log"

case "$stack" in
  dotnet) cmd="dotnet test" ;;
  node)   cmd="npm test" ;;
  *)      write_verdict tests skipped 0 "$stack" "none" "$log"
          echo "no known stack in $REPO; skipping test gate"; exit 0 ;;
esac

# .NET: ensure restore works (auto offline-cache workaround on a private-feed 401).
if [ "$stack" = "dotnet" ]; then
  # Not under $STATE: that is the durable audit trail and nothing ever reclaims it,
  # while fallback B can put a copy of the package cache here. The workspace is
  # outside the repo too and cleanup-workspace removes it with the clones.
  ovr="$(resolve_workspace_root)/${TICKET}/.nuget-override/${LABEL}"; rm -rf "$ovr"
  rc=0; "${here}/ensure-dotnet-restore.sh" "$REPO" "$ovr" >> "$log" 2>&1 || rc=$?
  if [ "$rc" -eq 3 ]; then
    write_verdict tests blocked 3 "$stack" "dotnet restore blocked (private-feed 401)" "$log"
    echo "restore blocked — needs a valid private feed credential; escalate to human" >&2
    exit 3
  fi
fi

# This command's own implicit restore needs the override too (see ensure-dotnet-restore).
if [ -f "${ovr:-}/nuget.config" ]; then
  cmd="$cmd /p:RestoreConfigFile=\"$ovr/nuget.config\""
fi

set +e
run_in_repo "$cmd" >> "$log" 2>&1
code=$?
set -e

if [ "$EXPECT_FAIL" -eq 1 ]; then
  if [ "$code" -eq 0 ]; then
    write_verdict tests fail 0 "$stack" "$cmd (expect-fail)" "$log"
    echo "TDD gate: tests were expected to FAIL but passed — no real failing test was added" >&2
    exit 1
  fi
  if ! touched_a_test; then
    write_verdict tests fail "$code" "$stack" "$cmd (expect-fail)" "$log"
    echo "TDD gate: suite exited $code but no test file was added or changed — that failure isn't a new test. See $log." >&2
    exit 1
  fi
  write_verdict tests pass "$code" "$stack" "$cmd (expect-fail)" "$log"; exit 0
fi

if [ "$code" -eq 0 ]; then
  write_verdict tests pass 0 "$stack" "$cmd" "$log"; exit 0
else
  write_verdict tests fail "$code" "$stack" "$cmd" "$log"; exit 1
fi
