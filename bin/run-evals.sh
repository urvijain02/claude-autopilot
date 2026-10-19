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

verify_telemetry_invariants() {
  local tel_file="$1" ticket="$2" in_tok="$3" cache_tok="$4"
  local engine; engine="$(resolve_json_engine)"

  case "$engine" in
    jq)
      jq -e \
        --arg exp_t "$ticket" \
        --argjson exp_in "$in_tok" \
        --argjson exp_cache "$cache_tok" '
        .ticket == $exp_t and
        (.models.analyst | type == "string") and
        (.models.implementer | type == "string") and
        (.models.reviewer | type == "string") and
        .tokens.input == $exp_in and
        .tokens.cache_read == $exp_cache and
        (.tokens.output | type == "number") and
        (.tokens.cache_creation | type == "number") and
        ((.cache_hit_rate_percent - (if $exp_in > 0 then (($exp_cache / $exp_in * 1000 | round) / 10) else 0 end)) | (if . < 0 then -. else . end) < 0.05) and
        (.duration_seconds.phases.plan_and_setup | type == "number") and
        (.duration_seconds.phases.tdd_and_gates | type == "number") and
        (.duration_seconds.phases.review_and_delivery | type == "number") and
        .duration_seconds.total == (.duration_seconds.phases.plan_and_setup + .duration_seconds.phases.tdd_and_gates + .duration_seconds.phases.review_and_delivery) and
        (.duration_seconds.stages | type == "object")
      ' "$tel_file" >/dev/null 2>&1
      return $?
      ;;
    python3|python)
      "$engine" - "$tel_file" "$ticket" "$in_tok" "$cache_tok" << 'PYEOF' >/dev/null 2>&1
import sys, json

tel_file, expected_ticket, exp_in, exp_cache = sys.argv[1:5]
with open(tel_file, "r", encoding="utf-8") as f:
    d = json.load(f)

# 1. Identity & model schema assertions
assert d.get("ticket") == expected_ticket, "Ticket mismatch"
models = d.get("models", {})
assert isinstance(models.get("analyst"), str) and isinstance(models.get("implementer"), str) and isinstance(models.get("reviewer"), str), "Models schema invalid"

# 2. Token contract & cache hit rate invariants
toks = d.get("tokens", {})
assert toks.get("input") == int(exp_in), "Input tokens mismatch"
assert toks.get("cache_read") == int(exp_cache), "Cache read mismatch"
assert isinstance(toks.get("output"), int) and isinstance(toks.get("cache_creation"), int), "Tokens output/creation invalid"

expected_hit_rate = round((int(exp_cache) / int(exp_in)) * 100.0, 1)
assert abs(d.get("cache_hit_rate_percent", 0) - expected_hit_rate) < 0.05, "Hit rate math mismatch"

# 3. Duration & phase sum invariants
dur = d.get("duration_seconds", {})
total = dur.get("total", 0)
phases = dur.get("phases", {})
phase_sum = phases.get("plan_and_setup", 0) + phases.get("tdd_and_gates", 0) + phases.get("review_and_delivery", 0)
assert total == phase_sum, f"Total duration {total} != phase sum {phase_sum}"
assert isinstance(dur.get("stages"), dict), "Stages object missing or invalid"
sys.exit(0)
PYEOF
      return $?
      ;;
    node|node.exe|*)
      local node_exec="${engine}"
      [ "$node_exec" = "node" ] || [ "$node_exec" = "node.exe" ] || node_exec="$NODE_CMD"
      "$node_exec" - "$tel_file" "$ticket" "$in_tok" "$cache_tok" << 'NODEOF' >/dev/null 2>&1
const fs = require("fs");
const [telFile, expectedTicket, expInStr, expCacheStr] = process.argv.slice(2);
const d = JSON.parse(fs.readFileSync(telFile, "utf8"));
const expIn = parseInt(expInStr, 10);
const expCache = parseInt(expCacheStr, 10);

if (d.ticket !== expectedTicket) process.exit(1);
if (typeof d.models?.analyst !== "string" || typeof d.models?.implementer !== "string" || typeof d.models?.reviewer !== "string") process.exit(1);
if (d.tokens?.input !== expIn || d.tokens?.cache_read !== expCache) process.exit(1);
if (typeof d.tokens?.output !== "number" || typeof d.tokens?.cache_creation !== "number") process.exit(1);

const expectedHitRate = expIn > 0 ? Math.round((expCache / expIn) * 1000) / 10 : 0.0;
if (Math.abs((d.cache_hit_rate_percent || 0) - expectedHitRate) >= 0.05) process.exit(1);

const dur = d.duration_seconds || {};
const total = dur.total || 0;
const phases = dur.phases || {};
const phaseSum = (phases.plan_and_setup || 0) + (phases.tdd_and_gates || 0) + (phases.review_and_delivery || 0);
if (total !== phaseSum) process.exit(1);
if (typeof dur.stages !== "object" || dur.stages === null) process.exit(1);
process.exit(0);
NODEOF
      return $?
      ;;
  esac
}

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

  # 4. Real Telemetry Engine execution (record-telemetry.sh)
  echo -n "  • Executing telemetry engine (record-telemetry.sh)... "
  local eval_ticket="EVAL-${id}"
  local m_file="${STATE_ROOT}/${eval_ticket}/.marks"
  local now
  now="$(date +%s)"
  mkdir -p "${STATE_ROOT}/${eval_ticket}"
  {
    printf '%s\tpreflight\n' "$((now - 45))"
    printf '%s\tjira-start\n' "$((now - 43))"
    printf '%s\tprovision\n' "$((now - 39))"
    printf '%s\trequirements\n' "$((now - 33))"
    printf '%s\ttest-plan\n' "$((now - 29))"
    printf '%s\tbranch\n' "$((now - 27))"
    printf '%s\twrite-tests\n' "$((now - 25))"
    printf '%s\timplement\n' "$((now - 13))"
    printf '%s\treview\n' "$((now - 5))"
    printf '%s\tcommit\n' "$((now - 2))"
    printf '%s\tticket-updates\n' "$now"
  } > "$m_file"

  local tokens_in="${4:-112000}"
  local tokens_out="${5:-12400}"
  local tokens_cache_read="${6:-94500}"
  local tokens_cache_creation="${7:-17500}"

  if "$HERE/record-telemetry.sh" "$eval_ticket" \
      --tokens-in "$tokens_in" \
      --tokens-out "$tokens_out" \
      --tokens-cache-read "$tokens_cache_read" \
      --tokens-cache-creation "$tokens_cache_creation" \
      --print-banner >/dev/null 2>&1; then
    local tel_json="${STATE_ROOT}/${eval_ticket}/telemetry.json"
    if [ -f "$tel_json" ] && verify_telemetry_invariants "$tel_json" "$eval_ticket" "$tokens_in" "$tokens_cache_read"; then
      echo -e "${GREEN}PASS${NC} (recorded: telemetry.json)"
    else
      echo -e "${RED}FAIL${NC} (telemetry contract or invariant assertion failed)"
      return 1
    fi
  else
    echo -e "${RED}FAIL${NC} (telemetry execution error)"
    return 1
  fi

  echo -e "  • ${GREEN}Benchmark ${id} Invariants, Gates & Telemetry Verified.${NC}\n"
  return 0
}

failures=0

if [ "$TARGET" = "PROJ-1001" ] || [ "$TARGET" = "all" ]; then
  run_task "PROJ-1001" "Boundary Regression Slicing" "test/paginate.test.js" 82000 8400 68000 14000 || failures=$((failures + 1))
fi

if [ "$TARGET" = "PROJ-1002" ] || [ "$TARGET" = "all" ]; then
  run_task "PROJ-1002" "Token Expiry & Clock Skew Invariant" "test/token-verifier.test.js" 124500 14200 102000 22500 || failures=$((failures + 1))
fi

if [ "$TARGET" = "PROJ-1003" ] || [ "$TARGET" = "all" ]; then
  run_task "PROJ-1003" "Multi-Repo Contract (Server)" "test/schema-validator.test.js" 198000 24000 166000 32000 || failures=$((failures + 1))

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
  echo -e "${GREEN}  ALL GOLDEN BENCHMARKS & QUALITY GATES VERIFIED (${TARGET})${NC}"
  echo -e "  Gates: 3/3 PASS  ·  Telemetry: 3/3 PASS  ·  Zero Defect"
  echo -e "  Harness Status: READY FOR AGENT EVALUATION"
  echo -e ""
  echo -e "  To evaluate Claude Autopilot autonomously on a live task:"
  echo -e "    1. ./bin/reset-sandbox.sh PROJ-1001"
  echo -e "    2. In Claude Code: /autopilot:engage PROJ-1001 --file examples/sample-ticket-proj-1001.md"
else
  echo -e "${RED}  HARNESS INTEGRITY CHECK FAILED WITH ${failures} DEFECT(S)${NC}"
  exit 1
fi
echo -e "${BLUE}================================================================${NC}"
