#!/usr/bin/env bash
# Reset Sandbox Task to Broken Initial State for Live SWE-Agent Evaluation
# Usage: ./bin/reset-sandbox.sh [PROJ-1001 | PROJ-1002 | PROJ-1003 | clean]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TARGET="${1:-PROJ-1001}"

SANDBOX="$ROOT/examples/sandbox-repo"
CLIENT="$ROOT/examples/sandbox-client"
GOLDEN="$ROOT/examples/.golden"

restore_golden() {
  if [ -d "$GOLDEN/reference" ]; then
    cp "$GOLDEN/reference/paginate.js" "$SANDBOX/src/paginate.js"
    cp "$GOLDEN/reference/paginate.test.js" "$SANDBOX/test/paginate.test.js"
    cp "$GOLDEN/reference/token-verifier.js" "$SANDBOX/src/token-verifier.js"
    cp "$GOLDEN/reference/token-verifier.test.js" "$SANDBOX/test/token-verifier.test.js"
    cp "$GOLDEN/reference/schema-validator.js" "$SANDBOX/src/schema-validator.js"
    cp "$GOLDEN/reference/schema-validator.test.js" "$SANDBOX/test/schema-validator.test.js"
    cp "$GOLDEN/reference/client.js" "$CLIENT/src/client.js"
    cp "$GOLDEN/reference/client.test.js" "$CLIENT/test/client.test.js"
  fi
  # Also clean any git-tracked modifications if workspace is committed
  git -C "$ROOT" checkout -- "$SANDBOX" "$CLIENT" 2>/dev/null || true
}

case "$TARGET" in
  PROJ-1001)
    echo "Staging $SANDBOX to initial broken state for PROJ-1001 (Boundary Slicing)..."
    restore_golden
    cp "$GOLDEN/staged-proj-1001/paginate.js" "$SANDBOX/src/paginate.js"
    cp "$GOLDEN/staged-proj-1001/paginate.test.js" "$SANDBOX/test/paginate.test.js"
    echo "PROJ-1001 broken state successfully staged."
    echo ""
    echo "Next: Launch autonomous agent evaluation in Claude Code:"
    echo "  /autopilot:engage PROJ-1001 --file examples/sample-ticket-proj-1001.md"
    ;;

  PROJ-1002)
    echo "Staging $SANDBOX to initial state for PROJ-1002 (Injected Clock Skew Invariant)..."
    restore_golden
    cp "$GOLDEN/staged-proj-1002/token-verifier.js" "$SANDBOX/src/token-verifier.js"
    echo "PROJ-1002 defect state successfully staged."
    echo ""
    echo "Next: Launch autonomous agent evaluation in Claude Code:"
    echo "  /autopilot:engage PROJ-1002 --file examples/sample-ticket-proj-1002.md"
    ;;

  PROJ-1003)
    echo "Staging $SANDBOX and $CLIENT to initial state for PROJ-1003 (Contract Coordination)..."
    restore_golden
    cp "$GOLDEN/staged-proj-1003/schema-validator.js" "$SANDBOX/src/schema-validator.js"
    cp "$GOLDEN/staged-proj-1003/client.js" "$CLIENT/src/client.js"
    echo "PROJ-1003 multi-repo contract state successfully staged."
    echo ""
    echo "Next: Launch autonomous agent evaluation in Claude Code:"
    echo "  /autopilot:engage PROJ-1003 --file examples/sample-ticket-proj-1003.md"
    ;;

  clean)
    echo "Restoring all sandbox repositories to clean golden reference state..."
    restore_golden
    echo "All sandboxes restored to clean golden reference state."
    ;;

  *)
    echo "Usage: $(basename "$0") [PROJ-1001 | PROJ-1002 | PROJ-1003 | clean]" >&2
    exit 1
    ;;
esac
