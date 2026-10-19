# Claude Autopilot: Model-Agnostic Autonomous SWE-Agent Pipeline

[![CI](https://github.com/urvijain02/claude-autopilot/actions/workflows/ci.yml/badge.svg)](https://github.com/urvijain02/claude-autopilot/actions/workflows/ci.yml)
[![Architecture: Model-Agnostic](https://img.shields.io/badge/Architecture-Model--Agnostic-blueviolet)](#-is-this-locked-into-anthropics-claude-ecosystem)
[![Verification: Deterministic TDD](https://img.shields.io/badge/Verification-Deterministic_TDD-green)](#two-kinds-of-gate-dont-confuse-them)
[![Platform: Claude Code | Universal](https://img.shields.io/badge/Platform-Claude_Code_%7C_Universal-blue)](#architecture--state-machine)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<p align="center">
  <img src="docs/demo.svg" alt="Claude Autopilot SWE-Agent Terminal Demo" width="100%">
</p>

Takes a Jira ticket or GitHub issue through to open pull requests without supervision.

Failing tests are written before the production change, stage outcomes are decided by shell scripts rather than by the model reading its own work, and the review is done by a separate agent on a stronger model tier than the one that wrote the code — then looped through analyze and fix. At the iteration cap it escalates if anything blocking survives, and ships with the leftovers recorded if only minor findings remain.

It works across several repos in one run, clones what it needs into a throwaway workspace (nothing has to be checked out beforehand), and picks up where it left off if a run is interrupted.

---

## ⚡ Quickstart: Dual-Tier Evaluation Harness (Zero Setup)

You can evaluate the pipeline and deterministic quality gates locally without external Jira credentials or third-party repositories:

### Tier 1: Offline Gate & Invariant Harness Verification (< 5 Seconds)

Runs offline with zero external dependencies to verify that the target repository unit tests, POSIX quality gates (`gate-build.sh`, `gate-tests.sh`), and central state logging are fully operational:

```bash
# Clone the repository
git clone https://github.com/urvijain02/claude-autopilot.git
cd claude-autopilot

# Run Tier 1 evaluation harness (auto-detected engine: jq → python3 → node):
./bin/run-evals.sh

# Or explicitly verify under specific engine fallbacks:
AUTOPILOT_JSON_ENGINE=python3 ./bin/run-evals.sh
AUTOPILOT_JSON_ENGINE=node    ./bin/run-evals.sh
AUTOPILOT_JSON_ENGINE=jq      ./bin/run-evals.sh
```

### Tier 2: Live Autonomous Agent Evaluation

Stage a benchmark task in its initial broken state, then launch Claude Autopilot to watch the agent autonomously write the failing test (Red Gate), implement the fix (Green Gate), and complete the review loop:

```bash
# 1. Stage the broken defect (e.g. PROJ-1001 boundary slicing bug):
./bin/reset-sandbox.sh PROJ-1001

# 2. In your Claude Code session, launch the autonomous pipeline:
/autopilot:engage PROJ-1001 --file examples/sample-ticket-proj-1001.md

# 3. Restore all sandboxes to clean reference state when finished:
./bin/reset-sandbox.sh clean
```

> **What this executes:** Benchmarks the 3 Golden Benchmark tasks (`PROJ-1001` boundary slicing, `PROJ-1002` auth token clock-skew invariant, and `PROJ-1003` multi-repo contract coordination) against bundled sandboxes using native `node:test`, executing real `gate-build.sh` and `gate-tests.sh` quality gates and asserting un-fakeable central JSON verdicts. See [RFC-002: Evaluation Protocol](docs/EVALS.md).

### Tier 3: Zero-Install Case Study Walkthrough

Want to inspect authentic, un-fakeable run artifacts without cloning or running locally? Browse the complete, frozen execution transcript in [`examples/case-study/`](examples/case-study/):
* [`log.md`](examples/case-study/log.md) — Complete 14-stage append-only execution log with stage elapsed times, decisions, and quality gate outputs.
* [`requirements.md`](examples/case-study/requirements.md) & [`test-plan.md`](examples/case-study/test-plan.md) — Pre-implementation engineering plans authored by Claude Sonnet.
* [`review-findings-sandbox-repo.json`](examples/case-study/review-findings-sandbox-repo.json) — Real adversarial review finding flagged by Claude Opus catching negative-index array slicing.
* [`fix-list-sandbox-repo.json`](examples/case-study/fix-list-sandbox-repo.json) — Structured Review Analyst remediation decisions translating findings into fixer actions.
* [`gates/sandbox-repo/`](examples/case-study/gates/sandbox-repo/) — Verifiable exit-code JSON payloads ([`build.json`](examples/case-study/gates/sandbox-repo/build.json), [`tests.json`](examples/case-study/gates/sandbox-repo/tests.json)) and raw terminal execution streams ([`build.log`](examples/case-study/gates/sandbox-repo/build.log), [`tests.log`](examples/case-study/gates/sandbox-repo/tests.log)).
* [`telemetry.json`](examples/case-study/telemetry.json) — AI token accounting and stage latencies (**84.5% prompt cache efficiency**, $0.14 execution cost).
* [`final-pr-diff.patch`](examples/case-study/final-pr-diff.patch) — Surgical patch (+27, −5 across 2 files) resolving both boundary defect and negative page clamping.

---

## Architecture & State Machine

The pipeline operates as an explicit finite-state machine backed by disk-persisted state (`$STATE/state.json`), ensuring crash resilience and resumability. For formal JSON schemas, convergence guarantees, and quality gate contracts, see the [System Architecture Specification (RFC-001)](docs/SPECIFICATION.md).

```mermaid
flowchart TD
    subgraph Top_Row ["Preparation & Verification"]
        direction LR
        subgraph Plan_Phase ["1. Ingestion and Planning"]
            direction TB
            Start(["/autopilot:engage PROJ-123"]) --> Preflight{"Preflight Check"}
            Preflight -->|Verified| Provision["Provision Workspace"]
            Provision --> Req["Requirements Analyst"]
            Req --> Plan["Test Planner"]
            Plan --> Branch["Feature Branch*"]
        end

        subgraph TDD_Phase ["2. Deterministic TDD Quality Gates"]
            direction TB
            WriteTests["Test Writer* (Sonnet)"] --> RedGate{"gate-tests.sh<br/>--expect-fail"}
            RedGate -->|Red Pass| Implement["Implementer* (Sonnet)"]
            Implement --> GreenGate{"gate-tests.sh + gate-build.sh"}
        end
    end

    subgraph Review_Phase ["3. Adversarial Review and Delivery"]
        %% Delivery flow on the left
        Review["Adversarial Reviewer* (Opus)"] -->|Clean or Minor at Cap| Commit["Committer* Subagent"]
        Commit --> Ship["Open GitHub PR via gh"]
        Ship --> Updates["Ticket and Slack Updates"]
        Updates --> Done(["Pipeline Complete"])

        %% Escalation
        Review -->|Blocking at Cap| Escalate["Escalate to Human"]

        %% Fix Loop on the right (directly aligned with GreenGate)
        Review -->|Findings| Findings["review-findings-&lt;label&gt;.json*"]
        Findings --> Triage["Review Analyst*"]
        Triage --> Fixer["Targeted Fixer*"]
    end

    Branch --> WriteTests
    GreenGate -->|"All Tests and Build Pass"| Review
    Fixer -->|"Retest Gates (Loop Cap: 3)"| GreenGate
```

> [!NOTE]
> **Multi-Repo Fan-Out (`*`):** Stages marked with an asterisk (`*`) automatically fan out per repository recorded in `state.json.repos[]`. Each repository executes isolated quality gates and review passes, while coordinating against the shared test plan in `$STATE/test-plan.md`.

### Multi-Repo Coordination Architecture

Real-world engineering tickets frequently span multiple repositories (e.g. updating a schema or API contract in a backend microservice, then updating client callers and frontend components in dependent repositories). Claude Autopilot coordinates this atomically without pre-cloning:

* **Dynamic Dependency Discovery:** The `requirements-analyst` inspects ticket specifications and detects connected repositories without requiring hardcoded repository mappings.
* **Isolated Clones, Unified Plan:** Each repository is cloned into an isolated disposable workspace (`~/.claude/autopilot/work/<TICKET>/repos/<REPO>`). Subagents author code independently in each repository, but coordinate contract boundaries against a shared multi-repo plan (`$STATE/test-plan.md`).
* **Atomic Cross-Linked Pull Requests:** When quality gates pass across all affected repositories, the `committer` subagent authors conventional commits per repo, opens individual PRs, and cross-links sibling PR URLs in each PR description for synchronized team reviews.

### Asymmetric Subagent Hierarchy & Context Isolation

To eliminate LLM sycophancy (models rubber-stamping their own mistakes), the authoring and review roles are strictly decoupled into isolated contexts across asymmetric model tiers:

```mermaid
flowchart LR
    Orchestrator["Orchestrator (The Brain)\n• Drives State Machine\n• Zero Direct Code Edits\n• Enforces 3-Loop Cap"]
    
    Orchestrator --> Req["Requirements Analyst\n(Sonnet - Read Only)"]
    Orchestrator --> Plan["Test Planner\n(Sonnet - Multi-Repo)"]
    Orchestrator --> Writer["Test Writer\n(Sonnet - Red Tests)"]
    Orchestrator --> Impl["Implementer\n(Sonnet - Green Code)"]
    Orchestrator --> Reviewer["Adversarial Reviewer\n(Opus - Isolated Context)"]
    Orchestrator --> Analyst["Review Analyst\n(Sonnet - Triage)"]
    Orchestrator --> Fixer["Fixer\n(Sonnet - Targeted Fixes)"]
    Orchestrator --> Commit["Committer\n(Sonnet - Git/PR)"]

    Impl -.-> Gate1["gate-tests.sh\n(Deterministic Shell)"]
    Writer -.-> Gate2["gate-tests.sh --expect-fail\n(TDD Red Verification)"]
    Reviewer -.-> Schema["review-findings.json\n(Write-Only Permissions)"]
```

* **Context Boundaries & Multi-Repo Coexistence:** The orchestrator runs in your primary Claude Code session, managing the state machine across all connected repositories for that ticket. When stages fan out (`*`), subagents are launched in clean, isolated contexts per repository. Between different ticket runs, running `/clear` resets the primary conversation to maintain clean context hygiene.

### Token Economics & Server-Side Prompt Caching

Running an autonomous multi-agent pipeline (orchestrator + specialized subagents executing 12–16 sequential invocations per ticket) would be too expensive to run at scale without prompt caching. Claude Autopilot is architected specifically around **Anthropic server-side prompt caching** and **asymmetric model tiering**:

| Execution Stage | Model Tier | Primary Function | Cache Hit Ratio | Input Cache Savings |
| :--- | :--- | :--- | :---: | :---: |
| **Requirements & Test Plan** | Claude Sonnet | Ingestion & contract design | ~20% (Initial load) | Baseline (Cold cache) |
| **TDD Red & Green Cycle** | Claude Sonnet | Test writing & implementation | **> 90% (Cached repo & tools)** | **~90% reduction** |
| **Adversarial Review** | Claude Opus | Isolated, zero-context safety audit | **> 85% (Cached codebase & spec)** | **~85% reduction** |
| **Triage & Targeted Fixes** | Claude Sonnet | Fix extraction & re-gate loop | **> 90% (Cached context)** | **~90% reduction** |
| **Total Typical Run** | *Asymmetric Pipeline* | *Complete ticket to open PR* | **~82% Blended Cache Rate** | **~80%+ net input reduction** |

#### Why Prompt Caching Excels in Claude Autopilot
* **5-Minute Server-Side TTL Exploitation:** Anthropic's KV cache operates on a sliding 5-minute window per model prefix. Because a standard ticket run executes all subagent phases sequentially within 90–150 seconds, each subagent invocation hits the active server-side cache, resetting the TTL and amortizing repository and instruction overhead across the run.
* **The "Bookend" Model Strategy:** High-cost frontier reasoning (Claude Opus) is quarantined strictly to the Adversarial Reviewer where deep boundary analysis matters most. High-volume iterative coding and triage remain on Claude Sonnet, delivering Opus-grade safety at Sonnet-grade cost while eliminating full-pipeline Opus expense.
* **Zero Session Leakage:** Subagents operate with clean context boundaries per invocation, preventing conversation bloat while automatically inheriting cached prompt prefixes and repository trees.

---

## 🛠️ Supported Target Languages & Tech Stacks

Claude Autopilot is designed to write code and verify tests across any programming language. Stack detection and deterministic gates are handled by modular POSIX scripts in `bin/`:

| Ecosystem / Stack | Detection Manifest | Deterministic Build Gate | Deterministic Test Gate | Out-of-the-Box Status |
| :--- | :--- | :--- | :--- | :---: |
| **Node.js / TypeScript** | `package.json` | `npm run build` / `typecheck` / `tsc` | `npm test` (native `node:test`, Jest, Vitest, Mocha) | ✅ **Shipped** |
| **.NET (C# / F#)** | `*.sln`, `*.slnx`, `*.csproj` | `dotnet build` | `dotnet test` (with offline feed fallback) | ✅ **Shipped** |
| **Python** | `pyproject.toml`, `requirements.txt` | `python -m py_compile` | `pytest` | ⚡ *Easily extensible (see [Guide](CONTRIBUTING.md#3-extending-language-support-for-target-repositories-eg-rust-go-python))* |
| **Rust** | `Cargo.toml` | `cargo check --tests` | `cargo test` | ⚡ *Easily extensible (see [Guide](CONTRIBUTING.md#3-extending-language-support-for-target-repositories-eg-rust-go-python))* |
| **Go** | `go.mod` | `go build ./...` | `go test ./...` | ⚡ *Easily extensible (see [Guide](CONTRIBUTING.md#3-extending-language-support-for-target-repositories-eg-rust-go-python))* |

> **Extending to New Stacks:** Adding support for any compiled or interpreted language requires only adding a `case` statement to `bin/detect-stack.sh`, `bin/gate-build.sh`, and `bin/gate-tests.sh`. See the [Contributor Walkthrough](CONTRIBUTING.md#3-extending-language-support-for-target-repositories-eg-rust-go-python).

---

## ❓ Is this locked into Anthropic's Claude ecosystem?

**No at the architecture level; Yes for the ready-to-run plugin distribution.**

* **The 1-Click Plugin (Today):** Distributed natively for Claude Code. It is tuned specifically for Anthropic's Claude Sonnet and Claude Opus to leverage Claude Code's native tool execution, workspace subagents, and 5-minute server-side prompt caching (reducing repetitive input token overhead by ~80%+).
* **The Architecture & Protocol (Universal):** The underlying engine has zero vendor lock-in and can be driven by any model or autonomous agent framework:
  1. **Un-fakeable Shell Gates:** All build and test verdicts come from deterministic shell scripts (`gate-tests.sh`, `gate-build.sh`), not model self-reporting. The model cannot hallucinate or argue past failing exit codes.
  2. **Standardized JSON State Protocol:** The orchestrator communicates via vendor-neutral JSON schemas (`state.json`, `review-findings.json`, `fix-list.json`). Any frontier model—OpenAI (GPT-4o/o3), Google Gemini, DeepSeek, or local open-weights models (Ollama/vLLM)—can drive the subagent briefings.
  3. **Universal Loop Design:** The state machine is designed to transcribe directly into a standalone TypeScript or Python agent loop (`while state.phase !== 'done'`).
     <details>
     <summary><b>View Universal Loop Implementation (TypeScript / Python)</b></summary>

     ```typescript
     // Standalone TypeScript/Python loop over disk-persisted state
     while (state.phase !== 'done' && state.phase !== 'escalated') {
       const subagent = getSubagentForPhase(state.phase);
       await subagent.execute(state);
       
       // Gate verdicts decide transition — zero model self-grading:
       state = await reloadStateFromDisk(stateDir);
     }
     ```
     </details>

---

## Install

```bash
/plugin marketplace add urvijain02/claude-autopilot
```

```bash
/plugin install autopilot@claude-autopilot
```

Restart Claude Code afterwards. On the next start, `~/.claude/autopilot/config.json` is created for you from the shipped template.

## Requirements

| Need | Missing means |
|---|---|
| `gh`, authenticated | **Critical** — no cloning private repos, no PRs |
| `git` | **Critical** — no branches or commits |
| An Atlassian MCP — the standalone server or the claude.ai connector | Jira steps skip: the ticket isn't assigned or moved |
| Slack MCP | The PR-link post skips |
| `jq` **or** `python3` | Optional. Only needed to read `state_root` / `workspace_root` out of your config when the value isn't a plain one-line string. With neither installed and such a value set, the scripts stop rather than silently write gate output somewhere the pipeline won't read it. |

`preflight` checks the first four before anything else runs and tells you exactly what will be skipped, so a missing tool surfaces up front rather than three stages in.

**Cross-Platform Support:** Runs natively on macOS and Linux (via `/bin/bash`). On Windows, runs through Git Bash (bundled with Git for Windows) or WSL. While distributed as a 1-click plugin for Claude Code, the state protocol and shell gates are model-agnostic and can be orchestrated by any frontier model or autonomous agent framework.

## Use it

```bash
/autopilot:engage PROJ-123
```

It also answers to plain requests — "run autopilot on PROJ-123", "engage autopilot on PROJ-123".

Re-running on a ticket already underway **resumes** it from `state.json` rather than starting over:

```text
/autopilot:engage PROJ-123                  resume, or start if it's new
/autopilot:engage PROJ-123 --from review    redo from a named phase
/autopilot:engage PROJ-123 --restart        start over (asks first; archives the old run)
/autopilot:engage PROJ-123 --prompt "..."   run from inline prompt string (zero Jira dependency)
/autopilot:engage PROJ-123 --file <path>    run from local markdown file (zero Jira dependency)
/autopilot:engage DEMO                      1-click quickstart: runs PROJ-1001 on bundled sandbox repo
/autopilot:engage                           list every run that isn't finished
```

One invocation carries the ticket all the way to open PRs — it doesn't stop to ask you to approve anything. If the session dies partway, nothing is lost: state is on disk after every transition, so running the same command again picks up where it stopped.

> 💡 **Tip:** Run `/clear` between different tickets to start with a fresh conversation context.

### Two kinds of gate, don't confuse them

"Unsupervised" means nobody is asked to click approve. It does not mean unchecked.

- **Quality gates** — tests and build, run by shell scripts that write `pass`/`fail` to disk. The orchestrator has to read those files before it advances. Always on, not configurable, and the reason the run can be trusted without you watching it.
- **Human gates** — the pauses for you to approve a plan or sign off before commit. Off by default. Set `human_gates: true` in your config if you'd rather it stop and wait at those points.

## Configuration & Workspace Management

**Nothing is strictly required** — the pipeline runs out-of-the-box with zero configuration needed.

<details>
<summary><b>⚙️ View Advanced Settings & Workspace Relocation</b></summary>

### Configuration Options (`~/.claude/autopilot/config.json`)

The config file is created automatically on first run.

| Key | Ships as | What it does |
|---|---|---|
| `slack_channel` | *empty* | Channel id (`C0…`) the PR links get posted to. Empty means the post is skipped and logged. |
| `jira_site` | *empty* | Optional. Host for Atlassian Cloud (e.g. `your-team.atlassian.net`). If empty, Jira transitions skip and prompt-mode applies. |
| `human_gates` | `false` | `true` pauses for plan approval and pre-commit sign-off. No effect on the quality gates — see *Two kinds of gate*. |
| `cleanup_after_pr` | `false` | `true` deletes a ticket's clones once its PRs are open. A run's output under `state_root` is kept either way. |
| `default_base_branch` | `main` | Base branch to branch from when the ticket doesn't imply one. |
| `state_root` | `~/.claude/autopilot/state` | Where a run's durable output lands. Point it somewhere browsable if you'd rather read runs outside `~/.claude`. A value containing a quote or backslash needs `jq` or `python3` — see *Requirements*. |
| `workspace_root` | `~/.claude/autopilot/work` | Where the throwaway clones go. Move it if the repos you work on are large. |
| `orgs` | `[]` | Optional. GitHub orgs or username searched to resolve a connected repo that analysis names. Empty means you're always asked for the link. Bare `owner/repo` is GitHub-only; Bitbucket needs a full URL. |
| `auto_expand_connected` | `false` | `true` clones connected repos without confirming each one first. |
| `jira_transitions` | `{}` | Fills itself in. The first time a project's in-progress or in-review status can't be matched automatically you're asked once, and the answer is cached per project key. |

### Where Things Live

| Path | Description |
|---|---|
| The plugin's own scripts | inside the installed plugin — you never need this path |
| `~/.claude/autopilot/config.json` | your settings |
| `~/.claude/autopilot/state/<TICKET>/` | a run's output: spec, test plan, findings, gate verdicts, `log.md` |
| `~/.claude/autopilot/work/<TICKET>/repos/` | the throwaway clones |

Those paths are defaults. `state_root` and `workspace_root` in your config move the last two, and the `AUTOPILOT_HOME` environment variable moves all of it at once — it's the anchor the rest hang off, resolved in one place (`bin/_paths.sh`).

To relocate the root workspace and config:

```bash
# macOS / Linux (in ~/.bashrc or ~/.zshrc)
export AUTOPILOT_HOME="$HOME/.custom-autopilot"

# Windows (in PowerShell profile or Environment Variables)
$env:AUTOPILOT_HOME = "D:/autopilot"
```

</details>

## Reading a run

The session output is deliberately thin — one line per stage and a summary block at the end. Everything else is on disk under `state_root/<TICKET>/`: `requirements.md`, `test-plan.md`, `review-findings-*.json`, `fix-list-*.json`, the gate verdicts under `gates/`, and `log.md`, which carries every decision the run made along with why and what it rejected.

## Documentation & Community

* [System Architecture Specification (RFC-001)](docs/SPECIFICATION.md) — State machine mechanics, JSON schemas, quality gate contracts, and loop guarantees.
* [Evaluation Protocol & Benchmarks (RFC-002)](docs/EVALS.md) — Quantitative evaluation methodology, Pass@1 / Pass@3 metrics, and the 3 Golden Benchmark tasks.
* [Security Policy & Trust Model](SECURITY.md) — Agent workspace sandboxing, permission quarantining, and deterministic guardrail layers.
* [Contributor Guide](CONTRIBUTING.md) — Local development setup, stack extensibility walkthrough, and subagent prompt standards.
* [Changelog](CHANGELOG.md) — Release notes and version history.

## Citation & Attribution

If this autonomous architecture, TDD quality gate design, or state-protocol informs your research, engineering projects, or agent pipelines, please attribute the work:

```bibtex
@software{jain2026claudeautopilot,
  author = {Urvi Jain},
  title = {Claude Autopilot: Autonomous SWE-Agent Pipeline with Deterministic TDD Quality Gates},
  year = {2026},
  publisher = {GitHub},
  journal = {GitHub repository},
  howpublished = {\url{https://github.com/urvijain02/claude-autopilot}}
}
```

Or reference in markdown:
> **Claude Autopilot** by [Urvi Jain](https://github.com/urvijain02) — [github.com/urvijain02/claude-autopilot](https://github.com/urvijain02/claude-autopilot)

## Maintainer

[Urvi Jain](https://github.com/urvijain02). Open an issue on this repo for bugs, or send a PR.
