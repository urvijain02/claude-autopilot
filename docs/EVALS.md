# SWE-Agent Evaluation & Benchmark Protocol: Claude Autopilot
**RFC-002: Autonomous Engineering Evaluation Harness & Metrics**  
**Author:** Urvi Jain ([@urvijain02](https://github.com/urvijain02))  
**Status:** Living Specification / Production Standard  
**Revision:** 1.0.0  

---

## 1. Executive Summary & Evaluation Philosophy

Evaluating autonomous software engineering (SWE) agents requires fundamentally different rigor than grading conversational chatbots. While static benchmarks (e.g. HumanEval, MBPP) test isolated function completion in-memory, real-world SWE agents must navigate multi-step file manipulation, build failures, compiler errors, adversarial review passes, and cross-repo coordination.

`claude-autopilot` defines an empirical, three-pillar evaluation framework designed to benchmark agent performance under deterministic production conditions:

```
                          ┌─────────────────────────────────────┐
                          │     Autonomous Evaluation Suite     │
                          └──────────────────┬──────────────────┘
                                             │
      ┌──────────────────────────────────────┼──────────────────────────────────────┐
      ▼                                      ▼                                      ▼
┌───────────────────────────┐  ┌───────────────────────────┐  ┌───────────────────────────┐
│  Deterministic Resolution │  │     Adversarial Review    │  │    Loop Convergence &     │
│       (Pass@1 / Pass@3)   │  │   Sensitivity (ARR / ARP) │  │   Iteration Efficiency    │
└───────────────────────────┘  └───────────────────────────┘  └───────────────────────────┘
```

---

## 2. Core Evaluation Dimensions

### 2.1 Deterministic Task Resolution Rate (Pass@1 & Pass@3)

A benchmark task is scored as **Resolved** if and only if all four deterministic conditions are satisfied:

1. **Red Gate Inversion:** The authored test suite fails on initial verification (`gate-tests.sh --expect-fail` exits `0`), proving new tests are non-trivial and not pre-satisfied.
2. **Deterministic Green Gate:** The final build and test suites pass with zero exit codes (`gate-tests.sh` exits `0` and `gate-build.sh` exits `0`).
3. **Adversarial Approval:** The independent `code-reviewer` (Opus) awards a `CLEAN` verdict (or `NON_BLOCKING` at loop cap) in `$STATE/review-findings-<label>.json`.
4. **Clean Delivery:** The `committer` formats conventional commits and opens a valid pull request with verified diff boundaries.

#### Metrics Definition:

* **Pass@1 (First-Attempt Resolution Rate):**  
  `Pass@1 = (Tasks resolved on first try with 0 fix iterations) / (Total benchmark tasks)`  
  Measures whether the initial implementation satisfies all deterministic quality gates and receives an immediate `CLEAN` approval from the Opus reviewer without requiring fix cycles.

* **Pass@3 (Bounded Convergence Rate):**  
  `Pass@3 = (Tasks resolved within 3 review-fix iterations) / (Total benchmark tasks)`  
  Measures whether the implementer-reviewer-fixer loop successfully converges within the system loop ceiling of 3 iterations.

---

### 2.2 Adversarial Review Sensitivity (Recall & Precision)

To prevent LLM sycophancy (models approving their own flawed code), the review engine is evaluated against ground-truth defects:

* **Adversarial Review Recall (ARR):**  
  `ARR = (Injected defects detected by reviewer) / (Total injected defects)`  
  Measures the percentage of deliberate defects caught by the reviewer, ensuring high sensitivity to security invariants and logic flaws.

* **Adversarial Review Precision (ARP):**  
  `ARP = (Actionable blocking defects) / (Total reported review findings)`  
  Measures the signal-to-noise ratio of findings to ensure the reviewer does not generate spurious blocking nits that stall delivery.

> [!NOTE]
> Adversarial Review Recall (ARR) and Precision (ARP) metrics are formally specified in RFC-002. Automated test harnesses and ground-truth defect fixtures are scheduled for Phase 5 (CI & Automated Benchmarks).

---

### 2.3 Loop Convergence & Iteration Efficiency

Measures the efficiency of the feedback loop between the implementer (Sonnet), reviewer (Opus), analyst (Sonnet), and fixer (Sonnet). 

Iteration requirements scale with task complexity:
* **Simple Bugfixes (e.g. PROJ-1001):** Expected to resolve at **Iteration 0 (Pass@1)** with minimal diff footprint.
* **Security & Invariants (e.g. PROJ-1002):** Expected to resolve within **1 iteration** (flaw caught by adversarial review and resolved on the first targeted fix cycle).
* **Multi-Repo Coordination (e.g. PROJ-1003):** Expected to resolve within **1 to 2 iterations** across coordinated worktrees.
* **Hard Escalation:** Any task that cannot reach a `CLEAN` or `NON_BLOCKING` verdict within 3 iterations stops and escalates to human review.

---

## 3. Dual-Tier Benchmark Architecture

To balance instant developer verifiability with genuine SWE-agent evaluation rigor, `claude-autopilot` implements a **Dual-Tier** evaluation model:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   Dual-Tier Evaluation Architecture                    │
├───────────────────────────────────┬────────────────────────────────────┤
│ Tier 1: Harness & Gate Integrity  │ Tier 2: Autonomous Agent Benchmark │
│ (Offline, Zero-Cost, < 5 Seconds) │ (Live LLM Agent Execution)         │
│                                   │                                    │
│ • Validates native node:test      │ • Resets sandbox to broken state   │
│ • Executes real gate-build.sh     │ • Prompts Claude Autopilot live    │
│ • Executes real gate-tests.sh     │ • Agent writes test (Red Gate)     │
│ • Verifies JSON verdict in $STATE │ • Agent writes fix (Green Gate)    │
│ • Runner: ./bin/run-evals.sh      │ • Measures real Pass@1 & loops     │
└───────────────────────────────────┴────────────────────────────────────┘
```

### 3.1 Golden Benchmark Tasks (Bundled in `examples/sandbox-repo/`)

The evaluation suite defines three representative golden tasks bundled directly into `examples/sandbox-repo/` with native `node:test` execution:

| Benchmark ID | Category | Complexity | Target Invariants Tested | Sample Ticket |
|---|---|---|---|---|
| **PROJ-1001** | Boundary Regression | Single-Repo | TDD Red Gate, minimal diff footprint, Pass@1 resolution. | [`examples/sample-ticket-proj-1001.md`](../examples/sample-ticket-proj-1001.md) |
| **PROJ-1002** | Security & Auth Validation | Single-Repo | Injected token expiry bypass; target Opus review sensitivity (target ARR: 100%), fix loop convergence at iteration 1. | [`examples/sample-ticket-proj-1002.md`](../examples/sample-ticket-proj-1002.md) |
| **PROJ-1003** | Contract Update | Multi-Repo | API microservice schema addition + consumer library deserializer update; isolated clones, sibling PR cross-linking. | [`examples/sample-ticket-proj-1003.md`](../examples/sample-ticket-proj-1003.md) |

### 3.2 Tier 1: Executing the Benchmark & Gate Harness

The harness runner validates the sandbox test suites, real quality gates, and central state persistence offline:

```bash
# Run all golden benchmarks and real gate validations
./bin/run-evals.sh

# Run a specific benchmark task
./bin/run-evals.sh PROJ-1001
./bin/run-evals.sh PROJ-1002
./bin/run-evals.sh PROJ-1003
```

### 3.3 Tier 2: Evaluating Claude Autopilot Autonomously

To run an autonomous agent evaluation from scratch on a live task:

```bash
# 1. Reset the sandbox repository to the broken defect state
./bin/reset-sandbox.sh PROJ-1001

# 2. In your Claude Code session, launch the autonomous pipeline:
/autopilot:engage PROJ-1001 --file examples/sample-ticket-proj-1001.md

# 3. Restore all sandboxes to clean reference state when finished
./bin/reset-sandbox.sh clean
```

> [!IMPORTANT]
> **Multi-Task Benchmark Hygiene (Step 0.5 Session Isolation):**  
> To guarantee valid Pass@1 and token efficiency measurements, always run `/clear` between consecutive Tier 2 benchmark runs.  
> 
> If you evaluate `PROJ-1001` and subsequently trigger `PROJ-1002` in the same conversation window without clearing, the **Step 0.5 Session Isolation Guardrail** will pause and prompt for confirmation before proceeding, preventing previous ticket ASTs and files from contaminating the new evaluation.

---

## 4. Continuous Integration & Regression Testing (Phase 5 Roadmap)

In Phase 5, this protocol will be automated via GitHub Actions (`.github/workflows/ci.yml`):
* Every prompt edit or gate script modification triggers the golden benchmark matrix.
* Automated defect-injection fixtures (`examples/eval-fixtures/`) benchmark reviewer recall (ARR) and precision (ARP).
* Automated PR comments report Pass@1, Pass@3, and regression status against baseline.
