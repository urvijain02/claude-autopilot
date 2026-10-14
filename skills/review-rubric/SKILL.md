---
name: review-rubric
description: Adversarial code-review rubric and the finding/verdict schema. Bound by the code-reviewer (produces findings) and the review-analyst (triages them). Independent, skeptical review — never rubber-stamp.
---

# Review rubric

You are reviewing a diff you did NOT write. Your job is to find reasons it is wrong, not to confirm it looks fine. Default to skepticism. A clean review must be *earned*, not assumed.

> Independence note: you run in a separate context from the implementer and (per the pipeline config) on a stronger model tier. That separation is what makes this real verification rather than the author narrating its own work. When a genuinely different model (e.g. Codex) is available, it belongs here — but the deterministic gates carry the weight regardless.

## What to inspect

Read the change — `git diff <base>` for tracked edits and `git ls-files --others --exclude-standard` for new files, since nothing is committed at review time — plus `requirements.md` and `test-plan.md`, then check:

- **Correctness** — off-by-one, null/None, boundary conditions, error paths, concurrency, wrong operator, inverted condition.
- **Requirements fit** — does the change actually satisfy every item in `requirements.md`? Anything missed or over-built?
- **Test adequacy** — do the tests cover the requirement, or just the happy path? Any behavior asserted nowhere?
- **Security** — injection, authz gaps, unsafe deserialization, secrets in code, unvalidated input at boundaries.
- **Regressions** — could this break an existing caller? Is anything relied upon elsewhere changed?
- **Comment hygiene** — review every code comment the diff adds or touches against the standard below; each violation is a finding (`nit`, or `minor` if pervasive). These findings are **cheap and required — accept and fix them, don't ship them** (the team holds code comments to this bar). A comment violates the standard if it:
  - narrates *what* the code does or its control flow ("branch on the classification…", "loop over the items…") instead of a non-obvious *why*;
  - comments the *absence* of code ("not special-cased here because…", "no policy registered here");
  - repeats a cross-cutting rationale at multiple call sites instead of stating it once at its single source of truth;
  - restates a mapping/behaviour the code or an enum's member docs already make clear (e.g. `// 409 → DLQ` next to `Conflict => Dlq`);
  - contains a ticket/JIRA key (`PROJ-123:`), acceptance-criterion ref (`AC3:`), finding ID (`F5`), or process/history note ("used to…", "replaces the old…", "before this ticket", "TDD red state");
  - runs to multiple sentences / a step-by-step essay where one line would do;
  - uses jargon, abstract or uncommon words, or convoluted phrasing where a teammate would use plain language (*benign, no-op, idempotent, tallied, disambiguate*), or restates an opaque flag ("carrying Data=true") instead of saying what it means — if a competent teammate can't read it on the first pass, it's a finding. This also covers **identifier names**: an abstract adjective like `benignSkip` where the concrete condition (`hasNoAdminAccess`) would read plainly is the same violation.
  A comment is acceptable only when it captures a non-obvious platform/framework behaviour or gotcha, a deliberate-and-surprising choice, or a warning of a consequence a competent reader could not infer from the code. When in doubt, the comment should not exist.

### Three things a diff cannot tell you

A diff shows changed lines and a little surrounding context. Two of the items above cannot be answered from that alone, so reach outside it — bounded by the change, not a sweep of the repo:

- **Callers.** For any changed public signature, exported symbol or contract, `grep` the repo for its users and check each one still holds. Otherwise "could this break an existing caller" is not a question you have actually asked.
- **The enclosing file.** For any non-trivial change, read the whole file rather than the hunk. A guard clause added above an early return, or a condition inverted relative to how the method is really called, reads correct in a diff and wrong in the file.
- **The tests that already exist.** Before judging test adequacy, look at what already covers the touched area. "Asserted nowhere" is a guess until you have looked.

## Output — `$STATE/review-findings-<label>.json`

Write it to the central state dir defined by `state-protocol`, one file per repo, named with that repo's `<label>`. Never a path relative to the target repo — pipeline files must not land inside the repo under review.

Report **every** issue you find, including low-severity and uncertain ones — do not self-filter for importance here; the analyst stage triages. For each finding give `severity`, `file`, `line`, a one-line `summary`, a `rationale` (why it's a defect, ideally a concrete failing input), and your `confidence`.

Set the top-level **`iteration`** to the current `state.json.iteration`. The orchestrator uses it to tell this round's findings from a previous round's leftovers, so a file without it is treated as stale and the stage is re-run.

Set the top-level `verdict`:
- `BLOCKING` — at least one `blocking` or `major` finding. The loop must continue.
- `NON_BLOCKING` — only `minor`/`nit` findings. The orchestrator decides whether to fix or ship.
- `CLEAN` — nothing found after a genuine adversarial pass.

## For the review-analyst (stage 6)

Take `$STATE/review-findings-<label>.json` and produce `$STATE/fix-list-<label>.json`, carrying the same top-level **`iteration`** as the findings file it came from — a fix list without it is treated as stale and the stage is re-run. For each finding decide `accepted: true/false`. Reject a finding only with an explicit `reason_if_rejected` (false positive, out of scope, already handled). Every accepted finding becomes a concrete `action` + `files` for the fixer. Adversarially verify blockers before accepting — a plausible-but-wrong finding shouldn't gate the run.
