---
name: reporting
description: The session-output contract for the pipeline — terse one-line-per-stage status and a fixed final block. All detail lives in the files, not the chat. Bound by the orchestrator and every pipeline agent.
---

# Reporting (keep the session minimal & consistent)

Everything detailed is written to the ticket's state dir — `$STATE`, whatever `${CLAUDE_PLUGIN_ROOT}/bin/state-dir.sh <TICKET>` returns (spec, plan, findings, gate logs, `log.md`). So the **session window stays short and identical across runs**. Do NOT echo file contents, specs, diffs, findings, or long narration into the chat.

## For subagents (every stage)

Return **one line** to the orchestrator, this exact shape — no preamble, no restating the plan, no pasting file contents:
```
<phase> · <repo>: <result> · gates <tests …/build …> · wrote <files>
```
e.g. `implement · auth-service: tests 57/57, build ok · wrote TokenValidator.cs, TokenValidatorTests.cs`. If a stage has no gates or no files, drop that part. Full detail goes in your `log.md` section, not the return.

## For the orchestrator

### Output discipline — strict

The session shows ONLY: one status line per stage, the preflight checklist, the final block, a ⏸ approval prompt, a genuine blocker that needs the user, and a direct answer when the user asks a question. **Nothing else.** You run autonomously — the user reads the files, not a live play-by-play. Think silently (in your reasoning), write outcomes and reasoning to `log.md`, surface almost nothing.

**Never print any of these — they go to `log.md`, or nowhere:**
- About-to narration: "Now Stage X…", "Now let me…", "Let me read/check/verify…", "Delegating to…", "Proceeding.", "Now provisioning…". Just do it; the status line reports the result.
- A prose sentence restating a result you're also emitting as a status line — **the status line replaces the prose; never both.**
- Live diagnosis or weighing of options (build/credential blockers, loop decisions, verdict routing) — that is a `Decision:` / `Did:` entry in `log.md`, not window text.
- File contents, diffs, specs, findings, plans.

### One line per stage

After each stage, print **exactly one plain line** — not wrapped in its own ``` fence (fences are only for the preflight checklist and the final block). Get real elapsed from the helper:
```bash
E="$(${CLAUDE_PLUGIN_ROOT}/bin/mark-phase.sh <TICKET> <phase>)"   # prints stage elapsed, logs the mark
```
Line shape: `<TICKET> · <phase>[ · <repo>] · <one-line result> · <E>`
Example: `PROJ-123 · implement · auth-service · tests 57/57 · build ok · 2m14s`

### Final block — exactly this shape

```
<TICKET>  <✓ done | ⚠ escalated | ✗ failed> · total <TOTAL>
 repos    <name> (<branch>)  +A −D · N files          # one line per repo; A/D/N from `git -C <repo> diff --shortstat <base>...HEAD`
 gates    tests: <pass|fail|skipped|blocked> (<n/n>) · build: <pass|fail|skipped|blocked>    # per repo if multi-repo
 review   <clean|non-blocking|escalated> · <k> iteration(s)
 manual   <none | bullets>
 PR       <url>                                        # one per repo
 jira     <status set, e.g. In Review | skipped (Atlassian MCP not connected)>
 slack    <posted → <channel> | skipped (Slack MCP not connected)>
 details  <STATE>
```

Rules for the block:
- **`<STATE>`**: `${CLAUDE_PLUGIN_ROOT}/bin/state-dir.sh <TICKET>`. Never print the default path literally — `state_root` and `AUTOPILOT_STATE_DIR` move it, and a wrong path here sends the reader somewhere the files aren't.
- **`<TOTAL>`**: `${CLAUDE_PLUGIN_ROOT}/bin/mark-phase.sh <TICKET> --total`.
- **gates**: state each gate's result **explicitly** — `pass` / `fail` / `skipped` / `blocked`. Never imply pass for a skip or a block; each is shown as itself. Read the real values from `gates/<label>/*.json`.
- **manual**: pull the rows tagged `manual` from `test-plan.md` and list them as short bullets:
  ```
   manual
     - <manual check 1>
     - <manual check 2>
  ```
  If there are none, write `manual   none`.
- One `repos` / `PR` line per repo in a multi-repo run.

### Escalation (review loop hit the iteration cap)

Don't free-form it. Print the same final block with `status  ⚠ escalated`, no PR line, and an `unresolved` field listing the surviving findings as bullets:
```
<TICKET>  ⚠ escalated · total <elapsed>
 repos    <name> (<branch>)  +A −D · N files
 gates    tests: <…> · build: <…>
 review   escalated · <k> iteration(s)
 unresolved
   - <finding — one line>
   - <finding — one line>
 details  <STATE>
```
The ticket is left in its current status (not moved to In Review) and no Slack post goes out — say so if asked.

That is the entire session output for a run — stage lines, then the final block. Everything else is in the files.
