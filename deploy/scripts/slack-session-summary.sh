#!/bin/bash
# Post session summary to Slack #mayor channel on session end
# Works for all agents (mayor, crew, polecats)
set -euo pipefail

CHANNEL="C0ADPNR9W7M"  # #mayor
REPLY_SCRIPT="/home/kanaba/.openclaw/workspaces/mayor/slack-reply.sh"
export PATH="$HOME/go/bin:$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

ROLE="${GT_ROLE:-unknown}"

# Noise filter: skip for witnesses and refineries (they cycle constantly)
case "$ROLE" in
  */witness|*/refinery) exit 0 ;;
esac

# Collect recently closed beads (last 4 hours as session proxy)
# Filter out wisps (internal automation) and messages
SINCE=$(date -d '4 hours ago' '+%Y-%m-%dT%H:%M:%S')
CLOSED=$(bd list --status=closed --closed-after="$SINCE" --limit=0 2>/dev/null \
  | grep -v '\-wisp-\|\[message\]\|Showing' \
  | head -20 || true)

if [ -z "$CLOSED" ]; then
  "$REPLY_SCRIPT" "$CHANNEL" ":wave: *${ROLE}* session ended. No beads closed this session."
else
  COUNT=$(echo "$CLOSED" | wc -l | tr -d ' ')
  "$REPLY_SCRIPT" "$CHANNEL" ":white_check_mark: *${ROLE}* session ended. Closed $COUNT bead(s):
\`\`\`
$CLOSED
\`\`\`"
fi
