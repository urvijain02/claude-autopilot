---
name: ticket-updates
description: Jira status transitions + assignee, and the Slack notification, for the autopilot pipeline. Moves the ticket to its in-progress status at the start and its in-review status after PRs, assigns it to whoever is running the pipeline, and posts the PR link to the configured Slack channel. Used by the autopilot orchestrator.
---

# Ticket updates (Jira + Slack)

These are **ticket-level** actions — once per run, not per repo. If the relevant MCP isn't connected (see preflight), **skip gracefully**: log the skip in `log.md`, note it in the final block, continue the run.

## Jira (Atlassian MCP)

`cloudId` comes from `config.jira_site` (e.g. `yourcompany.atlassian.net`). If it's unset or a call fails with a cloudId or permission error, resolve it with `getAccessibleAtlassianResources` and use that.

**At run start** (before requirements):

1. Resolve the runner dynamically: `atlassianUserInfo` → `account_id`.
2. Assign the ticket to that account: `editJiraIssue` with `fields.assignee.accountId`.
3. Move it to the project's in-progress status (see *Resolving a status* below). If it's already there, skip.

**After all PRs are open** (before cleanup):

4. Move it to the project's in-review status, resolved the same way.

### Resolving a status

Status names differ per project, so never assume them. Call `getTransitionsForJiraIssue` and pick from what it actually offers:

1. If `config.jira_transitions.<PROJECT>` already records a target status name for this step, find the offered transition whose `to.name` matches it case-insensitively and take it.
2. Otherwise match `to.name` case-insensitively against the candidates for the step, in order, and take the first hit:
   - **start** → `In Progress`, `In Development`, `Doing`, `Start Progress`
   - **review** → `In Review`, `Code Review`, `Review`, `Ready for review`, `Peer review`
3. Exactly one hit → use it and log a `Decision:` block naming the transition and why.
4. No hit → **ask the user once**, listing the offered status names, then write their answer to `config.jira_transitions.<PROJECT>.<step>` so later runs are silent.
5. Nobody to ask (running unattended) → **skip the transition and log it**. Never guess a status on someone else's board, and never force a transition the API didn't offer.

Cache the target **status name**, not the transition id: which transitions exist depends on where the ticket currently sits, so a stored id goes stale while a stored name can be re-resolved.

Do **not** resolve a status by its `statusCategory`. Categories are coarse (`To Do` / `In Progress` / `Done`) and workflows routinely put several statuses in one — a board can offer `In Progress`, `In Review`, `Ready for test` and `Blocked` all under the `In Progress` category, and land `Ready for release` under `Done`.

## Slack (Slack MCP)

Channel: `config.slack_channel` — a channel id (e.g. `C0…`). If it's unset, skip the post and log it rather than guessing a channel. Post with `slack_send_message` once, after the PR(s) are open.

Format — a header line, then each PR URL on its **own** line (so Slack doesn't fold the link), with **contributors / @-mentions excluded**. **Do not start the message with the ticket KEY** — it's already in the PR title.

Single repo:
```
Ready for technical review — <PR title>
<PR URL>
```
Multi-repo (one header, one URL per line):
```
Ready for technical review — <short ticket summary>
<PR URL — repo A>
<PR URL — repo B>
```

Record the ticket's new status and the posted message link in `state.json`.
