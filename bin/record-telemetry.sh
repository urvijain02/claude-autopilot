#!/usr/bin/env bash
# Claude Autopilot — AI Telemetry & Token Economics Engine (RFC-002 / Phase 4)
# Records token consumption, prompt cache efficiency, and execution phase/stage latencies
# into a decoupled, durable artifact: $STATE/<TICKET>/telemetry.json
#
# Supported Engines (in fallback order via bin/_paths.sh):
#   1. jq
#   2. python3 / python
#   3. node / node.exe
#
# Usage:
#   record-telemetry.sh <TICKET> [options]
# Options:
#   --tokens-in <int>             Cumulative input tokens (default: 0)
#   --tokens-out <int>            Cumulative output tokens (default: 0)
#   --tokens-cache-read <int>     Cache read input tokens (default: 0)
#   --tokens-cache-creation <int> Cache creation input tokens (default: 0)
#   --analyst-model <str>         Analyst model name (default: claude-sonnet)
#   --implementer-model <str>     Implementer model name (default: claude-sonnet)
#   --reviewer-model <str>        Reviewer model name (default: claude-opus)
#   --stage <name> <seconds>      Explicit stage duration override
#   --phase <name> <seconds>      Explicit phase duration override
#   --total-duration <seconds>    Explicit total duration override
#   --print-banner                Print formatted terminal finish banner to stdout
#   --quiet                       Suppress confirmation output
#   -h, --help                    Show usage help
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/_paths.sh"
STATE_ROOT="$(resolve_state_root)"

ticket=""
tokens_in=0
tokens_out=0
tokens_cache_read=0
tokens_cache_creation=0
analyst_model="claude-sonnet"
implementer_model="claude-sonnet"
reviewer_model="claude-opus"
explicit_stages=()
explicit_phases=()
total_duration=""
print_banner=0
quiet=0

_to_int() { [[ "${1:-}" =~ ^[0-9]+$ ]] && echo "$1" || echo "0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --tokens-in|--input)                     tokens_in="${2:-0}"; shift 2 ;;
    --tokens-out|--output)                   tokens_out="${2:-0}"; shift 2 ;;
    --tokens-cache-read|--cache-read)        tokens_cache_read="${2:-0}"; shift 2 ;;
    --tokens-cache-creation|--cache-creation) tokens_cache_creation="${2:-0}"; shift 2 ;;
    --analyst-model)                         analyst_model="${2:-claude-sonnet}"; shift 2 ;;
    --implementer-model)                     implementer_model="${2:-claude-sonnet}"; shift 2 ;;
    --reviewer-model)                        reviewer_model="${2:-claude-opus}"; shift 2 ;;
    --stage)
      explicit_stages+=("$2=$3")
      shift 3 ;;
    --phase)
      explicit_phases+=("$2=$3")
      shift 3 ;;
    --total-duration)        total_duration="${2:-}"; shift 2 ;;
    --print-banner)          print_banner=1; shift ;;
    --quiet)                 quiet=1; shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") <TICKET> [OPTIONS]"
      echo "Records token consumption and phase/stage durations in \$STATE/<TICKET>/telemetry.json"
      exit 0 ;;
    -*)
      echo "unknown option: $1" >&2; exit 2 ;;
    *)
      if [ -z "$ticket" ]; then
        ticket="$1"
      else
        echo "unexpected argument: $1" >&2; exit 2
      fi
      shift ;;
  esac
done

tokens_in="$(_to_int "$tokens_in")"
tokens_out="$(_to_int "$tokens_out")"
tokens_cache_read="$(_to_int "$tokens_cache_read")"
tokens_cache_creation="$(_to_int "$tokens_cache_creation")"

[ -n "$ticket" ] || { echo "usage: $(basename "$0") <TICKET> [options]" >&2; exit 2; }
_safe_component ticket "$ticket" || exit 2

target_dir="$STATE_ROOT/$ticket"
mkdir -p "$target_dir"
marks_file="$target_dir/.marks"
telemetry_file="$target_dir/telemetry.json"

ENGINE="$(resolve_json_engine)"
if [ "$ENGINE" = "none" ]; then
  echo "Error: record-telemetry.sh requires jq, python3, or node to format telemetry JSON." >&2
  exit 1
fi

stages_arg=""
if [ ${#explicit_stages[@]} -gt 0 ]; then
  stages_arg="$(IFS=';'; echo "${explicit_stages[*]}")"
fi

phases_arg=""
if [ ${#explicit_phases[@]} -gt 0 ]; then
  phases_arg="$(IFS=';'; echo "${explicit_phases[*]}")"
fi

run_with_python() {
  local py_bin="$1"
  PYTHONIOENCODING="utf-8" "$py_bin" - \
    "$ticket" \
    "$marks_file" \
    "$telemetry_file" \
    "$tokens_in" \
    "$tokens_out" \
    "$tokens_cache_read" \
    "$tokens_cache_creation" \
    "$analyst_model" \
    "$implementer_model" \
    "$reviewer_model" \
    "$stages_arg" \
    "$phases_arg" \
    "$total_duration" \
    "$print_banner" \
    "$quiet" << 'PYEOF'
import sys
import os
import json

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

(
    ticket,
    marks_file,
    telemetry_file,
    tokens_in_str,
    tokens_out_str,
    tokens_cache_read_str,
    tokens_cache_creation_str,
    analyst_model,
    implementer_model,
    reviewer_model,
    stages_arg,
    phases_arg,
    total_duration_str,
    print_banner_str,
    quiet_str
) = sys.argv[1:16]

tokens_in = int(tokens_in_str) if tokens_in_str.isdigit() else 0
tokens_out = int(tokens_out_str) if tokens_out_str.isdigit() else 0
tokens_cache_read = int(tokens_cache_read_str) if tokens_cache_read_str.isdigit() else 0
tokens_cache_creation = int(tokens_cache_creation_str) if tokens_cache_creation_str.isdigit() else 0
print_banner = (print_banner_str == "1")
quiet = (quiet_str == "1")

existing = {}
if os.path.exists(telemetry_file):
    try:
        with open(telemetry_file, "r", encoding="utf-8") as f:
            existing = json.load(f)
    except Exception:
        existing = {}

if tokens_in == 0 and "tokens" in existing and "input" in existing["tokens"]:
    tokens_in = existing["tokens"]["input"]
if tokens_out == 0 and "tokens" in existing and "output" in existing["tokens"]:
    tokens_out = existing["tokens"]["output"]
if tokens_cache_read == 0 and "tokens" in existing and "cache_read" in existing["tokens"]:
    tokens_cache_read = existing["tokens"]["cache_read"]
if tokens_cache_creation == 0 and "tokens" in existing and "cache_creation" in existing["tokens"]:
    tokens_cache_creation = existing["tokens"]["cache_creation"]

STAGE_TO_PHASE = {
    "preflight": "plan_and_setup",
    "jira_start": "plan_and_setup",
    "jira-start": "plan_and_setup",
    "provision": "plan_and_setup",
    "provision_repo": "plan_and_setup",
    "provision-repo": "plan_and_setup",
    "requirements": "plan_and_setup",
    "test_plan": "plan_and_setup",
    "test-plan": "plan_and_setup",
    "branch": "plan_and_setup",
    "create_branch": "plan_and_setup",
    "create-branch": "plan_and_setup",
    "write_tests": "tdd_and_gates",
    "write-tests": "tdd_and_gates",
    "red_gate": "tdd_and_gates",
    "red-gate": "tdd_and_gates",
    "implement": "tdd_and_gates",
    "green_gate": "tdd_and_gates",
    "green-gate": "tdd_and_gates",
    "gate_tests": "tdd_and_gates",
    "gate-tests": "tdd_and_gates",
    "gate_build": "tdd_and_gates",
    "gate-build": "tdd_and_gates",
    "review": "review_and_delivery",
    "code_review": "review_and_delivery",
    "code-review": "review_and_delivery",
    "adversarial_review": "review_and_delivery",
    "adversarial-review": "review_and_delivery",
    "analyze": "review_and_delivery",
    "fix": "review_and_delivery",
    "commit": "review_and_delivery",
    "ticket_updates": "review_and_delivery",
    "ticket-updates": "review_and_delivery",
    "cleanup": "review_and_delivery",
    "done": "review_and_delivery",
}

def categorize_stage(stage_name):
    norm = stage_name.lower().strip()
    if norm in STAGE_TO_PHASE:
        return STAGE_TO_PHASE[norm]
    clean = norm.replace("-", "_")
    if clean in STAGE_TO_PHASE:
        return STAGE_TO_PHASE[clean]
    if any(k in clean for k in ["plan", "jira", "prov", "req", "branch"]):
        return "plan_and_setup"
    if any(k in clean for k in ["test", "impl", "build", "gate"]):
        return "tdd_and_gates"
    return "review_and_delivery"

stages = {}
if os.path.exists(marks_file):
    marks = []
    try:
        with open(marks_file, "r", encoding="utf-8") as f:
            for line in f:
                parts = line.strip().split("\t")
                if len(parts) >= 2 and parts[0].isdigit():
                    marks.append((int(parts[0]), parts[1].strip()))
    except Exception:
        marks = []

    if len(marks) >= 2:
        for i in range(len(marks) - 1):
            t_curr, s_curr = marks[i]
            t_next, _ = marks[i + 1]
            elapsed = max(0, t_next - t_curr)
            clean_stage = s_curr.replace("-", "_")
            stages[clean_stage] = stages.get(clean_stage, 0) + elapsed
    elif len(marks) == 1:
        stages[marks[0][1].replace("-", "_")] = 0

if stages_arg:
    for item in stages_arg.split(";"):
        if "=" in item:
            k, v = item.split("=", 1)
            if v.isdigit():
                stages[k.strip().replace("-", "_")] = int(v)

phases = {
    "plan_and_setup": 0,
    "tdd_and_gates": 0,
    "review_and_delivery": 0
}

for stage_name, duration in stages.items():
    cat = categorize_stage(stage_name)
    phases[cat] += duration

if phases_arg:
    for item in phases_arg.split(";"):
        if "=" in item:
            k, v = item.split("=", 1)
            clean_k = k.strip().replace("-", "_")
            if clean_k in phases and v.isdigit():
                phases[clean_k] = int(v)

if total_duration_str and total_duration_str.isdigit():
    total_seconds = int(total_duration_str)
else:
    total_seconds = phases["plan_and_setup"] + phases["tdd_and_gates"] + phases["review_and_delivery"]

if tokens_in > 0:
    cache_hit_rate = round((tokens_cache_read / tokens_in) * 100.0, 1)
else:
    cache_hit_rate = 0.0

telemetry_data = {
    "ticket": ticket,
    "models": {
        "analyst": analyst_model,
        "implementer": implementer_model,
        "reviewer": reviewer_model
    },
    "tokens": {
        "input": tokens_in,
        "output": tokens_out,
        "cache_read": tokens_cache_read,
        "cache_creation": tokens_cache_creation
    },
    "cache_hit_rate_percent": cache_hit_rate,
    "duration_seconds": {
        "total": total_seconds,
        "phases": phases,
        "stages": stages
    }
}

tmp_file = f"{telemetry_file}.tmp.{os.getpid()}"
with open(tmp_file, "w", encoding="utf-8") as f:
    json.dump(telemetry_data, f, indent=2)
    f.write("\n")
os.replace(tmp_file, telemetry_file)

if not quiet:
    print(f"Recorded telemetry: {telemetry_file}")

def fmt_time(s):
    if s >= 60:
        return f"{s // 60}m {s % 60:02d}s"
    return f"{s}s"

def fmt_tokens(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}k"
    return str(n)

if print_banner:
    banner = (
        f"⏱️ Duration: {fmt_time(total_seconds)} ("
        f"Plan & Setup: {fmt_time(phases['plan_and_setup'])} · "
        f"TDD & Gates: {fmt_time(phases['tdd_and_gates'])} · "
        f"Review & Delivery: {fmt_time(phases['review_and_delivery'])})\n"
        f"📊 Tokens: {fmt_tokens(tokens_in)} total | {fmt_tokens(tokens_cache_read)} cached "
        f"({cache_hit_rate}% prompt cache hit rate)"
    )
    print(banner)

PYEOF
}

run_with_node() {
  local node_bin="$1"
  "$node_bin" - \
    "$ticket" \
    "$marks_file" \
    "$telemetry_file" \
    "$tokens_in" \
    "$tokens_out" \
    "$tokens_cache_read" \
    "$tokens_cache_creation" \
    "$analyst_model" \
    "$implementer_model" \
    "$reviewer_model" \
    "$stages_arg" \
    "$phases_arg" \
    "$total_duration" \
    "$print_banner" \
    "$quiet" << 'NODEOF'
const fs = require("fs");

const [
  ticket, marks_file, telemetry_file,
  tokens_in_str, tokens_out_str, tokens_cache_read_str, tokens_cache_creation_str,
  analyst_model, implementer_model, reviewer_model,
  stages_arg, phases_arg, total_duration_str,
  print_banner_str, quiet_str
] = process.argv.slice(2);

let tokens_in = /^\d+$/.test(tokens_in_str) ? parseInt(tokens_in_str, 10) : 0;
let tokens_out = /^\d+$/.test(tokens_out_str) ? parseInt(tokens_out_str, 10) : 0;
let tokens_cache_read = /^\d+$/.test(tokens_cache_read_str) ? parseInt(tokens_cache_read_str, 10) : 0;
let tokens_cache_creation = /^\d+$/.test(tokens_cache_creation_str) ? parseInt(tokens_cache_creation_str, 10) : 0;
const print_banner = (print_banner_str === "1");
const quiet = (quiet_str === "1");

let existing = {};
if (fs.existsSync(telemetry_file)) {
  try {
    existing = JSON.parse(fs.readFileSync(telemetry_file, "utf8"));
  } catch {}
}

if (tokens_in === 0 && existing.tokens?.input) tokens_in = existing.tokens.input;
if (tokens_out === 0 && existing.tokens?.output) tokens_out = existing.tokens.output;
if (tokens_cache_read === 0 && existing.tokens?.cache_read) tokens_cache_read = existing.tokens.cache_read;
if (tokens_cache_creation === 0 && existing.tokens?.cache_creation) tokens_cache_creation = existing.tokens.cache_creation;

const STAGE_TO_PHASE = {
  "preflight": "plan_and_setup",
  "jira_start": "plan_and_setup",
  "jira-start": "plan_and_setup",
  "provision": "plan_and_setup",
  "provision_repo": "plan_and_setup",
  "provision-repo": "plan_and_setup",
  "requirements": "plan_and_setup",
  "test_plan": "plan_and_setup",
  "test-plan": "plan_and_setup",
  "branch": "plan_and_setup",
  "create_branch": "plan_and_setup",
  "create-branch": "plan_and_setup",
  "write_tests": "tdd_and_gates",
  "write-tests": "tdd_and_gates",
  "red_gate": "tdd_and_gates",
  "red-gate": "tdd_and_gates",
  "implement": "tdd_and_gates",
  "green_gate": "tdd_and_gates",
  "green-gate": "tdd_and_gates",
  "gate_tests": "tdd_and_gates",
  "gate-tests": "tdd_and_gates",
  "gate_build": "tdd_and_gates",
  "gate-build": "tdd_and_gates",
  "review": "review_and_delivery",
  "code_review": "review_and_delivery",
  "code-review": "review_and_delivery",
  "adversarial_review": "review_and_delivery",
  "adversarial-review": "review_and_delivery",
  "analyze": "review_and_delivery",
  "fix": "review_and_delivery",
  "commit": "review_and_delivery",
  "ticket_updates": "review_and_delivery",
  "ticket-updates": "review_and_delivery",
  "cleanup": "review_and_delivery",
  "done": "review_and_delivery"
};

function categorize_stage(stage_name) {
  const norm = stage_name.toLowerCase().trim();
  if (STAGE_TO_PHASE[norm]) return STAGE_TO_PHASE[norm];
  const clean = norm.replace(/-/g, "_");
  if (STAGE_TO_PHASE[clean]) return STAGE_TO_PHASE[clean];
  if (["plan", "jira", "prov", "req", "branch"].some(k => clean.includes(k))) return "plan_and_setup";
  if (["test", "impl", "build", "gate"].some(k => clean.includes(k))) return "tdd_and_gates";
  return "review_and_delivery";
}

const stages = {};
if (fs.existsSync(marks_file)) {
  const marks = [];
  try {
    const lines = fs.readFileSync(marks_file, "utf8").split("\n");
    for (const line of lines) {
      const parts = line.trim().split("\t");
      if (parts.length >= 2 && /^\d+$/.test(parts[0])) {
        marks.push([parseInt(parts[0], 10), parts[1].trim()]);
      }
    }
  } catch {}

  if (marks.length >= 2) {
    for (let i = 0; i < marks.length - 1; i++) {
      const [t_curr, s_curr] = marks[i];
      const [t_next] = marks[i + 1];
      const elapsed = Math.max(0, t_next - t_curr);
      const clean_stage = s_curr.replace(/-/g, "_");
      stages[clean_stage] = (stages[clean_stage] || 0) + elapsed;
    }
  } else if (marks.length === 1) {
    stages[marks[0][1].replace(/-/g, "_")] = 0;
  }
}

if (stages_arg) {
  for (const item of stages_arg.split(";")) {
    if (item.includes("=")) {
      const [k, v] = item.split("=");
      if (/^\d+$/.test(v)) stages[k.trim().replace(/-/g, "_")] = parseInt(v, 10);
    }
  }
}

const phases = { plan_and_setup: 0, tdd_and_gates: 0, review_and_delivery: 0 };
for (const [s_name, dur] of Object.entries(stages)) {
  phases[categorize_stage(s_name)] += dur;
}

if (phases_arg) {
  for (const item of phases_arg.split(";")) {
    if (item.includes("=")) {
      const [k, v] = item.split("=");
      const clean_k = k.trim().replace(/-/g, "_");
      if (phases[clean_k] !== undefined && /^\d+$/.test(v)) {
        phases[clean_k] = parseInt(v, 10);
      }
    }
  }
}

let total_seconds;
if (total_duration_str && /^\d+$/.test(total_duration_str)) {
  total_seconds = parseInt(total_duration_str, 10);
} else {
  total_seconds = phases.plan_and_setup + phases.tdd_and_gates + phases.review_and_delivery;
}

const cache_hit_rate = (tokens_in > 0)
  ? Math.round((tokens_cache_read / tokens_in) * 1000) / 10
  : 0.0;

const telemetry_data = {
  ticket,
  models: { analyst: analyst_model, implementer: implementer_model, reviewer: reviewer_model },
  tokens: {
    input: tokens_in,
    output: tokens_out,
    cache_read: tokens_cache_read,
    cache_creation: tokens_cache_creation
  },
  cache_hit_rate_percent: cache_hit_rate,
  duration_seconds: {
    total: total_seconds,
    phases,
    stages
  }
};

const tmp_file = `${telemetry_file}.tmp.${process.pid}`;
fs.writeFileSync(tmp_file, JSON.stringify(telemetry_data, null, 2) + "\n", "utf8");
fs.renameSync(tmp_file, telemetry_file);

if (!quiet) console.log(`Recorded telemetry: ${telemetry_file}`);

function fmt_time(s) {
  return s >= 60 ? `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, "0")}s` : `${s}s`;
}
function fmt_tokens(n) {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return String(n);
}

if (print_banner) {
  console.log(
    `⏱️ Duration: ${fmt_time(total_seconds)} (Plan & Setup: ${fmt_time(phases.plan_and_setup)} · TDD & Gates: ${fmt_time(phases.tdd_and_gates)} · Review & Delivery: ${fmt_time(phases.review_and_delivery)})\n` +
    `📊 Tokens: ${fmt_tokens(tokens_in)} total | ${fmt_tokens(tokens_cache_read)} cached (${cache_hit_rate}% prompt cache hit rate)`
  );
}
NODEOF
}

run_with_jq() {
  local existing_in=0 existing_out=0 existing_cache_read=0 existing_cache_create=0
  if [ -f "$telemetry_file" ]; then
    existing_in="$(_to_int "$(jq -r '.tokens.input // 0' "$telemetry_file" 2>/dev/null)")"
    existing_out="$(_to_int "$(jq -r '.tokens.output // 0' "$telemetry_file" 2>/dev/null)")"
    existing_cache_read="$(_to_int "$(jq -r '.tokens.cache_read // 0' "$telemetry_file" 2>/dev/null)")"
    existing_cache_create="$(_to_int "$(jq -r '.tokens.cache_creation // 0' "$telemetry_file" 2>/dev/null)")"
  fi
  [ "$tokens_in" -eq 0 ] && [ "$existing_in" -gt 0 ] && tokens_in="$existing_in"
  [ "$tokens_out" -eq 0 ] && [ "$existing_out" -gt 0 ] && tokens_out="$existing_out"
  [ "$tokens_cache_read" -eq 0 ] && [ "$existing_cache_read" -gt 0 ] && tokens_cache_read="$existing_cache_read"
  [ "$tokens_cache_creation" -eq 0 ] && [ "$existing_cache_create" -gt 0 ] && tokens_cache_creation="$existing_cache_create"

  local stages_tmp
  stages_tmp="$(mktemp)" || exit 1
  local marks_input="${marks_file}"
  [ -f "$marks_input" ] || marks_input="/dev/null"

  awk -F'\t' -v ov="$stages_arg" '
    NF >= 2 {
      t = $1; s = $2;
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s);
      gsub(/-/, "_", s);
      if (prev_t != "") {
        el = t - prev_t;
        if (el < 0) el = 0;
        stages[prev_s] += el;
      }
      prev_t = t;
      prev_s = s;
    }
    END {
      if (ov != "") {
        n = split(ov, arr, ";");
        for (i = 1; i <= n; i++) {
          if (arr[i] != "") {
            split(arr[i], kv, "=");
            k = kv[1]; v = kv[2];
            gsub(/-/, "_", k);
            stages[k] = v + 0;
          }
        }
      }
      for (st in stages) {
        printf "%s=%d\n", st, stages[st];
      }
    }
  ' "$marks_input" > "$stages_tmp"

  local plan_sec=0 tdd_sec=0 rev_sec=0
  local stages_json="{" first=1
  if [ -s "$stages_tmp" ]; then
    while IFS='=' read -r st_name dur; do
      [ -n "$st_name" ] || continue
      [[ "$dur" =~ ^[0-9]+$ ]] || continue
      case "$st_name" in
        preflight|jira*|prov*|req*|test_plan|branch*|create_branch)
          plan_sec=$(( plan_sec + dur )) ;;
        write_tests|red_gate|implement|green_gate|gate_tests|gate_build)
          tdd_sec=$(( tdd_sec + dur )) ;;
        *)
          rev_sec=$(( rev_sec + dur )) ;;
      esac
      [ "$first" -eq 1 ] && first=0 || stages_json+=","
      stages_json+="\"$st_name\":$dur"
    done < "$stages_tmp"
  fi
  stages_json+="}"
  rm -f "$stages_tmp"

  if [ -n "$phases_arg" ]; then
    local item k v
    IFS=';' read -ra items <<< "$phases_arg"
    for item in "${items[@]}"; do
      k="${item%%=*}"; v="${item#*=}"
      k="${k//-/_}"
      if [[ "$v" =~ ^[0-9]+$ ]]; then
        case "$k" in
          plan_and_setup) plan_sec="$v" ;;
          tdd_and_gates) tdd_sec="$v" ;;
          review_and_delivery) rev_sec="$v" ;;
        esac
      fi
    done
  fi

  local tot_sec
  if [ -n "$total_duration" ] && [[ "$total_duration" =~ ^[0-9]+$ ]]; then
    tot_sec="$total_duration"
  else
    tot_sec=$(( plan_sec + tdd_sec + rev_sec ))
  fi

  local cache_rate="0.0"
  if [ "$tokens_in" -gt 0 ]; then
    local rate_x10=$(( (tokens_cache_read * 1000 + tokens_in / 2) / tokens_in ))
    cache_rate="$(printf '%d.%d' $((rate_x10 / 10)) $((rate_x10 % 10)))"
  fi

  local tmp_file="${telemetry_file}.tmp.$$"
  jq -n \
    --arg ticket "$ticket" \
    --arg a_mod "$analyst_model" \
    --arg i_mod "$implementer_model" \
    --arg r_mod "$reviewer_model" \
    --argjson in_tok "$tokens_in" \
    --argjson out_tok "$tokens_out" \
    --argjson cache_read "$tokens_cache_read" \
    --argjson cache_create "$tokens_cache_creation" \
    --argjson cache_rate "$cache_rate" \
    --argjson total_sec "$tot_sec" \
    --argjson plan_sec "$plan_sec" \
    --argjson tdd_sec "$tdd_sec" \
    --argjson rev_sec "$rev_sec" \
    --argjson stages_obj "$stages_json" \
    '{
      ticket: $ticket,
      models: { analyst: $a_mod, implementer: $i_mod, reviewer: $r_mod },
      tokens: { input: $in_tok, output: $out_tok, cache_read: $cache_read, cache_creation: $cache_create },
      cache_hit_rate_percent: $cache_rate,
      duration_seconds: {
        total: $total_sec,
        phases: { plan_and_setup: $plan_sec, tdd_and_gates: $tdd_sec, review_and_delivery: $rev_sec },
        stages: $stages_obj
      }
    }' > "$tmp_file"
  mv "$tmp_file" "$telemetry_file"

  [ "$quiet" -eq 1 ] || echo "Recorded telemetry: $telemetry_file"

  if [ "$print_banner" -eq 1 ]; then
    fmt_t() { local s=$1; [ "$s" -ge 60 ] && printf '%dm %02ds' $((s/60)) $((s%60)) || printf '%ds' "$s"; }
    fmt_tok() {
      local n=$1
      if [ "$n" -ge 1000000 ]; then
        local m=$(( (n * 10 + 500000) / 1000000 ))
        printf '%d.%dM' $((m/10)) $((m%10))
      elif [ "$n" -ge 1000 ]; then
        local k=$(( (n * 10 + 500) / 1000 ))
        printf '%d.%dk' $((k/10)) $((k%10))
      else
        printf '%d' "$n"
      fi
    }
    echo "⏱️ Duration: $(fmt_t "$tot_sec") (Plan & Setup: $(fmt_t "$plan_sec") · TDD & Gates: $(fmt_t "$tdd_sec") · Review & Delivery: $(fmt_t "$rev_sec"))"
    echo "📊 Tokens: $(fmt_tok "$tokens_in") total | $(fmt_tok "$tokens_cache_read") cached (${cache_rate}% prompt cache hit rate)"
  fi
}

case "$ENGINE" in
  jq)
    run_with_jq
    ;;
  python3|python)
    run_with_python "$ENGINE"
    ;;
  node|node.exe)
    run_with_node "$ENGINE"
    ;;
esac
