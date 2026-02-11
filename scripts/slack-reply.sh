#!/bin/bash
# Send a message to a Slack channel as the Mayor bot
# Usage: slack-reply.sh <channel_id> "message text"
# Example: slack-reply.sh C0ADPNR9W7M "Hello from the Mayor!"

set -euo pipefail

[ -f "$HOME/.gt/.env" ] && source "$HOME/.gt/.env"

BOT_TOKEN="${SLACK_BOT_TOKEN:?SLACK_BOT_TOKEN not set — add it to ~/.gt/.env}"

if [ $# -lt 2 ]; then
  echo "Usage: $0 <channel_id> <message>"
  echo "  channel_id: C0ADPNR9W7M (#mayor) or D... (DM)"
  exit 1
fi

CHANNEL="$1"
shift
MESSAGE="$*"

RESPONSE=$(curl -s -X POST "https://slack.com/api/chat.postMessage" \
  -H "Authorization: Bearer $BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg ch "$CHANNEL" --arg msg "$MESSAGE" '{channel: $ch, text: $msg}')")

OK=$(echo "$RESPONSE" | jq -r '.ok')
if [ "$OK" = "true" ]; then
  echo "Sent to $CHANNEL"
else
  echo "FAILED: $(echo "$RESPONSE" | jq -r '.error')" >&2
  exit 1
fi
