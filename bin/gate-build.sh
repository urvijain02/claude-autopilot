#!/usr/bin/env bash
# Compile / typecheck a target repo. Records a central verdict.
# Usage: gate-build.sh <ticket> --repo <path>
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${here}/_gate_lib.sh"
parse_args "$@"

# A repo's typecheck/build script is not always in the ROOT package.json: a nested-workspace
# monorepo (client/, server/, packages/*) keeps them in the subpackage while the root holds only
# orchestration. Searching the root alone finds nothing, and an empty command is written as
# `skipped` with exit 0 — indistinguishable from a pass to the caller. A repo whose tests live in
# one workspace and whose typechecked source lives in another then advances with its source never
# compiled. Script names vary too (typecheck / type-check / tsc), and matching parsed JSON keys
# rather than grepping avoids a script that merely CONTAINS the word.
_pkg_script() {  # <package.json> <name>... -> prints the first script name that exists
  local f="$1"; shift
  [ -f "$f" ] || return 1
  node -e '
    const fs=require("fs");
    let p; try{p=JSON.parse(fs.readFileSync(process.argv[1],"utf8"))}catch{process.exit(1)}
    const s=(p&&p.scripts)||{};
    for(const n of process.argv.slice(2)) if(Object.prototype.hasOwnProperty.call(s,n)){console.log(n);process.exit(0)}
    process.exit(1)
  ' "$f" "$@" 2>/dev/null
}

node_build_cmd() {
  local repo="$1" n rel
  local names=(typecheck type-check tsc build)
  # The root wins when it declares one: it is the repo's own entry point and may itself fan out.
  if n="$(_pkg_script "$repo/package.json" "${names[@]}")"; then printf 'npm run %s' "$n"; return; fi

  # Otherwise run every workspace that declares one. The gate fails if ANY fails: a monorepo
  # where only half the source compiles is not a pass.
  local -a dirs=() cmds=()
  while IFS= read -r rel; do [ -n "$rel" ] && dirs+=("$rel"); done < <(
    node -e '
      const fs=require("fs"),path=require("path"),root=process.argv[1];
      let ws=[]; try{const p=JSON.parse(fs.readFileSync(path.join(root,"package.json"),"utf8"));
        ws=Array.isArray(p.workspaces)?p.workspaces:((p.workspaces&&p.workspaces.packages)||[])}catch{}
      const out=new Set(), add=d=>{try{if(fs.existsSync(path.join(root,d,"package.json")))out.add(d)}catch{}};
      for(const w of ws){
        if(w.includes("*")){const base=w.replace(/\/?\*+$/,"");
          try{for(const e of fs.readdirSync(path.join(root,base),{withFileTypes:true})) if(e.isDirectory()) add(base+"/"+e.name)}catch{}}
        else add(w);
      }
      for(const d of ["client","server","frontend","backend","web","api","app"]) add(d);
      for(const base of ["packages","apps"]){
        try{for(const e of fs.readdirSync(path.join(root,base),{withFileTypes:true})) if(e.isDirectory()) add(base+"/"+e.name)}catch{}
      }
      for(const d of out) console.log(d);
    ' "$repo" 2>/dev/null
  )
  for rel in "${dirs[@]}"; do
    _safe_path "workspace directory" "$rel" || continue
    if n="$(_pkg_script "$repo/$rel/package.json" "${names[@]}")"; then
      cmds+=("npm run $n --prefix '$rel'")
    fi
  done
  [ "${#cmds[@]}" -eq 0 ] && return 0
  local joined="${cmds[0]}" i
  for ((i=1; i<${#cmds[@]}; i++)); do joined="$joined && ${cmds[$i]}"; done
  printf '%s' "$joined"
}

stack="$(detect)"
log="$(gates_dir)/build.log"
mkdir -p "$(gates_dir)"
# Truncated once, then appended to, so the restore trail shares the verdict's log.
: > "$log"

case "$stack" in
  dotnet) cmd="dotnet build --nologo" ;;
  node)   cmd="$(node_build_cmd "$REPO")" ;;
  *)      cmd="" ;;
esac

if [ -z "$cmd" ]; then
  write_verdict build skipped 0 "$stack" "none" "$log"
  echo "no build/typecheck command in $REPO; skipping build gate"; exit 0
fi

# .NET: ensure restore works (auto offline-cache workaround on a private-feed 401).
if [ "$stack" = "dotnet" ]; then
  # Not under $STATE: that is the durable audit trail and nothing ever reclaims it,
  # while fallback B can put a copy of the package cache here. The workspace is
  # outside the repo too and cleanup-workspace removes it with the clones.
  ovr="$(resolve_workspace_root)/${TICKET}/.nuget-override/${LABEL}"; rm -rf "$ovr"
  rc=0; "${here}/ensure-dotnet-restore.sh" "$REPO" "$ovr" >> "$log" 2>&1 || rc=$?
  if [ "$rc" -eq 3 ]; then
    write_verdict build blocked 3 "$stack" "dotnet restore blocked (private-feed 401)" "$log"
    echo "restore blocked — needs a valid ADO feed credential; escalate to human" >&2
    exit 3
  fi
fi

# This command's own implicit restore needs the override too (see ensure-dotnet-restore).
if [ -f "${ovr:-}/nuget.config" ]; then
  cmd="$cmd /p:RestoreConfigFile=\"$ovr/nuget.config\""
fi

set +e
run_in_repo "$cmd" >> "$log" 2>&1
code=$?
set -e

[ "$code" -eq 0 ] && st=pass || st=fail
write_verdict build "$st" "$code" "$stack" "$cmd" "$log"
[ "$code" -eq 0 ]
