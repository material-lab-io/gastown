#!/bin/bash
# Gas Town → Slack event notifications
# Usage: slack-notify.sh <event-type>
# Events: session-start, session-stop, waiting-input
set -uo pipefail

CHANNEL="C0ADPNR9W7M"  # #mayor
REPLY_SCRIPT="/home/kanaba/.openclaw/workspaces/mayor/slack-reply.sh"

EVENT="${1:-unknown}"
ROLE="${GT_ROLE:-unknown}"

# Noise filter: skip start/stop for witnesses and refineries (they cycle constantly)
case "$EVENT" in
  session-start|session-stop)
    case "$ROLE" in
      */witness|*/refinery) exit 0 ;;
    esac
    ;;
esac

# Format message
case "$EVENT" in
  session-start)    MSG=":rocket: *${ROLE}* started a session" ;;
  session-stop)     MSG=":stop_sign: *${ROLE}* session ended" ;;
  waiting-input)    MSG=":raising_hand: *${ROLE}* is waiting for input" ;;
  *)                MSG=":bell: *${ROLE}* — ${EVENT}" ;;
esac

"$REPLY_SCRIPT" "$CHANNEL" "$MSG" >/dev/null 2>&1 || true
