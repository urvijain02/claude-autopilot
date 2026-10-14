#!/usr/bin/env bash
# Runs on SessionStart. Creates ~/.claude/autopilot/ and seeds config.json from
# the shipped template on first install.
#
# Defensive throughout: a session must start even if this can't do its job, so
# every step is guarded and the script always exits 0.
set -uo pipefail

AUTOPILOT_HOME="${AUTOPILOT_HOME:-$HOME/.claude/autopilot}"
CONFIG="$AUTOPILOT_HOME/config.json"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || exit 0
TEMPLATE="$here/../config.template.json"

[ -f "$TEMPLATE" ] || exit 0
[ -f "$CONFIG" ] && exit 0

mkdir -p "$AUTOPILOT_HOME/state" "$AUTOPILOT_HOME/work" 2>/dev/null || exit 0
cp "$TEMPLATE" "$CONFIG" 2>/dev/null || exit 0

echo "autopilot: config created at $CONFIG"
echo "  → set \"jira_site\" to your Atlassian host, e.g. yourcompany.atlassian.net"
echo "  → set \"slack_channel\" to the channel id for PR links (left empty, the post is skipped)"
exit 0
