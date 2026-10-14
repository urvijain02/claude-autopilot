---
name: provision-repo
description: Obtain working copies for a ticket by cloning remotes into an ephemeral, ticket-scoped, multi-repo workspace. The user provides the primary repo link at run time; connected repos found during analysis are added the same way. Used by the autopilot orchestrator.
---

# Provision repo

There is **no ticket→repo map** — a Jira project can span many repos. You get the primary repo from the user, and grow the set as analysis reveals dependencies. The workspace is multi-repo: `~/.claude/autopilot/work/<TICKET>/repos/<name>/`, one clone per repo, all disposable.

## Primary repo (at setup)

1. **Ask the user for the repo link** for this ticket — an `owner/repo` slug or a git URL. Do not guess; there's no map to fall back on.
2. Determine the base branch: `config.default_base_branch` (default `main`) unless the user specifies otherwise.
3. Clone and capture the path:
   ```bash
   REPO="$(${CLAUDE_PLUGIN_ROOT}/bin/provision-repo.sh <TICKET> --remote <owner/repo> --base <base>)"
   ```
   The final stdout line is the workspace path (`…/work/<TICKET>/repos/<name>`). Idempotent; `--fresh` forces re-clone.
4. Detect the stack: `${CLAUDE_PLUGIN_ROOT}/bin/detect-stack.sh "$REPO"`.
5. Record it in `state.json.repos[]` with `role: "primary"` (name, remote, path, branch_base, stack) — see state-protocol.

## Connected repos (during the run)

The requirements-analyst investigates the primary repo and lists any **connected repos** the change needs (a service it calls, a shared package/client, a consumer of a changed contract) in `requirements.md` → "Connected repos", each with *why* and a best-guess remote or "unknown".

When connected repos are identified, for each one:
- Resolve the remote: use the analyst's suggestion; if unknown, try `gh` within `config.orgs` to find a matching repo and **confirm with the user**; if still unresolved, **ask the user for the link**. (If `config.auto_expand_connected` is true, provision resolved ones without asking; always ask when a link can't be resolved.)
- Provision it into the same ticket workspace:
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/bin/provision-repo.sh <TICKET> --remote <owner/repo> --name <name> --base <base>
  ```
- Append it to `state.json.repos[]` with `role: "connected"`.

## Rules

- Never invent a remote. Ask when unsure — a wrong repo wastes the run.
- Config holds no repo paths or maps — only defaults and optional org hints.
**Remote form matters.** A full URL or `git@` remote is cloned with plain `git`, so GitHub and Bitbucket both work. A bare `owner/repo` is resolved against **GitHub only** — `config.orgs` and the `gh` search that suggests connected repos are GitHub-shaped. For a Bitbucket repo, pass the full URL (`https://bitbucket.org/<workspace>/<repo>.git`); the script says so if a bare slug fails.

**One name, three uses.** `provision-repo.sh` prints the workspace path as its last stdout line. Record `state.json.repos[].name` as the **basename of that path** — never a tidier name of your own. That single string is the workspace directory, the `<label>` you pass to every gate, and the `$STATE/gates/<label>/` directory. Invent a different one and gate verdicts are written under one name while provisioning clears another, so a re-provisioned clone silently keeps a stale `pass`.

- All repos for a ticket share one workspace and one central `$STATE`; every repo gets its own branch, gates (namespaced by `--label <name>`), and PR.
