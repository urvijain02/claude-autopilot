---
name: engage
description: Takes a Jira ticket through to open PRs unattended, as an explicit state machine — failing tests written first, shell-script gates the model cannot argue past, and an independent review-and-fix loop. Use when the user says "autopilot <TICKET>", "engage autopilot on <TICKET>", or "run autopilot on <TICKET>". Scoped to one active ticket pipeline per session; prompts for user confirmation before proceeding if prior ticket context is detected to prevent context contamination. NOT for supervised, step-by-step work on a ticket, and not for reviewing or planning a ticket without changing code. The user provides the starting repo link; the pipeline clones it, and expands to connected repos if analysis needs them. Re-running on a ticket already underway resumes it from state.json rather than starting over. The main session (the brain) delegates each stage to subagents and owns the review->fix loop. Multi-repo; no local clone required.
---

# Autopilot — engage (the brain)

You delegate each stage to a subagent, read the file it produced under `$STATE`, decide the next transition, and drive the loop. You do not write code/tests/reviews yourself. Only distilled file outputs return to you.

Nothing is maintained per-repo. The scripts ship inside the plugin (`${CLAUDE_PLUGIN_ROOT}/bin/`); config, state, and the clones live under `~/.claude/autopilot/`. **There is no ticket→repo map** — the user gives you the primary repo link, and connected repos are discovered during analysis. The workspace is multi-repo. This state machine is explicit so it transcribes directly into a TypeScript `while` loop for the Agent SDK.

## Output discipline (read first)

You run autonomously; the user reads the files, not a live narration. **Between stages, emit ONLY one status line per stage** (see the `reporting` skill), plus the preflight checklist, the final block, ⏸ approval prompts, and genuine blockers that need the user. Nothing else reaches the window.

Do all your thinking silently and write reasoning/decisions/diagnosis to `log.md` — **never** to the window. In particular, do NOT print: "Now Stage X…", "Now let me…", "Let me check/verify…", "Delegating to…", "Proceeding."; a prose sentence that restates a result you're already emitting as a status line (the status line replaces it); or any live working-through of a blocker, loop decision, or verdict routing (those are `Decision:` blocks in `log.md`). If in the last run you'd have typed a sentence to explain what you're about to do or just did — don't; act, then print the one status line.

## Invocation

```
engage <TICKET>                    resume if the ticket is already underway, otherwise start it
engage <TICKET> --from <phase>     redo from a named phase (keeps everything before it)
engage <TICKET> --restart          discard the run and start over — confirm first, it throws work away
engage <TICKET> --prompt "<text>"  start with requirement provided as inline prompt text (zero Jira dependency)
engage <TICKET> --file <path>      start with requirement loaded from a markdown file (zero Jira dependency)
engage DEMO                        1-click quickstart: runs PROJ-1001 benchmark on bundled examples/sandbox-repo
engage                             list every ticket whose phase isn't `done`, and stop
```

## Setup

0. **Preflight (preflight skill).** Before anything else, check the required tools (gh auth, git, Atlassian MCP, Slack MCP). If something's missing, tell the user what will fail/skip and get an explicit go-ahead before starting. When running in `DEMO` mode or with `--prompt` / `--file`, Jira and GitHub remote requirements are automatically satisfied locally. Record which optional integrations are unavailable so later steps skip them cleanly.
0.5. **Session Isolation Invariant (Single-Ticket Scope).** You manage strictly ONE active ticket pipeline per Claude conversation session to prevent context contamination and token waste. If conversation history indicates that a previous ticket was already executed or discussed in this session, pause and prompt the user before proceeding:
   > ⚠️ **Context Notice:** A previous ticket run was detected in this conversation session. Running multiple tickets in the same session causes context contamination and higher token spend.
   > 
   > Recommended: Run `/clear` to start with a pristine context window.
   > 
   > Proceed with `<TICKET>` in this session anyway? (y/N)
   
   Wait for explicit user confirmation. If the user declines or requests a reset, stop execution so they can run `/clear`. Never cross-contaminate state, ASTs, or workspaces between tickets.
1. No `<TICKET>` given → if invoked as `DEMO`, set `<TICKET> = "PROJ-1001"`, `--file = "${CLAUDE_PLUGIN_ROOT}/examples/sample-ticket-proj-1001.md"`, and use the primary repo `${CLAUDE_PLUGIN_ROOT}/examples/sandbox-repo`. Otherwise list the parked tickets (see Resuming) and stop.
2. **Read `$STATE/state.json` before you write anything.** Get `$STATE` from `${CLAUDE_PLUGIN_ROOT}/bin/state-dir.sh <TICKET>` — never work it out from config yourself, or you become a second implementation that can disagree with the gate scripts about where verdicts live. What you find decides where you start (see **Resuming**); only when there is no `state.json` do you create one — `phase: "jira-start"`, `iteration: 0`, `max_iterations: 3`, `repos: []` — along with the `log.md` header line (`# <TICKET> — <summary> · pipeline log`).
3. **Jira start (ticket-updates skill).** Assign the ticket to the runner (dynamic `currentUser`) and move it to the project's in-progress status, resolved by that skill. Record `jira_status` in `state.json`. Skip (logged) if the Atlassian MCP is unavailable. Set `phase = "provision"`.
4. **Provision the primary repo (provision-repo skill):** ask the user for the repo link, clone it, record it in `state.json.repos[]` as `role: "primary"`.

## State machine

```
preflight → jira-start → provision(primary) → requirements → [provision connected repos] → test-plan → branch*
   → write-tests* → implement* → review* → (analyze* → fix*)loop → commit* → ticket-updates → cleanup
        (* = fan out: run the stage once per repo in state.repos)
```

`preflight` runs before `state.json` exists, so it is never a value of `phase` — the enum starts at `jira-start`.

Transitions:

1. **requirements** → `requirements-analyst` (runs against the primary repo) → `$STATE/requirements.md`, including a **"Connected repos"** section listing any other repos the change needs, each with why + a best-guess remote or "unknown". ⏸ **when `config.human_gates` is true**, present it and wait before continuing.
2. **provision connected** → for each connected repo the analyst listed, use the provision-repo skill (resolve via `gh`+`config.orgs` and confirm, or ask the user for the link) and append it to `state.json.repos[]` as `role: "connected"`. If none, skip.
3. **test-plan** → `test-planner` → `$STATE/test-plan.md`, covering behaviors **across all repos in `state.repos`** (tag each behavior with the repo it belongs to).
4. **branch** → you (orchestrator) create the feature branch in each repo that will change, using the scripted naming rule. The branch name is derived in code from `state.json.issue_type` + `ticket` + `slug`:
   ```bash
   BR="$(${CLAUDE_PLUGIN_ROOT}/bin/create-branch.sh <TICKET> --repo "$REPO" --type "<issue_type>" --slug "<slug>" --base "<branch_base>")"    # that repo's branch_base, else config.default_base_branch — never empty
   ```
   Run it once per repo (same name across repos). Record each result in that repo's `state.repos[].branch`. `feat/` for Task·Story, `bugfix/` for Bug·Development bug, no prefix for Epic/other; sub-tasks use the parent's type (already resolved into `issue_type`). Then set `phase = "write-tests"`.
5. **write-tests** (fan out per repo that needs tests) → `test-writer`, briefing = `<TICKET>` + that repo's `path` (`$REPO`) + `name` (`<label>`) + its `branch`. The branch already exists and is checked out; the test-writer only writes failing tests and confirms via `gate-tests.sh … --repo "$REPO" --label "<label>" --expect-fail`.
6. **implement** (fan out per repo) → `implementer` → makes that repo's tests pass; leaves its `gates/<label>/tests.json` + `build.json` = pass.
7. **review** (fan out per repo) → `code-reviewer` → `$STATE/review-findings-<label>.json` (per repo). Before using a repo's file, check its `iteration` matches `state.json.iteration` — a mismatch or a missing field means it's a previous round's, so re-run that repo's review once, then escalate if it comes back wrong again (state-protocol). **Combined verdict = worst across repos:** any repo `BLOCKING` → BLOCKING; else any `NON_BLOCKING` → NON_BLOCKING; else CLEAN. Log the combination as a `Decision:` block.
8. Read the combined verdict: `CLEAN` → **commit**; `BLOCKING` → **analyze**; `NON_BLOCKING` → **analyze** as well, and fix whatever the analyst accepts. Do not default to shipping a NON_BLOCKING verdict: by the rubric it can only mean `minor`/`nit` findings, and comment hygiene — which the rubric requires fixed, not shipped — lands in exactly that band. Ship only if the analyst accepts nothing, and log that as a `Decision:` block.
9. **analyze** (fan out per repo with findings) → `review-analyst` → `$STATE/fix-list-<label>.json`.
10. **fix** (fan out per affected repo) → `fixer` → applies that repo's accepted fixes; keeps its gates green.
11. Increment `iteration`. `< max_iterations` → back to **review**. At the cap, decide by **severity**, not unconditionally:
    - last combined verdict `BLOCKING` → **escalate** to a human with the unresolved findings:
      1. Invoke `${CLAUDE_PLUGIN_ROOT}/bin/record-telemetry.sh <TICKET> [...]` to compile stage/phase durations and token metrics for the attempted run.
      2. Print the escalation final block (see reporting skill) populated with `telemetry` and `tokens`.
      3. Append the `## Summary` block and `## AI Telemetry & Token Economics` table to `log.md`.
      4. Leave ticket status unchanged (do not move to In Review; no Slack post) and stop.
    - last combined verdict `NON_BLOCKING` → **commit**. Only `minor`/`nit` findings can survive that verdict, and withholding a PR over nits strands finished work for a human to rescue. Record the survivors as a `Decision:` block and carry them into the final block's `review` field.
12. **commit** — ⏸ **when `config.human_gates` is true, stop here first:** show the per-repo `git diff --shortstat "<branch_base>"` and a count of new untracked files (nothing is committed until the committer runs, so a `...HEAD` diffstat would be empty) plus the combined review verdict, and wait for a go-ahead. This gate lives with you, not the committer: that subagent runs in a fresh context with no channel to the user, so a confirmation delegated to it has nobody to ask. Then (fan out per repo with changes) → `committer` → commits + pushes that repo's branch, opens its PR, records `pr_url` in `state.repos[]`. Cross-reference sibling PRs + the ticket in each body.
13. **ticket-updates (ticket-updates skill)** — once, after all PRs are open:
    - move the ticket to the project's in-review status, resolved by that skill (record `jira_status`);
    - post the PR link(s) to the configured channel (`config.slack_channel`) in the required format (header + one URL per line, no @-mentions, don't start with the KEY); record `slack_link`. If it's unset, skip and log — don't guess a channel.
    Each sub-step skips (logged, surfaced in the final block) if its MCP is unavailable.
14. **cleanup** — three parts. Only the first is conditional:
    - **Discarding the clones — only if `config.cleanup_after_pr`** (shipped default: `false`) → `${CLAUDE_PLUGIN_ROOT}/bin/cleanup-workspace.sh <TICKET>`. Central `$STATE` is kept either way.
    - **Telemetry calculation — always:** invoke the deterministic telemetry engine before finalizing output:
      ```bash
      "${CLAUDE_PLUGIN_ROOT}/bin/record-telemetry.sh" <TICKET> [--tokens-in <IN> --tokens-out <OUT> --tokens-cache-read <CR> --tokens-cache-creation <CC>]
      ```
      This computes macro-phase rollups (`plan_and_setup`, `tdd_and_gates`, `review_and_delivery`) and stage durations from phase marks, calculates prompt cache efficiency, and atomically generates `$STATE/telemetry.json`.
    - **Finalising — always, whether or not the above ran:** set `phase = "done"`, read `$STATE/telemetry.json` to populate the `telemetry` and `tokens` rows, print the final block (see Output / reporting skill), and append both the `## Summary` block and `## AI Telemetry & Token Economics` table to `log.md`.

    Finalising is not optional and does not depend on `cleanup_after_pr`. Skip it and the ticket stays listed as parked forever, and the user never sees the summary of what the run did.

## Output — follow the `reporting` skill

Keep the session minimal and identical across runs: **one line per stage, then the final block, nothing else.** Do not echo file contents, diffs, specs, or findings into the chat — it's all in `$STATE`.

- At each transition, get real elapsed: `${CLAUDE_PLUGIN_ROOT}/bin/mark-phase.sh <TICKET> <phase>` records the mark and prints the stage elapsed on stdout. It does not write to `log.md` — put what it printed into that phase's section header (`· HH:MM (+<elapsed>)`), which is the only place per-stage timing survives. Print the one-line status from the reporting skill.
- At the end, print the fixed final block (status · total elapsed; per-repo line with `git diff --shortstat`; gates shown as pass/fail/**skipped** explicitly; review + iterations; `telemetry` phase timings; `tokens` with cache efficiency; **manual** checks as bullets pulled from `test-plan.md`, or `none`; PR URL(s); the `details` path). Exact shape is in the `reporting` skill.

### Logging (follow the `state-protocol` log format)

`log.md` is structured, not free-form (see state-protocol → Log format). Your responsibilities as orchestrator:
- Write the one-line header at run start.
- Log your own **routing decisions as `Decision:` blocks** — verdict routing (CLEAN→commit / NON_BLOCKING→ship-or-fix / BLOCKING→analyze), skipping a step because an MCP is unavailable, escalating at the iteration cap, choosing connected repos to provision. Always with `Why:` and `Alternatives:`.
- Open a `## Follow-up: <name> (<date>)` section for any work after `done`.
- At the end, append the `## Summary` block (same content as the console final block) and the `## AI Telemetry & Token Economics` table.

## Hard rules

- **Gate before transition, per repo.** Never advance a repo past write-tests/implement/fix unless its `$STATE/gates/<label>/*.json` says `pass`. Read the file.
- **Tests earn long-term value, and the suite is always green.** Don't add unit/integration tests that only satisfy this ticket, exercise the framework, or wouldn't survive the next refactor — a repo may reach commit with **zero *added* tests** when the plan marks the work `none`. But the **full existing test suite must run and pass** in every changed repo before commit, regardless of whether tests were added; "no new tests" never authorizes a skipped or failing suite. Log the no-new-test decision as a `Decision:` block.
- **A `blocked` gate → escalate, don't loop.** `blocked` means an environment problem the workaround couldn't fix (e.g. .NET NuGet restore still 401 after the offline fallback). Stop, log a `Decision:` block, and escalate to the human with the specific ask (a valid private package feed credential, e.g. Azure DevOps or GitHub Packages). Do not treat it as a code failure or spin the fix loop.
- **Cap the loop** at `max_iterations` (3). Escalate, don't spin.
- **Coordinate across repos.** A change that alters a contract in the primary repo and its consumer in a connected repo must be planned together (test-plan spans repos) and shipped together (linked PRs). Per-repo subagents stay isolated; the shared plan in `$STATE` is how they coordinate.
- **Every stage updates `state.json` and appends to `log.md`.**
- **Never write a `state.json` over one that already exists.** Read first, resume second. Overwriting loses the spec, plan, findings and gate verdicts of a run in flight.
- **Human gates (⏸) are off unless `config.human_gates` is true.** Default is a straight run from ticket to open PRs with nothing to approve. When it's on, pause at the ⏸ points and wait. Never infer this from context — read the config key, so the decision to stop for a person is checkable rather than guessed.
- **Quality gates are not human gates and are never optional.** `config.human_gates` has no bearing on `$STATE/gates/*.json`; those are read before every transition regardless.

## Resuming

`state.json` is the entire memory of a run, so a re-run is a resume.

| What you find at `$STATE/state.json` | What you do |
|---|---|
| Nothing | Fresh run from preflight. |
| A known `phase` other than `done` | Say in one line where it stopped, then continue from that phase. |
| `phase: "done"` | Don't silently redo it. Ask whether this is follow-up work; if it is, open a `## Follow-up: <name> (<date>)` section in `log.md` and take the starting phase from the user. |
| A `phase` outside the list below | **Stop and ask**, quoting the value. A phase you can't map means a corrupted or hand-edited run, and guessing where to pick up risks skipping a gate. |

The only legal values of `state.json.phase`:

`jira-start · provision · requirements · test-plan · branch · write-tests · implement · review · analyze · fix · commit · ticket-updates · cleanup · done`

### Trust the files, not the summary

`state.json` describes the world as it was when the run stopped. Before continuing, confirm that world still exists — per repo in `state.repos[]`:

**A gate verdict is only valid for the working tree that produced it.** A `pass` outlives the code it certified — the verdict is in `$STATE`, which survives, while the code is in the clone, which doesn't. So a re-clone plus a stale `pass` satisfies the hard rule against an empty branch. Whenever the tree is replaced, the verdicts go with it.

- **Clone missing** at `repos[].path` (cleanup ran, or the workspace was cleared) → re-provision with the provision-repo skill and update `path`. Never carry on against a path that isn't there, and don't assume the path sits under `workspace_root` — read what's recorded. `provision-repo.sh` deletes that repo's `$STATE/gates/<label>/` itself whenever it creates a new clone, so the verdicts can't survive the tree; clear `repos[].gates` in `state.json` to match. The new clone holds none of the work, so roll that repo's phase back to no later than `write-tests` as well.
- **Branch missing** in a clone that does exist → recreate it from that repo's `branch_base` (or `config.default_base_branch`) under the recorded name, **delete `$STATE/gates/<label>/` and clear `repos[].gates`**, and treat the phase as no later than `write-tests`. The clone survived here, so nothing deletes the verdicts for you.
- **Gate JSON missing** under `$STATE/gates/<label>/` → re-run that gate. The `gates` block in `state.json` is a convenience copy; the file the gate script wrote is the verdict. Never resume on a remembered `pass` you can't read.

**Any rollback resets the loop.** When revalidation moves `phase` backwards for a repo, set `iteration` back to `0`. Carrying the old count means a run that had already spent two of its three iterations redoes the work with one left and escalates without a single fix round against the new tree — the count belongs to a review loop that no longer exists.

Log anything you had to redo as a `Decision:` block.

### `--from <phase>` and `--restart`

- `--from <phase>` — validate against the list above, log a `Decision:` block, set `phase`, continue. Everything earlier is left alone.
- `--restart` — discards spec, plan, findings and gate verdicts. **Confirm with the user first**, quoting what's about to be lost: phase reached, repos and branches, and whether any PRs are already open. Then, in this order — the refusal comes first, so a guard can't fire after the thing it guards:
  1. **Refuse to restart if any repo already has a `pr_url`**, before touching anything. The branch is pushed and under review; a restart would either diverge from the open PR or force-push over its history. Say so, offer `--from <phase>` instead, and stop.
  2. Rename `$STATE` to `$STATE.superseded-<n>` rather than deleting it.
  3. **Delete the ticket's workspace** at `<workspace_root>/<TICKET>/`, or re-provision every repo with `--fresh`. Skip this and `provision-repo.sh` reuses the existing clone and `create-branch.sh` checks out the existing branch of the same computed name — so the "fresh" run silently continues on top of the commits it just told the user it was discarding.

### `engage` with no ticket

List every directory under the state root — `${CLAUDE_PLUGIN_ROOT}/bin/state-dir.sh` with no argument prints it — whose `state.json.phase` isn't `done`, **skipping any `*.superseded-*`**: `--restart` archives a discarded run under that name and its `state.json` keeps whatever phase it stopped at, so it would otherwise be listed as live — ticket, phase, iteration, `updated_at` — one line each. Then stop; don't start anything.

### One-transition mode (not currently used)

A run normally goes start to finish in a single invocation. The state machine is also written to support doing **one** transition per invocation and stopping, resuming by the rules above — the basis for driving it from a scheduler later. Nothing invokes it that way today.
