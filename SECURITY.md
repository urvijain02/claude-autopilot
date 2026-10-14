# Security Policy & Agent Trust Model

## 1. Overview & Threat Model

`claude-autopilot` executes code, invokes build tools, and manages Git branches autonomously. Because SWE agents have shell execution capabilities, the architecture is designed with defense-in-depth principles to enforce strict security boundaries, prevent prompt injection escalations, and protect developer environments.

```
                      ┌──────────────────────────────────────┐
                      │        Autonomous Host Agent         │
                      └──────────────────┬───────────────────┘
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 ▼                                               ▼
   ┌───────────────────────────┐                   ┌───────────────────────────┐
   │    Isolated Workspace     │                   │   Persistent State Dir    │
   │  ~/.claude/autopilot/     │                   │   ~/.claude/autopilot/    │
   │     work/<TICKET>/        │                   │     state/<TICKET>/       │
   │ (Disposable throwaway     │                   │ (JSON schemas & logs only;│
   │  clones; scoped execution)│                   │  read/write by protocol)  │
   └───────────────────────────┘                   └───────────────────────────┘
```

---

## 2. Deterministic Guardrail Architecture & Sandboxing

### 2.1 Disposable Workspace Sandboxing
* All repository checkouts and builds are confined to disposable worktrees under `~/.claude/autopilot/work/<TICKET>/repos/<REPO>`.
* The orchestrator and subagents operate solely within this directory tree. They do not execute within your primary developer directories, preventing unintended modifications to local unstaged work or host configuration.
* Setting `cleanup_after_pr: true` automatically purges the workspace clones once pull requests are opened.

### 2.2 Asymmetric Permission Quarantining
* **Implementer (Sonnet):** Scoped strictly to repository source code edits and executing the test/build gate scripts. Has zero permission to mark review findings as resolved or advance pipeline stages directly.
* **Adversarial Reviewer (Opus):** Operates in a fresh, isolated context window with **zero code edit permissions**. Its output is restricted exclusively to writing structured findings to `$STATE/review-findings-<label>.json`. It cannot alter codebase files, preventing prompt injection attacks from malicious repository contents attempting to hijack the reviewer.
* **Orchestrator:** High-level coordinator that transitions state machine phases based strictly on disk-persisted state and gate output. Has zero direct code-edit rights.

### 2.3 Deterministic Verification (Zero Model Self-Grading)
* Subagents are never permitted to self-report build or test success in natural language prose.
* All verification is executed by deterministic shell scripts (`gate-tests.sh`, `gate-build.sh`) whose exit codes (`0` for pass, `1` for fail, `3` for blocked) govern state transitions.
* A compromised or hallucinating model cannot bypass a failing test suite.

### 2.4 Denial-of-Wallet & Infinite Loop Mitigation
* The review-fix cycle enforces a hard ceiling of `max_iterations = 3`.
* If blocking defects persist after three iterations, the pipeline automatically halts and triggers an `Escalate to Human` verdict. It never enters an unbounded execution loop that drains API credits or token budgets.

---

## 3. Secret & Credential Management

* **No Credentials in State Files:** Authentication tokens for GitHub (`gh`), Slack, and Atlassian Jira are never written to `$STATE/state.json` or committed to Git.
* **MCP Daemon Delegation:** API interactions with Jira and Slack are delegated to external Model Context Protocol (MCP) servers or CLI utilities authenticated on the host machine.
* **Private Feed Isolation:** Private package feeds (e.g. Azure DevOps Artifacts, GitHub Packages) rely on existing machine-level credentials or fallback to local package caches (`ensure-dotnet-restore.sh`). Secret tokens are never echoed to gate logs.
* **Adversarial Security Scanning:** The review rubric (`skills/review-rubric/SKILL.md`) explicitly inspects all incoming diff hunks for hardcoded secrets, tokens, API keys, and unsafe deserialization patterns before any branch is committed.
