#!/usr/bin/env bash
# Benchmark Harness & Invariant Verifier for Claude Autopilot (RFC-002)
# Tier 1: Deterministic Quality Gate & Sandbox Invariant Verification
# Usage: ./bin/run-evals.sh [PROJ-1001 | PROJ-1002 | PROJ-1003 | all]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TARGET="${1:-all}"

# Source central paths
. "$HERE/_paths.sh"
STATE_ROOT="$(resolve_state_root)"

# Color output helpers
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}  Claude Autopilot — Benchmark Harness & Invariant Verification ${NC}"
echo -e "${BLUE}  RFC-002: Autonomous SWE-Agent Verification Protocol (Tier 1)  ${NC}"
echo -e "${BLUE}================================================================${NC}"

# Check prerequisites and resolve node command dynamically
NODE_CMD="node"
if ! command -v "$NODE_CMD" >/dev/null 2>&1; then
  if command -v node.exe >/dev/null 2>&1; then
    NODE_CMD="node.exe"
  else
    echo -e "${RED}Error: node runtime is required to execute sandbox benchmarks.${NC}" >&2
    exit 1
  fi
fi

NODE_VER="$("$NODE_CMD" -v)"
echo -e "Node Runtime: ${GREEN}${NODE_VER}${NC} (native node:test engine)"
echo -e "Benchmark Scope: ${YELLOW}${TARGET}${NC}\n"

SANDBOX="$ROOT/examples/sandbox-repo"
CLIENT="$ROOT/examples/sandbox-client"

run_task() {
  local id="$1"
  local name="$2"
  local file="$3"

  echo -e "${BLUE}----------------------------------------------------------------${NC}"
  echo -e "Executing Benchmark: ${YELLOW}${id}${NC} — ${name}"
  echo -e "${BLUE}----------------------------------------------------------------${NC}"

  # 1. Direct unit test execution in sandbox
  echo -n "  • Running native unit test (${file})... "
  if (cd "$SANDBOX" && "$NODE_CMD" --test "$file" >/dev/null 2>&1); then
    echo -e "${GREEN}PASS${NC}"
  else
    echo -e "${RED}FAIL${NC}"
    return 1
  fi

  # 2. Real Gate Build execution
  echo -n "  • Executing real build gate (gate-build.sh)... "
  if "$HERE/gate-build.sh" "EVAL-${id}" --repo "$SANDBOX" --label "sandbox-repo" >/dev/null 2>&1; then
    local b_json="${STATE_ROOT}/EVAL-${id}/gates/sandbox-repo/build.json"
    if [ -f "$b_json" ] && grep -q '"status": "pass"' "$b_json"; then
      echo -e "${GREEN}PASS${NC} (recorded: build.json)"
    else
      echo -e "${RED}FAIL${NC} (invalid verdict)"
      return 1
    fi
  else
    echo -e "${RED}FAIL${NC}"
    return 1
  fi

  # 3. Real Gate Tests execution
  echo -n "  • Executing real test gate (gate-tests.sh)... "
  if "$HERE/gate-tests.sh" "EVAL-${id}" --repo "$SANDBOX" --label "sandbox-repo" >/dev/null 2>&1; then
    local t_json="${STATE_ROOT}/EVAL-${id}/gates/sandbox-repo/tests.json"
    if [ -f "$t_json" ] && grep -q '"status": "pass"' "$t_json"; then
      echo -e "${GREEN}PASS${NC} (recorded: tests.json)"
    else
      echo -e "${RED}FAIL${NC} (invalid verdict)"
      return 1
    fi
  else
    echo -e "${RED}FAIL${NC}"
    return 1
  fi

  echo -e "  • ${GREEN}Benchmark ${id} Invariants & Gates Verified.${NC}\n"
  return 0
}

failures=0

if [ "$TARGET" = "PROJ-1001" ] || [ "$TARGET" = "all" ]; then
  run_task "PROJ-1001" "Boundary Regression Slicing" "test/paginate.test.js" || failures=$((failures + 1))
fi

if [ "$TARGET" = "PROJ-1002" ] || [ "$TARGET" = "all" ]; then
  run_task "PROJ-1002" "Token Expiry & Clock Skew Invariant" "test/token-verifier.test.js" || failures=$((failures + 1))
fi

if [ "$TARGET" = "PROJ-1003" ] || [ "$TARGET" = "all" ]; then
  run_task "PROJ-1003" "Multi-Repo Contract (Server)" "test/schema-validator.test.js" || failures=$((failures + 1))

  echo -n "  • Multi-Repo Client Build Gate (gate-build.sh)... "
  if "$HERE/gate-build.sh" "EVAL-PROJ-1003" --repo "$CLIENT" --label "sandbox-client" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
  else
    echo -e "${RED}FAIL${NC}"
    failures=$((failures + 1))
  fi

  echo -n "  • Multi-Repo Client Test Gate (gate-tests.sh)... "
  if "$HERE/gate-tests.sh" "EVAL-PROJ-1003" --repo "$CLIENT" --label "sandbox-client" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
  else
    echo -e "${RED}FAIL${NC}"
    failures=$((failures + 1))
  fi
  echo ""
fi

echo -e "${BLUE}================================================================${NC}"
if [ "$failures" -eq 0 ]; then
  echo -e "${GREEN}  ALL GOLDEN BENCHMARKS & GATES VERIFIED DETERMINISTICALLY (${TARGET})${NC}"
  echo -e "  Harness Status: READY FOR AGENT EVALUATION | Gates Verified: 3/3 | Zero Defect"
  echo -e ""
  echo -e "  To evaluate Claude Autopilot autonomously on a live task:"
  echo -e "    1. ./bin/reset-sandbox.sh PROJ-1001"
  echo -e "    2. In Claude Code: /autopilot:engage PROJ-1001 --file examples/sample-ticket-proj-1001.md"
else
  echo -e "${RED}  HARNESS INTEGRITY CHECK FAILED WITH ${failures} DEFECT(S)${NC}"
  exit 1
fi
echo -e "${BLUE}================================================================${NC}"
