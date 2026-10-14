#!/usr/bin/env bash
# Remove a ticket's whole ephemeral workspace (clones plus anything provisioning left
# beside them) after its PRs are opened.
# Usage: cleanup-workspace.sh <ticket> [--force]
# Does NOT touch central state (~/.claude/autopilot/state/<ticket>) — only the clones.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/_paths.sh"
WORKSPACE_ROOT="$(resolve_workspace_root)"
expand_tilde() { printf '%s' "${1/#\~/$HOME}"; }

ticket=""; force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    -*)      echo "unknown option: $1" >&2; exit 2 ;;
    *)       [ -z "$ticket" ] || { echo "unexpected argument: $1" >&2; exit 2; }
             ticket="$1"; shift ;;
  esac
done
[ -n "$ticket" ] || { echo "usage: $(basename "$0") <ticket> [--force]" >&2; exit 2; }

_safe_component ticket "$ticket" || exit 2

dir="$(expand_tilde "$WORKSPACE_ROOT")/${ticket}"
[ -d "$dir" ] || { echo "no workspace to remove at $dir"; exit 0; }

# Only ever delete something provision-repo built. Not overridable by --force:
# without this the target is trusted purely because ticket keys happen not to
# collide with real directory names, so a mis-set workspace_root would aim
# `rm -rf` at whatever sits at that path.
if [ ! -d "$dir/repos" ]; then
  echo "refusing to delete $dir — no repos/ subdirectory, so this is not a workspace" >&2
  exit 1
fi

if [ "$force" -eq 0 ]; then
  for repo in "$dir"/repos/*/; do
    [ -e "$repo/.git" ] || continue
    refuse=""

    if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      # A corrupt or unreadable .git fails every check below, which would otherwise read
      # as "no commits, nothing to lose" and delete whatever is there.
      refuse="git cannot inspect this work tree"
    elif ! git -C "$repo" rev-parse --verify -q HEAD >/dev/null 2>&1; then
      refuse=""            # valid work tree, genuinely no commits
    elif [ -n "$(git -C "$repo" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      # Tracked changes only. Untracked build output (obj/, bin/, node_modules) is left
      # by every gate run, and counting it would make the workspace undeletable forever.
      refuse="uncommitted changes to tracked files"
    elif upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"; then
      ahead="$(git -C "$repo" rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)"
      if [ "${ahead:-0}" -gt 0 ]; then
        refuse="$ahead commit(s) not pushed to $upstream"
      fi
    elif [ -z "$(git -C "$repo" branch -r --contains HEAD 2>/dev/null)" ]; then
      # A branch with no upstream is not "in sync" — it has never been pushed, so its
      # commits exist only here unless some remote ref already contains them.
      refuse="commits on a branch with no upstream"
    fi

    if [ -n "$refuse" ]; then
      echo "not deleting — $refuse: $repo (pass --force to override)" >&2
      exit 1
    fi
  done
fi

rm -rf "$dir"
echo "removed workspace: $dir"
