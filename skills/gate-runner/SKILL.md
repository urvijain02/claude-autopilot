---
name: gate-runner
description: How to run the deterministic quality gates (tests, build) against the target repo and interpret their verdicts. Bound by the test-writer, implementer, and fixer agents. Gates are the checks the model cannot talk its way past.
---

# Gate runner

Gates are **shell scripts**, not judgments. You run them; their exit code and the JSON they write are the truth. You never declare a gate "passed" from your own reasoning.

The scripts live in one place and run against any repo. Your briefing gives the repo you work on: its path (`$REPO`) and its name (`<label>`). Always pass **both** — `--repo "$REPO"` and `--label "<label>"` — so multi-repo verdicts don't collide.

## Commands

```bash
# tests — expects PASS
${CLAUDE_PLUGIN_ROOT}/bin/gate-tests.sh <TICKET> --repo "$REPO" --label "<label>"

# tests — TDD, expects FAIL (new failing tests, not yet implemented)
${CLAUDE_PLUGIN_ROOT}/bin/gate-tests.sh <TICKET> --repo "$REPO" --label "<label>" --expect-fail

${CLAUDE_PLUGIN_ROOT}/bin/gate-build.sh    <TICKET> --repo "$REPO" --label "<label>"
```

Each writes its verdict to `$STATE/gates/<label>/<gate>.json` (central, per-repo — see state-protocol) with `status` (`pass|fail|skipped|blocked`), `exit_code`, `repo`, and a `log_file` path. Don't construct that path from a default — `state_root` and `AUTOPILOT_STATE_DIR` relocate it, and the script prints the file it actually wrote on its last stdout line. The test/build commands run *inside* `$REPO`; you don't `cd` yourself and you don't choose the command by hand (the script auto-detects dotnet vs node). If `--label` is omitted it defaults to the repo dir name.

## Interpreting

- `pass` → proceed.
- `fail` → do **not** proceed. Read the `log_file`, fix, re-run. Report honestly in `log.md`.
- `skipped` → the tool/command wasn't available. Record it — a skipped gate is not a passed gate; say so.
- `blocked` → the gate **could not run** — an environment or tooling problem it couldn't work around, not a code defect. Do not "fix" code and do not loop: stop and escalate, quoting what the `log_file` actually shows. Read it before naming a cause; the ask depends on the reason. Two that occur today: a .NET NuGet restore hitting a private-feed 401 the offline-cache workaround couldn't resolve (ask for a valid Azure DevOps feed PAT, Packaging: Read), and a suite that exited non-zero without a test having run (a build error or a missing test script — a code or setup problem for the author, not a credential).

> **.NET restore is auto-handled.** For dotnet repos the gate first runs `ensure-dotnet-restore.sh`, which tries a normal restore, then an offline restore from the local NuGet cache on a 401. You don't do anything — a `blocked` verdict only appears if that fallback also failed.

## Non-negotiable

- Run the gate **after** the edit that's supposed to satisfy it, then read the JSON back.
- If a verdict is from an earlier round, it's stale — re-run.
