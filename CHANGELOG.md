# Changelog

All notable changes to **Claude Autopilot** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Phase 1: Autonomous Pipeline Core & State Architecture

#### Added
* **Autonomous SWE Pipeline:** 3-phase state machine orchestrating ticket intake, deterministic TDD implementation, and adversarial review-and-fix iterations.
* **Deterministic Quality Gates:** External POSIX Bash gates (`gate-tests.sh`, `gate-build.sh`) validating compiler and test verdicts with zero model self-grading.
* **Asymmetric Context Isolation:** Decoupled authoring and review roles using asymmetric model tiers (Sonnet implementer vs. Opus adversarial reviewer).
* **Multi-Repo Coordination Architecture:** Dynamic repository discovery, isolated workspace clones, unified cross-repo test planning, and atomic cross-linked PRs.
* **Crash-Resilient State Protocol:** Disk-persisted execution state in `$STATE/state.json` allowing uninterrupted pipeline resumption across sessions.
* **Private Feed Resilience:** Automatic offline package cache fallback and environment failure escalation for protected NuGet/npm package registries.

---

### Phase 2: Protocol Specification (RFC-001) & System Guardrails

#### Added
* **Formal Architecture Specification (RFC-001):** Complete protocol specification in `docs/SPECIFICATION.md` detailing state transitions, JSON schemas, gate contracts, and convergence proofs.
* **5-Layer Security Guardrail Suite:** Comprehensive Security Policy (`SECURITY.md`) detailing the 5-layer defence-in-depth model (path validation, secret exclusion, read-only reviews, fail-closed gates, human approval).
* **Community Suite & Visual Diagrams:** Contributor Guide (`CONTRIBUTING.md`), high-signal Mermaid architectural flowcharts, state transitions, and quality gate sequence diagrams.

---

### Phase 3: Zero-Dependency Quickstart, Native Sandboxes & Dual-Tier Evals

#### Added
* **Zero-Dependency Quickstart & Demo Mode:** Local ticket intake (`--file`), direct prompt intake (`--prompt`), and 1-click `/autopilot:engage DEMO` mode without requiring external Jira credentials.
* **Native Node.js Evaluation Sandbox Repositories:** Self-contained target repository (`examples/sandbox-repo/`) and consumer client repository (`examples/sandbox-client/`) utilizing native `node:test` and zero external npm dependencies.
* **Golden Benchmark Tasks:** Reference implementations and staged defect suites for `PROJ-1001` (boundary slicing), `PROJ-1002` (token clock skew invariant), and `PROJ-1003` (multi-repo schema contract).
* **Dual-Tier SWE-Agent Evaluation Protocol (RFC-002):** Formal specification in `docs/EVALS.md` defining Tier 1 Harness Invariant Checks and Tier 2 Autonomous Agent Benchmark evaluation.
* **Benchmark Harness & Task Reset Utilities:** Standalone runner `bin/run-evals.sh` executing real quality gates and verifying central JSON state, with `bin/reset-sandbox.sh` to stage broken defect states for live agent evaluation.

#### Fixed & Hardened
* **Deterministic Gate Hardening:** Boundary-aware test pattern regex in `bin/gate-tests.sh` preventing non-test source files from spoofing the Red Gate, and `_safe_path` sanitization for workspace directories in `bin/gate-build.sh`.
* **TDD Red Gate Directory Traversal:** Added `-uall` flag to `bin/gate-tests.sh` to ensure newly authored untracked test directories are fully traversed.
* **Cross-Platform Path Normalization:** Automatic Windows backslash-to-slash normalization in `bin/_paths.sh` supporting `$env:AUTOPILOT_HOME` and Windows environment paths out of the box.
* **Raw JSON Schema Invariant:** Universal protocol rule in `skills/state-protocol/` and reviewer agent personas prohibiting markdown code block fences (` ```json `) to guarantee deterministic JSON parsing.
* **Agent State Machine & Model Alignment:** Standardized `agents/review-analyst.md` to Sonnet model tier and aligned `agents/test-planner.md` state machine phase transition to `"branch"`.
* **Session Context Isolation Guardrail:** Enforced single-ticket conversation scope in `skills/engage/SKILL.md` with prompt-and-pause user confirmation if prior ticket context is detected, and formalized the three-tier concurrency/resumption model in RFC-001 Section 8.

