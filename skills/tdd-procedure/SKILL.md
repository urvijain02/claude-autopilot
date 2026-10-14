---
name: tdd-procedure
description: Test-Driven procedure — write tests that fail first, then make them pass. Bound by the test-writer (writes failing tests) and referenced by the implementer (makes them pass). Gives the pipeline an objective done-signal.
---

# TDD procedure

The failing-tests-first step is a forcing function: an objective, machine-checkable definition of "done" that no one can fake. Gates run against the target repo — `$REPO` is the `path` of that repo's entry in `state.json.repos[]`, and `<label>` its `name`. You are briefed with one repo per invocation; there is no single top-level repo path. See gate-runner.

## For the test-writer (stage 3)

1. Read `requirements.md` and `test-plan.md` from `$STATE`.
2. For each behavior the plan marks **unit** or **integration**, write a test in `$REPO` that encodes the expected behavior of the not-yet-written change.
3. Confirm they fail for the right reason:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/gate-tests.sh <TICKET> --repo "$REPO" --label "<label>" --expect-fail
   ```
   Three outcomes, and they are not interchangeable:
   - `pass` — ran and failed as expected. This is the red state you want; continue.
   - `fail` — the suite passed when it should have failed, or no test file was added or changed, so nothing new is being exercised. **Fix the tests.**
   - `blocked` — the gate couldn't run at all. **Do not touch the tests and do not loop** — stop and escalate (see gate-runner).
4. Do **not** write production code. Behaviors marked **manual** get a checklist line in `test-plan.md`, not an automated test.
5. Behaviors marked **none** get no new automated test and no checklist line beyond the planner's noted reason. If a repo's plan has **zero** new unit/integration rows, the red-first authoring step is a no-op for that repo — **but the existing test suite is still run and must be green** at the implement/fix/commit gates. "No new tests" is not "no tests run." The tests gate is recorded `pass` whenever a suite exists and passes, and `skipped` only when the gate script recognises no stack to run at all. When no new failing test was authored, the done-signal is **green existing suite + green build + CLEAN review** — never a skipped or red suite.

## For the implementer (stage 4)

1. Write the smallest change in `$REPO` that makes the failing tests pass.
2. Verify (normal mode):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/gate-tests.sh <TICKET> --repo "$REPO" --label "<label>"
   ${CLAUDE_PLUGIN_ROOT}/bin/gate-build.sh <TICKET> --repo "$REPO" --label "<label>"
   ```
3. Both must be `pass` before handing off. If either fails, fix and re-run — never hand off a red gate.
