#!/usr/bin/env bash
# Make a .NET repo restore-able. Codifies the offline workaround the pipeline kept
# re-discovering: on a 401/NU1301 against private package feeds (e.g. Azure DevOps, GitHub Packages), restore from the
# machine's already-populated local NuGet cache.
# If even that fails, exit 3 so the caller escalates to a human (needs valid feed creds).
#
# Nothing is written inside the target repo: a generated nuget.config there would replace
# the repo's own feed configuration. The override and the fallback feed live outside it and
# the restore is pointed at them with --configfile.
#
# <override-dir> is where a working override is left for the caller. Without it the
# override dies with this process, and the gate's own `dotnet build`/`dotnet test` would
# implicitly re-restore using the repo's config and hit the dead feed again — so the
# caller must pass it and add /p:RestoreConfigFile=<dir>/nuget.config to its command.
#
# Usage: ensure-dotnet-restore.sh <repo> [override-dir]
# Exit:  0 = restore ok (normal, or via workaround, or a non-auth failure left for the
#            gate to surface naturally) · 2 = usage · 3 = BLOCKED, escalate to human.
set -uo pipefail
repo="${1:?usage: ensure-dotnet-restore.sh <repo>}"
[ -d "$repo" ] || { echo "repo not found: $repo" >&2; exit 2; }

tmp="$(mktemp -d)" || { echo "cannot create temp dir" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT
log="$tmp/restore.log"

outdir="$tmp"
if [ -n "${2:-}" ]; then
  mkdir -p "$2" 2>/dev/null && outdir="$2"
fi
cfg="$outdir/nuget.config"

# With an argument, restore through that config instead of whatever the repo specifies.
restore() {
  if [ -n "${1:-}" ]; then
    ( cd "$repo" && dotnet restore --configfile "$1" ) > "$log" 2>&1
  else
    ( cd "$repo" && dotnet restore ) > "$log" 2>&1
  fi
}
is_auth_fail() { grep -qiE 'NU1301|401 \(Unauthorized\)|Unauthorized|status code.*401' "$log"; }

# 1) Normal restore — respects the repo's own config.
if restore; then echo "restore: ok"; exit 0; fi

# 2) Not the known private-feed auth failure? Leave it — the gate will fail naturally
#    on the real error (that's a genuine defect, not something to work around).
if ! is_auth_fail; then
  echo "restore failed for a non-auth reason — leaving it for the gate to surface:" >&2
  tail -15 "$log" >&2; exit 0
fi

echo "restore hit private-feed 401/NU1301 — applying offline workaround from the local cache" >&2
GP="$(dotnet nuget locals global-packages --list 2>/dev/null | sed -E 's/^[^:]*:[[:space:]]*//' | head -1)"
[ -d "$GP" ] || GP="$HOME/.nuget/packages"

# Fallback A: clear sources → nuget.org only, reuse the already-extracted global cache.
cat > "$cfg" <<XML
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <config><add key="globalPackagesFolder" value="$GP" /></config>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
XML
if restore "$cfg"; then echo "restore: ok (offline — cache only)"; exit 0; fi

# Fallback B: add a folder feed built from the cached .nupkg files. It sits beside the
# override config, never inside the working copy, and the config references it by path —
# so both have to outlive this process for the caller's build to restore.
feed="$outdir/feed"; mkdir -p "$feed"
# Hard-linked where possible: a link is the same file to NuGet but costs no disk, and the
# cache can run to gigabytes. cp is the cross-filesystem fallback.
find "$GP" -name '*.nupkg' -exec sh -c 'ln "$1" "$2/" 2>/dev/null || cp -n "$1" "$2/" 2>/dev/null' _ {} "$feed" \; 2>/dev/null || true
cat > "$cfg" <<XML
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <config><add key="globalPackagesFolder" value="$GP" /></config>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="local-cache" value="$feed" />
  </packageSources>
</configuration>
XML
if restore "$cfg"; then echo "restore: ok (offline — cache + local feed)"; exit 0; fi

echo "OFFLINE WORKAROUND FAILED — a required package is not in the local cache." >&2
echo "HUMAN INTERVENTION NEEDED: provide a valid Azure DevOps feed credential (Packaging: Read)." >&2
tail -15 "$log" >&2; exit 3
