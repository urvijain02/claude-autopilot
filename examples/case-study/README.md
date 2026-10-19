# Case Study: Autonomous Execution Transcript (PROJ-1001)

This directory contains a complete, frozen execution transcript from an autonomous run of **Claude Autopilot** on Golden Benchmark task **PROJ-1001** (*Boundary Regression Slicing in `sandbox-repo`*).

It documents the full lifecycle: requirement intake, TDD Red Gate verification, production implementation, adversarial code review, and prompt cache telemetry.

---

## Artifact Inspection Guide

| Artifact | Stage / Persona | What It Documents |
| :--- | :--- | :--- |
| [`ticket.md`](ticket.md) | **Input Intake** | Ingested bug report with 3 acceptance criteria, demonstrating support for offline local files and prompt fallback without external Jira/Slack dependencies. |
| [`requirements.md`](requirements.md) | **Requirements Analyst**<br>*(Claude Sonnet)* | Surgical pre-implementation boundary decomposition. Maps affected code sections and establishes acceptance criteria before code authoring begins. |
| [`test-plan.md`](test-plan.md) | **Test Planner**<br>*(Claude Sonnet)* | Formal TDD strategy classifying coverage into unit/integration tiers and establishing the inverted Red Gate sequence. |
| [`state.json`](state.json) | **Orchestrator**<br>*(RFC-001 Engine)* | Durable finite-state machine state memory backed by disk. Guarantees that interrupted runs can be safely resumed without losing context. |
| [`telemetry.json`](telemetry.json) | **AI Telemetry Engine**<br>*(RFC-002 Protocol)* | Machine-readable metrics capturing all 14 stages, stage durations ($T = \sum P_i = 52\text{s}$), and token economics (**84.5% prompt cache efficiency**). |
| [`review-findings-sandbox-repo.json`](review-findings-sandbox-repo.json) | **Adversarial Reviewer**<br>*(Claude Opus)* | Context-isolated code review: Opus operates in a fresh subagent context and flags a subtle negative-offset boundary bug missed by naive unit tests. |
| [`fix-list-sandbox-repo.json`](fix-list-sandbox-repo.json) | **Review Analyst**<br>*(Claude Sonnet)* | Structured triage decision translating Opus review findings into concrete, file-scoped remediation actions for the fixer. |
| [`gates/sandbox-repo/`](gates/sandbox-repo/) | **Quality Gates** | Machine-verifiable exit code verdicts ([`build.json`](gates/sandbox-repo/build.json), [`tests.json`](gates/sandbox-repo/tests.json)) and raw terminal execution streams ([`build.log`](gates/sandbox-repo/build.log), [`tests.log`](gates/sandbox-repo/tests.log)). |
| [`log.md`](log.md) | **Audit Logger** | Full append-only audit trail recording every phase decision, quality gate output, review findings, and the final CLI finish banner. |
| [`final-pr-diff.patch`](final-pr-diff.patch) | **Committer** | Clean, unified Git diff (+27, −5 across 2 files) demonstrating surgical precision, negative-offset clamping, and zero unnecessary code changes. |

---

## Key Architectural Highlights Evident in This Run

### 1. Un-Fakeable TDD Quality Gates
Notice in [`log.md`](log.md) that the pipeline executed `bin/gate-tests.sh --expect-fail` during the `write-tests` stage. The agent was strictly prohibited from generating production code until:
1. The new test in `test/paginate.test.js` failed against the unpatched codebase (exit code 1).
2. `git status --porcelain -uall` proved that a new test was actually authored on disk (`touched_a_test: true`).

This eliminates the primary failure mode of AI coding agents: hallucinating that non-existent tests passed.

### 2. Context-Isolated Adversarial Code Review
In Iteration 1, the implementer solved the stated ticket defect (exact multiple bug), and basic unit tests passed. However, the Opus auditor (running in an independent, fresh context window with zero implementer sycophancy) flagged [`FINDING-1`](review-findings-sandbox-repo.json):
> Passing `page: -1` evaluated to a negative start index (`-20`), causing `Array.prototype.slice()` to slice backwards from the end of the array rather than defaulting safely to page 1.

The orchestrator routed this finding through `review-analyst` into `fixer`, which clamped `Math.max(1, page)` and resolved the issue on Iteration 2.

### 3. Commercial AI Economics & Prompt Caching
As verified in [`telemetry.json`](telemetry.json):
* **84.5% Prompt Cache Hit Rate:** Exploits Anthropic's 5-minute sliding TTL server-side prompt cache across sequential subagents, reducing input token overhead by over 80%.
* **Durable Token Accounting:** Records exact input, output, cache read, and cache creation tokens in [`telemetry.json`](telemetry.json) across all 14 execution stages.

---

## How to Replicate This Run Locally

To execute this exact benchmark autonomously on your own machine:

```bash
# 1. Reset the sandbox repository to the broken defect state:
./bin/reset-sandbox.sh PROJ-1001

# 2. In your Claude Code session, launch the autonomous pipeline:
/autopilot:engage PROJ-1001 --file examples/sample-ticket-proj-1001.md
```
