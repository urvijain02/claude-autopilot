# Contributing to Claude Autopilot

Thank you for your interest in contributing to **Claude Autopilot**! We welcome contributions from the community—whether you are adding support for new language runtimes, refining subagent personas, improving deterministic quality gates, or expanding documentation.

---

## 1. Architectural Overview

Before contributing, please review the core architectural blueprints:
* **[System Architecture Specification (RFC-001)](docs/SPECIFICATION.md):** Formal state machine transitions, JSON data schemas, deterministic gate contracts, and convergence proofs.
* **[Security Policy & Trust Model](SECURITY.md):** Workspace sandboxing, permission quarantining, and credential handling invariants.

The repository is organized into four modular layers:

```
claude-autopilot/
├── agents/             # Subagent prompt specifications and operational personas
├── bin/                # Deterministic POSIX Bash shell scripts and quality gates
├── skills/             # Reusable workflow procedures, schemas, and rubrics
├── hooks/              # Plugin lifecycle hooks (configuration bootstrapping)
└── docs/               # System architecture specifications and RFC documents
```

---

## 2. Local Development Setup

### Prerequisites
* **POSIX Bash:** macOS and Linux supported natively; Windows supported via Git Bash or WSL.
* **Git:** Version 2.30+ installed and configured.
* **GitHub CLI (`gh`):** Authenticated with `gh auth login`.
* **Claude Code CLI:** Installed with active access.

### Setting Up a Development Worktree
1. Fork and clone the repository:
   ```bash
   git clone https://github.com/urvijain02/claude-autopilot.git
   cd claude-autopilot
   ```

2. Register and install the local plugin in Claude Code:
   ```bash
   /plugin marketplace add ./
   /plugin install autopilot@claude-autopilot
   ```
   *Or launch Claude Code with the local repository directory directly:*
   ```bash
   claude --plugin-dir .
   ```

3. Configure a custom testing workspace anchor using `AUTOPILOT_HOME` (prevents altering your production configuration):
   ```bash
   export AUTOPILOT_HOME="$HOME/.autopilot-dev"
   ```

---

## 3. Extending Language Support for Target Repositories (e.g. Rust, Go, Python)

> **Important Distinction:** While the Claude Autopilot orchestrator itself is driven via Claude Code or a lightweight Python/TypeScript loop (see [README.md](README.md#is-this-locked-into-anthropics-claude-ecosystem)), the **repositories it writes code for** can be written in any programming language (.NET, Node, Python, Rust, Go, etc.).

Adding support for a new target repository language or build system requires updates across three deterministic gate scripts in `bin/`:

### Step 1: Detect the Project Stack
In `bin/detect-stack.sh`, add a detection clause matching the project root manifest:
```bash
if [ -f "$REPO_PATH/Cargo.toml" ]; then
  echo "rust"
  exit 0
fi
```

### Step 2: Implement Build Verification
In `bin/gate-build.sh`, implement the compilation and syntax check command:
```bash
case "$stack" in
  rust)
    cargo check --tests ;;
esac
```

### Step 3: Implement Test Verification & TDD Red Gate
In `bin/gate-tests.sh`, implement test execution and the inverted `--expect-fail` red-test verification:
```bash
case "$stack" in
  rust)
    if [ "$EXPECT_FAIL" = "true" ]; then
      # Expect failure: command must exit non-zero
      cargo test && exit 1 || exit 0
    else
      cargo test
    fi
    ;;
esac
```

---

## 4. Subagent Prompt & Style Standards

When adding or modifying subagent prompts in `agents/` or skills in `skills/`, adhere strictly to these principles:

1. **Maintain Context Isolation:** Never merge authoring and review roles into a single prompt. Reviewers must operate with zero code-edit rights.
2. **Comment Hygiene Standard:** All prompts must instruct models to enforce minimal, high-signal comments:
   * Explain non-obvious *why*, never *what*.
   * One line where possible; no multi-sentence play-by-play essays.
   * Everyday language; avoid jargon or abstract adjectives.
   * Never comment the *absence* of code.
   * Zero ticket keys (`PROJ-123:`), acceptance criteria tags (`AC1:`), or temporary process notes in production source code.
3. **Deterministic Output:** Inter-agent messages must adhere to the JSON schemas defined in `docs/SPECIFICATION.md`.

---

## 5. Commit & Pull Request Guidelines

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

* `feat: ...` — New capability, subagent role, or stack support.
* `fix: ...` — Bug fix in a shell gate, state transition, or prompt.
* `docs: ...` — Additions or updates to specifications, architecture diagrams, or guides.
* `test: ...` — Testing infrastructure or mock suites.
* `chore: ...` — Maintenance, line endings, or build configuration.

### Version Bumping
The plugin version appears in **two** files and both must be updated together whenever a release is tagged:
* `.claude-plugin/plugin.json` (`version` field)
* `.claude-plugin/marketplace.json` (entry `version` field)

### Submitting a PR
1. Create a feature branch: `git checkout -b feat/my-enhancement`.
2. Ensure shell scripts pass syntax checks:
   ```bash
   bash -n bin/*.sh
   ```
3. Commit with a concise summary and structured bullet points.
4. Push and open a pull request against `main`. All PRs are reviewed for architectural consistency, gate determinism, and license compliance.
