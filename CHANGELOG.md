# Changelog

All notable changes to **Claude Autopilot** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-10-19

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

---

### Phase 4: AI Telemetry & Token Economics

#### Added
* **Deterministic AI Telemetry Engine (`bin/record-telemetry.sh`):** Standalone, zero-overhead telemetry recording engine computing phase and stage latencies from `.marks` timestamps, calculating prompt cache efficiency %, and atomically updating `$STATE/<TICKET>/telemetry.json` with zero LLM API token overhead.
* **Formal Telemetry State Contract (RFC-001 Section 3.4):** Decoupled `$STATE/<TICKET>/telemetry.json` schema contract covering model allocation, granular stage timings across 14 canonical stages, durable token ground truth, and macro-phase timing rollups (`plan_and_setup`, `tdd_and_gates`, `review_and_delivery`).
* **Centralized Multi-Engine JSON Resolver:** Universal JSON parser resolution in `bin/_paths.sh` implementing strict `jq` → `python3` → `python` → `node` → `none` fallback precedence for zero-dependency CLI environments.
* **High-Signal Presentation Layer:** Integrated `telemetry` (macro-phase breakdown) and `tokens` (prompt cache efficiency %) rows into orchestrator finish banners in `skills/reporting/SKILL.md` and `skills/engage/SKILL.md`.
* **Structured Token Economics Audit Log:** Formatted `## AI Telemetry & Token Economics` markdown audit table automatically appended to `$STATE/<TICKET>/log.md` mapping macro phases to constituent pipeline stages.
* **Mathematical Invariant Verifier:** Enhanced `bin/run-evals.sh` with `verify_telemetry_invariants()` asserting prompt cache hit rate mathematical precision and phase duration sum invariant ($T = \sum P_i$) across all golden benchmarks.

#### Fixed & Hardened
* **Windows Node.js Path & Binary Discovery:** Resolved cross-platform runtime disparities in `bin/gate-build.sh` and `bin/run-evals.sh` via `node.exe` fallback discovery and POSIX-to-Windows path normalization (`wslpath -m`), enabling deterministic gate and telemetry execution on Windows hosts.
* **Token Invariant Schema Synchronization:** Synchronized Section 3.4 of `docs/SPECIFICATION.md` and `skills/state-protocol/SKILL.md` with column-aligned comments and exact 14 canonical stages mapping dictionary.

---

### Phase 5: Cross-Platform & Developer Ergonomics

#### Added
* **Automated 3-OS Continuous Integration Matrix (`.github/workflows/ci.yml`):** Parallel GitHub Actions workflow matrix validating POSIX linting, plugin manifest schemas, and Tier 1 Golden Benchmark evaluations across `ubuntu-latest`, `macos-latest`, and `windows-latest`.
* **Multi-Engine In-Matrix Fallback Verification:** Automated CI loop on Ubuntu asserting functional equivalence and deterministic state persistence across `jq`, `python3`, and `node` fallback JSON engines.
* **Workflow Concurrency & Least Privilege Security:** Top-level `permissions: contents: read` enforcement and PR-scoped `cancel-in-progress` concurrency grouping to eliminate stale runner queue congestion.
* **Live Repository Status Badge:** Embedded CI status badge in `README.md` linked to the multi-platform test pipeline.
* **Formal Branch Protection Contract:** Documented 4 required CI status checks and protected `main` branch policy in `CONTRIBUTING.md`.

#### Fixed & Hardened
* **POSIX Portability & Zero-Warning ShellCheck Compliance:** Refactored all scripts in `bin/` to achieve zero warnings at `--severity=warning` under native ShellCheck (resolved SC2034, SC2155 variable masking, shadowed identifiers, and subshell quoting).
* **Cross-Platform Engine Whitelisting & Fail-Closed Guard:** Enforced whitelist filtering (`jq|python3|python|node|node.exe`) in `bin/_paths.sh` and implemented fail-closed fatal error branches in `bin/record-telemetry.sh`.
* **Dual-Mode Path Resolver Dispatcher:** Enabled direct CLI execution of `bin/_paths.sh` (`resolve_json_engine`, `resolve_state_root`, `resolve_workspace_root`) alongside native sourcing support.
* **Deterministic Platform & Preflight Probing:** Standardized host platform classification on `uname -s` pattern-matching (`MINGW*|MSYS*|CYGWIN*`), eliminated `$OSTYPE` subshell fragility, added 1-click package manager install recommendations for `git`, and decoupled contextual `gh auth` remote checks from offline sandbox evaluation modes (`DEMO`, `--file`, `--prompt`).

---

### Phase 6: Showcase Artifacts & Case Study

#### Added
* **Animated Terminal SVG Demo (`docs/demo.svg`):** Self-contained, lightweight animated SVG terminal recording embedded in `README.md` demonstrating sandbox staging, TDD Red Gate failure, Green Gate pass, adversarial code review, and completion telemetry with zero external video dependencies.
* **Execution Case Study (`examples/case-study/`):** Complete, reproducible execution transcript on `PROJ-1001` (Boundary Regression Slicing) adhering to RFC-001 State Protocol, capturing the full ticket-to-PR lifecycle across requirement intake, TDD Red Gate verification, green implementation, adversarial review triage, and prompt cache telemetry.
* **Developer Hygiene Rules (`.gitignore`):** Appended common developer configuration ignores (`.env*`, `.vscode/`, `.idea/`, `*.swp`) to prevent accidental credential and editor metadata leakage.

#### Fixed & Hardened
* **State Protocol Harmonization:** Standardized review findings naming to `review-findings-<label>.json` with iteration tracking, and standardized the execution log to the protocol-mandated `log.md` schema.
* **Benchmark Invariant Alignment:** Synchronized `examples/.golden/staged-proj-1001/` and reference test suites with `docs/EVALS.md` (§2.3 & §3.1) formalizing the dual role of `PROJ-1001` as both a clean baseline evaluation and a full review-fix cycle case study.
