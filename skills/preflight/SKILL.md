---
name: preflight
description: Pre-run checklist — verify the tools the pipeline needs (gh auth, git, Atlassian MCP, Slack MCP) are connected BEFORE starting. Surfaces anything missing and exactly what will fail or skip, and asks to continue. Used by the autopilot orchestrator at the very start.
---

# Preflight

Run this FIRST — before touching the ticket or cloning anything — so missing tools surface up front, not mid-run.

## Check each

| Need | How to check | If missing → consequence |
|---|---|---|
| **gh auth** | `gh auth status` | **Critical.** Cloning private repos and opening PRs fail — the core job can't run. |
| **git** | `command -v git` | **Critical.** No clones/branches/commits. |
| **Atlassian MCP** | attempt `atlassianUserInfo` on whichever Atlassian MCP is connected — the standalone server or the claude.ai connector (`mcp__claude_ai_Atlassian__*`). Either satisfies this check. | Jira steps **skip**: the ticket won't be assigned or moved. |
| **Slack MCP** | attempt a lightweight Slack call (e.g. resolve the channel) | Slack step **skips**: the PR link won't be posted. |
| **jq or python3** | `command -v jq`, else `python3 -c ''` | Neither, **and** a `state_root`/`workspace_root` in config that isn't a plain one-line string → the gate scripts **stop** rather than write verdicts where nothing reads them. With a plain value or no config, nothing is lost. |
| **config** | `${AUTOPILOT_HOME:-~/.claude/autopilot}/config.json` exists — check the resolved path, not the literal default, since `AUTOPILOT_HOME` moves it | Defaults are used. A missing `slack_channel` means the PR-link post is **skipped** — surface that now rather than at the end of the run. |

## Report + decide

Print the checklist in this exact shape — one line per tool:
```
preflight <TICKET>
 ✓ gh auth
 ✓ git
 ✗ Atlassian MCP — Jira steps (assign / status transitions) will be skipped
 ✗ Slack MCP — PR-link post will be skipped
 ✓ config
```
(`✓ <tool>` when present; `✗ <tool> — <consequence>` when missing.) Then:

- **All present** → proceed silently into the run.
- **Anything missing** → **stop and tell the user** what's missing and its consequence:
  - A **critical** miss (gh / git) → recommend fixing before running; don't start.
  - **Optional** misses (Atlassian / Slack / config) → state precisely which steps will be **skipped**, then ask: *"Continue anyway?"*
- If the user says continue, proceed and **skip only the unavailable steps** — log each skip in `log.md` and surface it in the final block (e.g. `jira  skipped (Atlassian MCP not connected)`). **Never skip silently.**
