---
name: state-protocol
description: The file-based hand-off contract for the autopilot pipeline. Where agents read prior stages and write their own output — a CENTRAL, repo-agnostic state dir. Every pipeline agent binds this skill.
---

# State protocol

Subagents start from a **fresh context** — the delegation prompt is the entire briefing. Nothing crosses the boundary except files on disk. So every stage reads its inputs from, and writes its outputs to, the ticket's **central state dir**. This is deliberate: it makes the pipeline resumable, auditable, portable to the Agent SDK, and — importantly — **repo-agnostic**. The scripts ship with the plugin and the state lives in one central place, so both run against any repo; the target repo is never polluted with pipeline files (only git operations touch it).

## Locations (one install, all repos)

Everything below hangs off one anchor: **`AUTOPILOT_HOME`**, default `~/.claude/autopilot`. Setting it relocates the config file and the *defaults* for the state and workspace roots together. It has no config-file equivalent — a setting inside config saying where config lives would be circular — so it is an environment variable only, and `bin/_paths.sh` is the single place all of these are resolved.

- **State dir:** `~/.claude/autopilot/state/<TICKET>/` — the durable, browsable output of a run (spec, plan, findings, gate verdicts, log). Ask for it — `${CLAUDE_PLUGIN_ROOT}/bin/state-dir.sh <TICKET>` prints it, and with no argument prints the root. Do not resolve it from config yourself; the gate scripts use that script's logic, and a second derivation can disagree about where verdicts live. Override with `AUTOPILOT_STATE_DIR`, or `state_root` in `config.json`. Referred to below as `$STATE`.
- **Gate scripts:** `${CLAUDE_PLUGIN_ROOT}/bin/` — shipped with the plugin; a single copy, pointed at the target repo via `--repo`.
- **Config:** `$AUTOPILOT_HOME/config.json`, default `~/.claude/autopilot/config.json` — defaults only, no repo map (see provision-repo). Holds `default_base_branch`, `human_gates`, `cleanup_after_pr`, `state_root`, `workspace_root`, `orgs`, `jira_site`, `slack_channel`, `auto_expand_connected`, and `jira_transitions` which fills itself in.
- **Workspace (multi-repo):** ephemeral clones at `~/.claude/autopilot/work/<TICKET>/repos/<name>/`, created by provision-repo and recorded in `state.json.repos[]`. The user gives the primary repo; connected repos are added during analysis. No pre-existing local clone is required; all clones are disposable and live outside any repo you maintain. A per-repo path is referred to below as `$REPO` and its name as `<label>`. `repos[].name`, the workspace directory basename, the `--label` passed to the gates and the `gates/<label>/` directory are all **the same string** — provisioning and the gates key off it independently, so they only agree if nothing renames it.

```
$STATE/                         (~/.claude/autopilot/state/<TICKET>/)
  state.json                    # single source of truth for the state machine
  requirements.md               # stage 1 (includes a "Connected repos" section)
  test-plan.md                  # stage 2 (each behavior tagged with its repo)
  review-findings-<label>.json  # stage 5, one per repo (rewritten each round; carries its `iteration`)
  fix-list-<label>.json         # stage 6, one per repo (same)
  gates/<label>/                # per-repo quality gate verdicts & execution logs
    tests.json                  # test runner exit verdict (pass | fail | skipped | blocked)
    build.json                  # compiler/build exit verdict (pass | fail | skipped | blocked)
    *.log                       # raw build and test runner console output
  telemetry.json                # token economics & phase/stage timings, written ONLY by record-telemetry.sh
  log.md                        # append-only human trail
  .marks                        # phase timestamps, written ONLY by mark-phase.sh
```

## state.json schema

```json
{
  "ticket": "PROJ-123",
  "issue_type": "Story",   // effective type: for a Sub-task, its PARENT's type
  "slug": "add-retry-on-timeout",   // short kebab summary; shared across repos
  "jira_status": "In Review",   // last status the pipeline set (or "skipped")
  "slack_link": "https://workspace.slack.com/archives/...",  // the notification post (or "skipped")
  "repos": [
    {
      "name": "service-api", "role": "primary", "remote": "org/service-api",
      "path": "/Users/you/.claude/autopilot/work/PROJ-123/repos/service-api",
      "stack": "dotnet", "branch": "feature/PROJ-123-slug",
      "branch_base": "main",   // this repo's base — the only place one is recorded; falls back to config.default_base_branch
      "gates": { "tests": "pass|fail|skipped|blocked", "build": "..." },  // these four only — a gate that hasn't run has no entry. blocked = env issue (e.g. NuGet feed 401) the workaround couldn't fix → escalate
      "pr_url": null
    }
    // connected repos appended here during the run, role: "connected"
  ],
  "phase": "jira-start | provision | requirements | test-plan | branch | write-tests | implement | review | analyze | fix | commit | ticket-updates | cleanup | done",
  "iteration": 0,
  "max_iterations": 3,
  "updated_at": "2026-07-07T00:00:00Z"
}
```

## review-findings-<label>.json  (one per repo)

```json
{ "repo": "service-api",
  "iteration": 0,          // the state.json iteration this round belongs to
  "verdict": "BLOCKING | NON_BLOCKING | CLEAN",
  "findings": [ { "id": "F1", "severity": "blocking|major|minor|nit", "file": "path", "line": 0,
                  "summary": "one line", "rationale": "why it's a defect", "confidence": "high|med|low" } ] }
```

## fix-list-<label>.json  (one per repo)

```json
{ "repo": "service-api",
  "iteration": 0,          // the state.json iteration this round belongs to
  "fixes": [ { "finding_id": "F1", "accepted": true, "action": "what to change",
               "files": ["path"], "reason_if_rejected": "" } ] }
```

## telemetry.json schema

```json
{
  "ticket": "PROJ-1001",
  "models": {
    "analyst": "claude-sonnet",
    "implementer": "claude-sonnet",
    "reviewer": "claude-opus"
  },
  "tokens": {
    "input": 124500,
    "output": 14200,
    "cache_read": 102000,
    "cache_creation": 22500
  },
  "cache_hit_rate_percent": 81.9,
  "duration_seconds": {
    "total": 134,
    "phases": {
      "plan_and_setup": 20,
      "tdd_and_gates": 52,
      "review_and_delivery": 62
    },
    "stages": {
      "preflight": 2,
      "jira_start": 2,
      "provision": 4,
      "requirements": 6,
      "test_plan": 4,
      "branch": 2,
      "write_tests": 12,
      "implement": 40,
      "review": 30,
      "analyze": 8,
      "fix": 12,
      "commit": 4,
      "ticket_updates": 8,
      "cleanup": 0
    }
  }
}
```

## Rules

- **Read before you act** — load the `$STATE` files your stage depends on.
- **All pipeline outputs go under `$STATE`**, never inside `$REPO`. Code changes go in `$REPO` (via git); pipeline artifacts do not.
- **All JSON files under `$STATE` (`state.json`, `review-findings-*.json`, `fix-list-*.json`, `telemetry.json`) must be valid, raw JSON only** — never wrap file contents in markdown code fences (` ``` ` or ` ```json `), and never include surrounding prose. When updating `state.json`, preserve valid JSON syntax.
- **Never write gate verdicts by hand.** `$STATE/gates/*.json` are written *only* by the gate scripts. Read them; don't author them.
- **Never write telemetry by hand.** `$STATE/telemetry.json` is written *only* by `bin/record-telemetry.sh`.
- **A findings or fix-list file is only valid for its own round.** Both carry `iteration`. Before routing on a verdict, or handing a fix list to the fixer, check it equals `state.json.iteration`. A lower number, or no `iteration` at all, means the file is left over from an earlier round — the loop was interrupted mid-fan-out — so re-run that stage for that repo instead of acting on it. **Re-run it once only:** if the regenerated file still doesn't carry the current `iteration`, stop and escalate. A writer that won't set the field would otherwise spin this loop forever.
- **`repos[].gates` is a copy, not the verdict.** The gate script's JSON under `$STATE/gates/<label>/` is authoritative. If it's gone, re-run the gate rather than trusting the copy — a resumed run must not inherit a `pass` nobody can read.
- **A verdict is only valid for the working tree that produced it.** Verdicts live in `$STATE` and survive; the code lives in a disposable clone and doesn't. So whenever a clone is replaced or a branch recreated, that repo's `$STATE/gates/<label>/` is deleted and `repos[].gates` cleared — otherwise a fresh, empty branch inherits the old `pass`.
- **`phase` is a closed set** — exactly the values listed in the schema above. Anything else means the file was hand-edited or truncated; stop and ask rather than guessing where to pick up, since the wrong guess skips a gate.
- **Never recreate a `state.json` that exists.** Read it and resume from `phase`.
- **Append to `log.md` in the fixed format below** — never free-form.
- End your stage by updating `state.json.phase` + `updated_at`.

## Log format (`log.md`) — required, not free-form

`log.md` has ONE header line (written once at run start):

```
# <TICKET> — <one-line summary> · pipeline log
```

Then each stage **appends its own `##` section**, in run order. Never overwrite; never dump file contents (detail lives in the stage's own files). Section header:

```
## <phase>[ · <repo>][ · iteration N] · HH:MM (+<elapsed>)
```
(multi-repo → include `· <repo>`; a review→fix loop pass → include `· iteration N`. `<elapsed>` is what `mark-phase.sh` printed for this phase — the only place per-stage timing survives in readable form.)

Inside a section, use only these fields, in this order, omitting any that don't apply:

```
Did:
- concise bullets of what happened (a few lines, not walls of text)
Decision: <what you chose>
  Why: <reasoning / evidence>
  Alternatives: <what else was considered and why rejected, or "none">
Gates: tests <pass|fail|skipped|blocked> (<n/n>) · build <pass|fail|skipped|blocked>
→ <next phase>
```

- **Every autonomous choice gets a `Decision:` block** with `Why:` and `Alternatives:` — this is required wherever a stage or the orchestrator picks between options (which repo/target, delete-vs-reimplement, skip analyze→fix, which status transition, etc.). Preserve the *thinking*, concisely.
- `Gates:` only when a gate ran.

**Follow-up work** (anything after the run reached `done` — a re-run, a review-comment cycle) opens its own section:

```
## Follow-up: <name> (<date>)
### <phase> · HH:MM
Did: …
```

**End of every run**, the orchestrator appends a `## Summary` block (the persisted mirror of the console final block):

```
## Summary
status   <✓ done | ⚠ escalated | ✗ failed> · total <elapsed>
repos    <name> (<branch>)  +A −D · N files
gates    tests: <pass|fail|skipped|blocked> (<n/n>) · build: <pass|fail|skipped|blocked>
review   <clean|non-blocking|escalated> · <k> iteration(s)
telemetry plan: <P> · tdd: <T> · review: <R>
tokens   <IN> in (<HIT>% cache hit) · <OUT> out · <TOTAL> tok
manual   <none | bullets>
PR       <url>
jira     <status | skipped (reason)>
slack    <posted → <channel> | skipped (reason)>
```

And right after `## Summary`, appends the structured telemetry audit table generated from `$STATE/telemetry.json`:

```markdown
## AI Telemetry & Token Economics

| Metric | Value | Breakdown / Details |
| :--- | :--- | :--- |
| **Total Duration** | `<total>s` | Plan: `<P>s` · TDD: `<T>s` · Review: `<R>s` |
| **Models Deployed** | `sonnet` / `opus` | Analyst: `sonnet` · Coder: `sonnet` · Reviewer: `opus` |
| **Input Tokens** | `<IN>` | Cache Read: `<CR>` (`<HIT>%`) · Cache Creation: `<CC>` |
| **Output Tokens** | `<OUT>` | Completion tokens generated across stages |
| **Total Tokens** | `<TOTAL>` | Combined context window footprint |
| **Cache Efficiency** | `<HIT>%` | Prompt cache read hit rate across sequential subagents |

### Phase Timing Breakdown
| Macro Phase | Duration | Constituent Stages |
| :--- | :--- | :--- |
| **Plan & Setup** | `<P>s` | `preflight`, `jira_start`, `provision`, `requirements`, `test_plan`, `branch` |
| **TDD & Gates** | `<T>s` | `write_tests`, `implement` |
| **Review & Delivery** | `<R>s` | `review`, `analyze`, `fix`, `commit`, `ticket_updates`, `cleanup` |
```
