# autopilot

Takes a Jira ticket through to open pull requests without supervision.

Failing tests are written before the production change, stage outcomes are decided by shell scripts rather than by the model reading its own work, and the review is done by a separate agent on a stronger model tier than the one that wrote the code — then looped through analyse and fix. At the iteration cap it escalates if anything blocking survives, and ships with the leftovers recorded if only minor findings remain.

It works across several repos in one run, clones what it needs into a throwaway workspace (nothing has to be checked out beforehand), and picks up where it left off if a run is interrupted.

## Install

```bash
/plugin marketplace add urvijain02/claude-autopilot
```

```bash
/plugin install autopilot@claude-autopilot
```

Restart Claude Code afterwards. On the next start, `~/.claude/autopilot/config.json` is created for you from the shipped template.

## Set up

**Nothing is strictly required** — the pipeline runs with the config exactly as shipped. The one value worth setting first is `slack_channel`: without it the PR-link post is skipped and logged rather than sent somewhere arbitrary.

Your config is at `~/.claude/autopilot/config.json`, created on first start. (`AUTOPILOT_HOME` moves it — see [Where things live](#where-things-live).)

| Key | Ships as | What it does |
|---|---|---|
| `slack_channel` | *empty* | Channel id (`C0…`) the PR links get posted to. Empty means the post is skipped and logged. |
| `jira_site` | *empty* | Optional. Host for Atlassian Cloud (e.g. `your-team.atlassian.net`). If empty, Jira transitions skip and prompt-mode applies. |
| `human_gates` | `false` | `true` pauses for plan approval and pre-commit sign-off. No effect on the quality gates — see *Two kinds of gate*. |
| `cleanup_after_pr` | `false` | `true` deletes a ticket's clones once its PRs are open. A run's output under `state_root` is kept either way. |
| `default_base_branch` | `main` | Base branch to branch from when the ticket doesn't imply one. |
| `state_root` | `~/.claude/autopilot/state` | Where a run's durable output lands. Point it somewhere browsable if you'd rather read runs outside `~/.claude`. A value containing a quote or backslash needs `jq` or `python3` — see *Requirements*. |
| `workspace_root` | `~/.claude/autopilot/work` | Where the throwaway clones go. Move it if the repos you work on are large. |
| `orgs` | `[]` | Optional. GitHub orgs or username searched to resolve a connected repo that analysis names. Empty means you're always asked for the link. Bare `owner/repo` is GitHub-only; Bitbucket needs a full URL. |
| `auto_expand_connected` | `false` | `true` clones connected repos without confirming each one first. |
| `jira_transitions` | `{}` | Fills itself in. The first time a project's in-progress or in-review status can't be matched automatically you're asked once, and the answer is cached per project key. |

## Requirements

| Need | Missing means |
|---|---|
| `gh`, authenticated | **Critical** — no cloning private repos, no PRs |
| `git` | **Critical** — no branches or commits |
| An Atlassian MCP — the standalone server or the claude.ai connector | Jira steps skip: the ticket isn't assigned or moved |
| Slack MCP | The PR-link post skips |
| `jq` **or** `python3` | Optional. Only needed to read `state_root` / `workspace_root` out of your config when the value isn't a plain one-line string. With neither installed and such a value set, the scripts stop rather than silently write gate output somewhere the pipeline won't read it. |

`preflight` checks the first four before anything else runs and tells you exactly what will be skipped, so a missing tool surfaces up front rather than three stages in.

## Use it

```
/autopilot:engage PROJ-123
```

It also answers to plain requests — "run autopilot on PROJ-123", "engage autopilot on PROJ-123".

Re-running on a ticket already underway **resumes** it from `state.json` rather than starting over:

```
/autopilot:engage PROJ-123                  resume, or start if it's new
/autopilot:engage PROJ-123 --from review    redo from a named phase
/autopilot:engage PROJ-123 --restart        start over (asks first; archives the old run)
/autopilot:engage                          list every run that isn't finished
```

One invocation carries the ticket all the way to open PRs — it doesn't stop to ask you to approve anything. If the session dies partway, nothing is lost: state is on disk after every transition, so running the same command again picks up where it stopped.

One ticket per run.

### Two kinds of gate, don't confuse them

"Unsupervised" means nobody is asked to click approve. It does not mean unchecked.

- **Quality gates** — tests and build, run by shell scripts that write `pass`/`fail` to disk. The orchestrator has to read those files before it advances. Always on, not configurable, and the reason the run can be trusted without you watching it.
- **Human gates** — the pauses for you to approve a plan or sign off before commit. Off by default. Set `human_gates: true` in your config if you'd rather it stop and wait at those points.

## Where things live

| | |
|---|---|
| The plugin's own scripts | inside the installed plugin — you never need this path |
| `~/.claude/autopilot/config.json` | your settings |
| `~/.claude/autopilot/state/<TICKET>/` | a run's output: spec, test plan, findings, gate verdicts, `log.md` |
| `~/.claude/autopilot/work/<TICKET>/repos/` | the throwaway clones |

Those paths are defaults. `state_root` and `workspace_root` in your config move the last two, and the `AUTOPILOT_HOME` environment variable moves all of it at once — it's the anchor the rest hang off, resolved in one place (`bin/_paths.sh`). Everything under it is yours and survives plugin updates. No pipeline artifact is ever written into a repo: the spec, plan, findings, gate verdicts and `log.md` all live under `state_root`. The clone itself does accumulate ordinary build output — `obj/`, `bin/`, `node_modules/` — because the gates run real build and test commands inside it. That's the reason the clone is disposable and the state dir isn't.

To relocate the root workspace and config:

```bash
# macOS / Linux (in ~/.bashrc or ~/.zshrc)
export AUTOPILOT_HOME="$HOME/.custom-autopilot"

# Windows (in PowerShell profile or Environment Variables)
$env:AUTOPILOT_HOME = "D:\autopilot"
```

## Permission prompts

The gate and provision scripts run through **POSIX Bash** (native on macOS/Linux; via Git Bash or WSL on Windows), so the first time each one is used you'll get a permission prompt showing its full path. Choosing the always-allow option persists it, and after the first run you won't see them again. If you'd rather pre-approve them, copy the paths out of those prompts into your own settings — they're stable for an installed version.

## Reading a run

The session output is deliberately thin — one line per stage and a summary block at the end. Everything else is on disk under `state_root/<TICKET>/`: `requirements.md`, `test-plan.md`, `review-findings-*.json`, `fix-list-*.json`, the gate verdicts under `gates/`, and `log.md`, which carries every decision the run made along with why and what it rejected.

## Releasing

The version appears in **two** files and both must be bumped together — `.claude-plugin/plugin.json` and the plugin's entry in `.claude-plugin/marketplace.json`. Bump one and the marketplace advertises a version that differs from what installs.

## Citation & Attribution

If this autonomous architecture, TDD quality gate design, or state-protocol informs your research, engineering projects, or agent pipelines, please attribute the work:

```bibtex
@software{jain2026claudeautopilot,
  author = {Urvi Jain},
  title = {Claude Autopilot: Autonomous SWE-Agent Pipeline with Deterministic TDD Quality Gates},
  year = {2026},
  publisher = {GitHub},
  journal = {GitHub repository},
  howpublished = {\url{https://github.com/urvijain02/claude-autopilot}}
}
```

Or reference in markdown:
> **Claude Autopilot** by [Urvi Jain](https://github.com/urvijain02) — [github.com/urvijain02/claude-autopilot](https://github.com/urvijain02/claude-autopilot)

## Maintainer

[Urvi Jain](https://github.com/urvijain02). Open an issue on this repo for bugs, or send a PR.
