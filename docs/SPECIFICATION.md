# System Architecture Specification & Protocol: Claude Autopilot
**RFC-001: Unattended Ticket-to-PR Autonomous Engineering Pipeline**  
**Author:** Urvi Jain ([@urvijain02](https://github.com/urvijain02))  
**Status:** Living Specification / Production Standard  
**Revision:** 1.0.0  

---

## 1. Executive Summary & Design Philosophy

`claude-autopilot` is an autonomous software engineering (SWE) pipeline designed to bridge the gap between ticket management systems (Jira / GitHub Issues) and production-grade pull requests without human supervision.

Unlike conversational coding assistants or unverified LLM scratchpads, the system is engineered around three foundational systems-engineering principles:

1. **Deterministic Quality Verification (Zero Model Self-Grading):** LLMs cannot reliably grade their own code. All build, syntax, and test validations are delegated to external, deterministic shell scripts (`gate-tests.sh`, `gate-build.sh`) whose UNIX exit codes dictate pipeline progression. The model cannot argue past or hallucinate a passing test suite.
2. **Crash-Resilient Disk-Persisted State Machine:** All execution context, stage transitions, and inter-agent messages are persisted to disk in vendor-neutral JSON schemas (`state.json`, `review-findings.json`). If a session terminates mid-run, the pipeline can be resumed idempotently from the exact point of interruption without losing work.
3. **Asymmetric Context Isolation:** To eliminate sycophancy (models approving their own flawed changes), authoring and review roles operate in strictly decoupled subagent sessions across asymmetric model tiers (e.g. Anthropic Claude 3.7 Sonnet for rapid code generation vs. Claude 3 Opus for adversarial review).

---

## 2. State Machine Formalism

The orchestrator operates as a discrete finite-state machine (FSM). The next state is a deterministic transition function:

$$S_{t+1} = \delta(S_t, A_t, V_t)$$

Where:
* $S_t$ is the current persisted state in `$STATE/state.json`.
* $A_t$ represents the structured file artifacts produced by subagents (`requirements.md`, `test-plan.md`, `review-findings.json`).
* $V_t$ represents deterministic shell quality gate verdicts written to `$STATE/gates/`.

```
[Start: Ticket Intake]
       │
       ▼
   preflight ──────────► [Missing Critical Tool] ──► HALT / Alert User
       │
       ▼
   jira-start (Assign ticket to runner & transition to 'In Progress')
       │
       ▼
   provision (Clone primary repository into throwaway workspace)
       │
       ▼
  requirements (Extract acceptance criteria & discover connected repos)
       │
       ▼
   test-plan (Produce multi-repo verification strategy)
       │
       ▼
    branch* (Create feature branches across all provisioned repos)
       │
       ▼
 ┌─────────────── DETERMINISTIC TDD QUALITY CYCLE ───────────────┐
 │                                                               │
 │  write-tests* (Author failing unit/integration tests)          │
 │       │                                                       │
 │       ▼                                                       │
 │  Red Gate ("gate-tests.sh --expect-fail")                     │
 │       │                                                       │
 │       ▼ [Must fail AND touch test files]                      │
 │  implement* (Author minimal production code to pass)          │
 │       │                                                       │
 │       ▼                                                       │
 │  Green Gate ("gate-tests.sh & gate-build.sh")                 │
 │                                                               │
 └───────────────────────────────┬───────────────────────────────┘
                                 │ [All Tests & Build Pass]
                                 ▼
 ┌────────────── ADVERSARIAL REVIEW & FIX LOOP ──────────────────┐
 │                                                               │
 │  review* (Opus reviews git diff against rubric)               │
 │       │                                                       │
 │       ▼                                                       │
 │  review-findings.json                                         │
 │       │                                                       │
 │       ├──► [Clean OR Minor findings at Cap] ──► Proceed       │
 │       │                                                       │
 │       ├──► [Blocking findings AND Iteration < 3]              │
 │       │         │                                             │
 │       │         ▼                                             │
 │       │    analyze* (Triage findings into fix-list.json)      │
 │       │         │                                             │
 │       │         ▼                                             │
 │       │    fixer* (Apply targeted patches)                    │
 │       │         │                                             │
 │       │         ▼                                             │
 │       │    Re-test via Green Gate ──► Loop to review          │
 │       │                                                       │
 │       └──► [Blocking findings AND Iteration >= 3]             │
 │                 │                                             │
 │                 ▼                                             │
 │            ESCALATE TO HUMAN (Halt pipeline)                  │
 └───────────────────────────────┬───────────────────────────────┘
                                 │
                                 ▼
    commit* (Author Conventional Commits with Co-Authored-By trailers)
       │
       ▼
  ticket-updates (Open GitHub PRs via gh, post Slack alert, transition Jira)
       │
       ▼
    cleanup (Optionally delete disposable clones; retain durable state)
       │
       ▼
    [Done]
```
*\* denotes stages that fan out across all repositories in multi-repo tickets.*

---

## 3. Data Protocols & Schema Contracts

All pipeline communications occur through disk-backed JSON files stored under `$STATE` (`~/.claude/autopilot/state/<TICKET>/`). Subagents receive explicit read-only or write-only boundaries.

### 3.1 `state.json` (Orchestrator Source of Truth)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "PipelineExecutionState",
  "type": "object",
  "required": ["ticket", "phase", "iteration", "max_iterations", "repos", "updated_at"],
  "properties": {
    "ticket": { "type": "string", "example": "PROJ-123" },
    "issue_type": { "type": "string", "enum": ["Story", "Bug", "Task", "Epic"] },
    "slug": { "type": "string", "example": "add-jwt-validation" },
    "jira_status": { "type": "string", "example": "In Review" },
    "slack_link": { "type": "string", "format": "uri" },
    "phase": {
      "type": "string",
      "enum": [
        "jira-start", "provision", "requirements", "test-plan",
        "branch", "write-tests", "implement", "review", "analyze",
        "fix", "commit", "ticket-updates", "cleanup", "done"
      ]
    },
    "iteration": { "type": "integer", "minimum": 0, "maximum": 3 },
    "max_iterations": { "type": "integer", "default": 3 },
    "updated_at": { "type": "string", "format": "date-time", "example": "2026-07-07T00:00:00Z" },
    "repos": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "role", "remote", "path", "stack", "branch"],
        "properties": {
          "name": { "type": "string", "example": "auth-service" },
          "role": { "type": "string", "enum": ["primary", "connected"] },
          "remote": { "type": "string", "example": "org/auth-service" },
          "path": { "type": "string" },
          "stack": { "type": "string", "enum": ["dotnet", "node", "python", "maven", "generic"] },
          "branch": { "type": "string", "example": "feature/PROJ-123-add-jwt-validation" },
          "branch_base": { "type": "string", "default": "main" },
          "gates": {
            "type": "object",
            "properties": {
              "tests": { "type": "string", "enum": ["pass", "fail", "skipped", "blocked"] },
              "build": { "type": "string", "enum": ["pass", "fail", "skipped", "blocked"] }
            }
          },
          "pr_url": { "type": ["string", "null"] }
        }
      }
    }
  }
}
```

### 3.2 `review-findings-<label>.json` (Adversarial Review Schema)

Written exclusively by the `code-reviewer` (Opus) per repository. The reviewer has zero code edit permissions.

```json
{
  "repo": "auth-service",
  "iteration": 0,
  "verdict": "BLOCKING | NON_BLOCKING | CLEAN",
  "findings": [
    {
      "id": "F1",
      "severity": "blocking | major | minor | nit",
      "file": "src/Auth/TokenValidator.cs",
      "line": 42,
      "summary": "JWT clock skew validation threshold is bypassed",
      "rationale": "Allows expired tokens to authenticate if clock skew exceeds 300s, violating security baseline.",
      "confidence": "high | med | low"
    }
  ]
}
```

### 3.3 `fix-list-<label>.json` (Triaged Fix Plan Schema)

Authored by the `review-analyst` (Sonnet) and consumed by the `fixer` (Sonnet). Translates review findings into actionable atomic edits.

```json
{
  "repo": "auth-service",
  "iteration": 0,
  "fixes": [
    {
      "finding_id": "F1",
      "accepted": true,
      "action": "Clamp ClockSkew parameter to maximum TimeSpan of 60 seconds in TokenValidationParameters",
      "files": ["src/Auth/TokenValidator.cs"],
      "reason_if_rejected": ""
    }
  ]
}
```

---

## 4. Deterministic Quality Gate Protocol

All software verification is anchored by shell scripts residing in `bin/`. Subagents are strictly evaluated on exit codes:

| Gate Script | Flag / Mode | Required Exit Code | Behavioral Invariant |
|---|---|---|---|
| `gate-build.sh` | Default | `0` | Compiler/transpiler must complete with zero errors. Warnings treated per project settings. |
| `gate-tests.sh` | `--expect-fail` | `0` (Under inverted logic) | Must return 0 **only if** test suite fails **AND** `git status --porcelain -uall` proves newly authored test files were touched (with `-uall` traversing untracked directories). Prevents vacuous test passes. |
| `gate-tests.sh` | Default | `0` | Full existing test suite plus new tests must pass completely (`100% green`). |
| `ensure-dotnet-restore.sh` | Automated fallback | `0` | Recovers from private NuGet/npm 401 feed failures using local machine package caches. If unrecoverable, exits with code `3` (`blocked`) to escalate to human. |

---

## 5. Asymmetric Subagent Hierarchy & Role Boundaries

To prevent LLMs from rubber-stamping errors, roles are partitioned into isolated contexts:

```
                  ┌───────────────────────────────┐
                  │   Orchestrator ("The Brain")  │
                  │   - Drives Finite State Machine│
                  │   - Zero Direct Code Changes  │
                  │   - Enforces 3-Iteration Cap  │
                  └───────────────┬───────────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│   Implementer    │    │ Adversarial Code │    │     Committer    │
│     (Sonnet)     │    │  Reviewer (Opus) │    │     (Sonnet)     │
├──────────────────┤    ├──────────────────┤    ├──────────────────┤
│• Writes code     │    │• Read-only code  │    │• Formats git PRs │
│• Runs TDD tests  │    │• Isolated context│    │• Conventional Msg│
│• Cannot self-    │    │• Writes findings │    │• Trailing Co-    │
│  approve PR      │    │  JSON only       │    │  Authored-By     │
└──────────────────┘    └──────────────────┘    └──────────────────┘
```

---

## 6. Convergence Guarantees & Loop Invariants

To avoid unbounded token expenditure or runaway agent behavior, the pipeline guarantees the following invariants:

1. **Deterministic Loop Termination:** The review-and-fix iteration loop is hard-capped at `max_iterations = 3`.
2. **Escalation Invariant:** If any `BLOCKING` finding persists at iteration 3, the pipeline **must halt immediately** and emit an escalation block to the human operator with diagnosis logs. It is forbidden to attempt iteration 4.
3. **Graceful Minor Finding Invariant:** If only `MINOR` or `STYLE` findings remain at iteration 3, the pipeline advances to `commit`, documenting surviving minor items directly in the GitHub PR description for human reviewers.
4. **Environment Failure Invariant:** An environment failure (such as missing cloud credentials or feed 401s) triggers exit code `3` (`blocked`), immediately halting execution and logging a `Decision: Escalate` record to `log.md` without consuming fix iterations.

---

## 7. Filesystem & Portability Invariants

```
~/.claude/autopilot/               <-- Root anchor ($AUTOPILOT_HOME)
├── config.json                    <-- Global user settings
├── state/                         <-- DURABLE OUTPUT (Never deleted automatically)
│   └── <TICKET>/
│       ├── state.json             <-- FSM current status & transition records
│       ├── requirements.md        <-- Distilled business requirements
│       ├── test-plan.md           <-- Multi-repo test strategy
│       ├── review-findings-*.json <-- Adversarial review audit trails
│       ├── fix-list-*.json        <-- Triaged patch lists
│       ├── gates/                 <-- Raw stdout/stderr & JSON gate verdicts
│       └── log.md                 <-- Append-only decision audit trail
└── work/                          <-- DISPOSABLE WORKSPACE (Can be wiped anytime)
    └── <TICKET>/
        └── repos/                 <-- Cloned Git repositories
            ├── service-api/
            └── client-web/
```

* **Durable vs. Disposable Separation:** No pipeline artifact is ever committed into the application source tree. The repo only contains authentic code and test diffs.
* **OS Independence:** Runs on POSIX Bash (native on macOS and Linux; via Git Bash or WSL2 on Windows).

---

## 8. Concurrency, Session Isolation & Resumption Guarantees

To ensure deterministic agent behavior and prevent state corruption across multi-ticket workflows, the pipeline enforces a three-tiered concurrency contract:

### 8.1 Single-Ticket Conversation Session Scope
A single conversation session is scoped to host one active ticket pipeline from intake to completion.
* **Context Bleed Prevention:** Sequential execution of multiple tickets within the same conversation window accumulates token bloat and risks cross-ticket AST hallucination.
* **Intake Guardrail:** If an orchestrator detects conversational history from a prior ticket run, it must pause and present a user confirmation prompt before continuing, advising the developer to reset context via `/clear` or open a fresh terminal.
* **Multi-Repo Coexistence:** A single ticket run may span multiple provisioned repositories (e.g. backend service, frontend client). The orchestrator coordinates all affected repositories within this single session, fanning out subagents per repository while maintaining isolation from previous tickets.

### 8.2 Multi-Terminal Cross-Ticket Parallelism
Distinct tickets (e.g., `PROJ-1001` and `PROJ-1002`) are **fully isolated by filesystem hierarchy**:
* Durable state is strictly partitioned under `$STATE/<TICKET>/`.
* Disposable Git workspaces are strictly partitioned under `$WORKSPACE/<TICKET>/repos/`.
* Separate tickets may run concurrently across independent terminal windows without locks or race conditions.

### 8.3 Same-Ticket Mutual Exclusion & Resumption
Concurrent execution of the **same ticket key** across multiple active sessions is undefined and prohibited. Sequential re-runs of the same ticket key act as an **idempotent pipeline resumption**, picking up execution directly from the phase recorded in `$STATE/<TICKET>/state.json`.

