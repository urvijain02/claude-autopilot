#!/usr/bin/env bash
# Create (or reuse) a ticket's feature branch in a repo, applying the naming rule in code.
# Usage: create-branch.sh <TICKET-KEY> --repo <path> --type <effective-issue-type> --slug <text> [--base <branch>]
#
# Naming rule:
#   feat/   <- Task, Story
#   bugfix/ <- Bug, Development bug
#   (none)  <- Epic, or any other type
# Sub-tasks: the caller must pass the PARENT's issue type as --type (not "Sub-task").
# Branch = <prefix><TICKET-KEY>-<sanitized-slug>, cut from --base. Prints the final branch
# name as the last stdout line. An existing branch of that name is checked out as-is.
set -euo pipefail
expand_tilde() { printf '%s' "${1/#\~/$HOME}"; }

key=""; repo="."; type=""; slug=""; base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$(expand_tilde "$2")"; shift 2 ;;
    --type) type="$2"; shift 2 ;;
    --slug) slug="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    -*)     echo "unknown flag: $1" >&2; exit 2 ;;
    *)      if [ -z "$key" ]; then key="$1"; shift; else echo "unexpected arg: $1" >&2; exit 2; fi ;;
  esac
done
# --base is required. Without it `checkout -b` branches from whatever HEAD happens to be,
# which on a reused clone is the previous ticket's branch — the new branch would then carry
# that work into its diff, silently.
[ -n "$key" ] && [ -n "$type" ] && [ -n "$slug" ] && [ -n "$base" ] || {
  echo "usage: $(basename "$0") <TICKET-KEY> --repo <path> --type <issue-type> --slug <text> --base <branch>" >&2; exit 2; }
[ -d "$repo/.git" ] || { echo "not a git repo: $repo" >&2; exit 2; }

# normalize type: lowercase, strip spaces/underscores/hyphens
norm="$(printf '%s' "$type" | tr '[:upper:]' '[:lower:]' | tr -d ' _-')"
if [ "$norm" = "subtask" ]; then
  echo "sub-task: pass the PARENT's issue type as --type, not 'Sub-task'" >&2; exit 2
fi
case "$norm" in
  task|story)                  prefix="feat/" ;;
  bug|developmentbug|devbug)   prefix="bugfix/" ;;
  *)                           prefix="" ;;   # epic or anything else -> no prefix
esac

# sanitize slug: lowercase, spaces/underscores -> '-', keep [a-z0-9-], collapse/trim '-'
s="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | tr -cd 'a-z0-9-' | sed -E 's/-+/-/g; s/^-//; s/-$//')"
[ -n "$s" ] || { echo "slug is empty after sanitizing: '$slug'" >&2; exit 2; }

branch="${prefix}${key}-${s}"

if git -C "$repo" show-ref --verify --quiet "refs/heads/${branch}"; then
  git -C "$repo" checkout "$branch" >&2
else
  git -C "$repo" checkout -b "$branch" "$base" >&2
fi
echo "$branch"
