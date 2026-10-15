#!/usr/bin/env bash
# Clone a repo into a ticket's multi-repo workspace. There is NO config map — the caller
# supplies the remote: the user provides the primary repo link at run time, and connected
# repos are discovered during analysis and provisioned the same way.
# Prints the workspace repo path as the final stdout line.
# Usage: provision-repo.sh <ticket> --remote <owner/repo|git-url> [--name <dir>] [--base <branch>] [--fresh]
#
# Repos live under ~/.claude/autopilot/work/<ticket>/repos/<name>/ — central, disposable,
# and outside any repo you maintain. Idempotent: an existing workspace is reused unless --fresh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/_paths.sh"
WORKSPACE_ROOT="$(resolve_workspace_root)"
expand_tilde() { printf '%s' "${1/#\~/$HOME}"; }

ticket=""; remote=""; name=""; base=""; fresh=0
while [ $# -gt 0 ]; do
  case "$1" in
    --remote) remote="$2"; shift 2 ;;
    --name)   name="$2"; shift 2 ;;
    --base)   base="$2"; shift 2 ;;
    --fresh)  fresh=1; shift ;;
    -*)       echo "unknown flag: $1" >&2; exit 2 ;;
    *)        if [ -z "$ticket" ]; then ticket="$1"; shift; else echo "unexpected arg: $1" >&2; exit 2; fi ;;
  esac
done
[ -n "$ticket" ] && [ -n "$remote" ] || {
  echo "usage: $(basename "$0") <ticket> --remote <owner/repo|git-url> [--name <dir>] [--base <branch>] [--fresh]" >&2; exit 2; }

# derive a workspace dir name from the remote if not given (e.g. org/service-api -> service-api)
if [ -z "$name" ]; then name="${remote##*/}"; name="${name%.git}"; fi

_safe_component ticket "$ticket" || exit 2
_safe_component name "$name" || exit 2

dest="$(expand_tilde "$WORKSPACE_ROOT")/${ticket}/repos/${name}"
echo "label: $name" >&2

if [ "$fresh" -eq 1 ] && [ -d "$dest" ]; then
  echo "--fresh: removing existing workspace $dest" >&2; rm -rf "$dest"
fi

# -e, not -d: a linked worktree has .git as a file, and treating that as "not a repo"
# would send it down the delete-and-clone path below.
cloned=0
if [ -e "$dest/.git" ]; then
  echo "workspace exists; leaving in place (use --fresh to re-clone): $dest" >&2
else
  # A directory with no .git is a clone that was interrupted. git clone refuses a
  # non-empty target, so leaving it wedges this ticket on every subsequent run with no
  # way out but manual deletion. Workspace clones are disposable, so there is nothing
  # here to preserve.
  if [ -d "$dest" ]; then
    echo "removing half-provisioned workspace (no .git): $dest" >&2; rm -rf "$dest"
  fi
  mkdir -p "$(dirname "$dest")"
  if [ -d "$remote" ]; then
    echo "provisioning local template/repo $remote -> $dest" >&2
    if [ -e "$remote/.git" ]; then
      git clone "$remote" "$dest" >&2
    else
      cp -r "$remote/." "$dest"
      git -C "$dest" init -b "${base:-main}" >&2
      git -C "$dest" add . >&2
      git -C "$dest" -c user.name="Claude Autopilot Sandbox" -c user.email="autopilot@local" commit -m "chore: initial sandbox baseline" >&2
    fi
  elif [[ "$remote" == *://* || "$remote" == git@* ]]; then
    echo "cloning (git) $remote -> $dest" >&2; git clone "$remote" "$dest" >&2
  else
    # A bare owner/repo carries no host, and both routes below assume GitHub. Say so on
    # failure: the same slug for a Bitbucket repo fails here with a GitHub not-found error
    # that gives no hint the fix is to pass a full URL.
    ok=1
    if command -v gh >/dev/null 2>&1; then
      echo "cloning (gh) $remote -> $dest" >&2
      gh repo clone "$remote" "$dest" >&2 || ok=0
    else
      echo "cloning (git https) $remote -> $dest" >&2
      git clone "https://github.com/${remote}.git" "$dest" >&2 || ok=0
    fi
    if [ "$ok" -eq 0 ]; then
      echo "could not clone '$remote' — a bare owner/repo is resolved against GitHub." >&2
      echo "For a Bitbucket repo pass the full URL instead, e.g." >&2
      echo "  https://bitbucket.org/<workspace>/<repo>.git" >&2
      exit 1
    fi
  fi
  # A verdict belongs to the tree that earned it, and this clone is new. $name is the
  # label the gates are written under; record a different one in state.json and this
  # clears nothing while the stale `pass` survives.
  cloned=1
  gates="$(resolve_state_root)/${ticket}/gates/${name}"
  if [ -d "$gates" ]; then
    echo "new clone: discarding stale gate verdicts in $gates" >&2; rm -rf "$gates"
  fi
fi

# Only on a clone we just made. A reused clone is already on this ticket's feature branch,
# and checking out the base would move it off the branch later stages expect.
if [ -n "$base" ] && [ "$cloned" -eq 1 ]; then
  git -C "$dest" fetch origin "$base" >&2 2>/dev/null || true
  git -C "$dest" checkout "$base" >&2
  git -C "$dest" pull --ff-only >&2 2>/dev/null || true
elif [ -n "$base" ]; then
  echo "reused workspace: staying on $(git -C "$dest" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?') rather than checking out $base" >&2
fi

echo "$dest"
