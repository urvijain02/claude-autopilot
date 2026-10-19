---
name: preflight
description: Pre-run checklist — verify the tools the pipeline needs (gh auth, git, Atlassian MCP, Slack MCP) are connected BEFORE starting. Surfaces anything missing and exactly what will fail or skip, and asks to continue. Used by the autopilot orchestrator at the very start.
---

# Preflight

Run this FIRST — before touching the ticket or cloning anything — so missing tools surface up front, not mid-run.

## Platform detection & package managers

At run start, probe the host platform:
- **Windows (Git Bash / MSYS / PowerShell):** `uname -s` starts with `MINGW*`, `MSYS*`, or `CYGWIN*` (or `$OSTYPE == msys*` / PowerShell `$env:OS == "Windows_NT"`).
- **macOS (Darwin):** `[[ "$(uname -s)" == "Darwin" ]]`.
- **Linux / WSL:** `[[ "$(uname -s)" == "Linux" ]]` (WSL if `/proc/version` contains `microsoft`).

When a critical CLI tool is missing, surface the recommended 1-click install command for the detected OS (with official URL) inline. Do NOT attempt to execute package manager commands automatically (avoids background subshell hangs or UAC/sudo permission stalls).

## Check each

| Need | How to check | If missing → consequence & remediation |
|---|---|---|
| **platform** | `uname -s 2>/dev/null || echo "$OS"` (matches `MINGW*|MSYS*|CYGWIN*` → Windows; `Darwin` → macOS; `Linux` → Linux / WSL) | Informs path normalization, package managers, and binary resolution across pipeline stages. |
| **gh auth** | `gh auth status 2>&1` | **Critical for remote runs.** If missing or unauthenticated: cannot clone private repos or open PRs. Surface recommended OS install command (`winget install --id GitHub.cli` on Windows, `brew install gh` on macOS, `sudo apt install gh` on Linux) or official installer (`cli.github.com`). *(Downgraded to non-blocking warning in offline evaluation / `DEMO` / `--file` modes; remote PR step is skipped).* |
| **git** | `command -v git` | **Critical.** No clones/branches/commits. Surface recommended OS install command (`winget install Git.Git` on Windows, `brew install git` on macOS, `sudo apt install git` on Linux) or official installer (`git-scm.com`). |
| **JSON engine** | `. "${CLAUDE_PLUGIN_ROOT}/bin/_paths.sh" && resolve_json_engine` | If returns `none`: **Critical.** Gate scripts and telemetry cannot parse state JSON. Surface install command for `node` (`winget install OpenJS.NodeJS.LTS`), `python3`, or `jq` (`brew install jq` / `sudo apt install jq`). |
| **Atlassian MCP** | attempt `atlassianUserInfo` on whichever Atlassian MCP is connected — the standalone server or the claude.ai connector (`mcp__claude_ai_Atlassian__*`). Either satisfies this check. | Jira steps **skip**: the ticket won't be assigned or moved. |
| **Slack MCP** | attempt a lightweight Slack call (e.g. resolve the channel) | Slack step **skips**: the PR link won't be posted. |
| **config** | `${AUTOPILOT_HOME:-~/.claude/autopilot}/config.json` exists — check the resolved path, not the literal default, since `AUTOPILOT_HOME` moves it | Defaults are used. A missing `slack_channel` means the PR-link post is **skipped** — surface that now rather than at the end of the run. |

## Report + decide

Print the checklist in this exact shape — one line per check:
```
preflight <TICKET>
 ✓ platform      windows (git bash)
 ✓ gh auth
 ✓ git
 ✓ engine        jq
 ✗ Atlassian MCP — Jira steps (assign / status transitions) will be skipped
 ✗ Slack MCP     — PR-link post will be skipped
 ✓ config
```
(`✓ <item>` when present; `✗ <item> — <consequence>` or `✗ <item> — missing; install via: <install-cmd> or <url>` when missing.) Then:

- **All present** → proceed silently into the run.
- **Anything missing** → **stop and tell the user** what's missing and its consequence:
  - **Universal critical miss** (`git` or `engine: none`) → surface the recommended install command and download link, recommend fixing before running, and do not start (pipeline cannot function without git and JSON parsing).
  - **Contextual miss** (`gh auth`):
    - *Remote run*: **do not start**; prompt to install or authenticate `gh` via `gh auth login`.
    - *Offline evaluation / `DEMO` / `--file` / `--prompt` mode*: warn that remote PR creation will be skipped, but **allow proceeding** with local git branches and commits.
  - **Optional misses** (Atlassian / Slack / config) → state precisely which steps will be **skipped**, then ask: *"Continue anyway?"*
- If the user says continue, proceed and **skip only the unavailable steps** — log each skip in `log.md` and surface it in the final block (e.g. `jira  skipped (Atlassian MCP not connected)`). **Never skip silently.**
