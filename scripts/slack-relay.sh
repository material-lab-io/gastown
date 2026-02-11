#!/bin/bash
# Slack ↔ Mayor Relay
# Polls Slack channels for new messages and forwards to gt mail inbox.
# Mayor responds by calling: slack-reply.sh <channel> "message"

set -uo pipefail

[ -f "$HOME/.gt/.env" ] && source "$HOME/.gt/.env"

BOT_TOKEN="${SLACK_BOT_TOKEN:?SLACK_BOT_TOKEN not set — add it to ~/.gt/.env}"
BOT_USER_ID="U0ADEC6M8T1"
STATE_DIR="/home/kanaba/.openclaw/workspaces/mayor/.slack-state"
POLL_INTERVAL=4
LOG="/home/kanaba/.openclaw/workspaces/mayor/slack-relay.log"

# Channels to monitor: #mayor + all DMs
CHANNELS=(
  "C0ADPNR9W7M"   # #mayor channel
)

mkdir -p "$STATE_DIR"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

resolve_user() {
  local uid="$1"
  local cache="$STATE_DIR/user-$uid"
  if [ -f "$cache" ]; then
    cat "$cache"
    return
  fi
  local name
  name=$(curl -s -H "Authorization: Bearer $BOT_TOKEN" \
    "https://slack.com/api/users.info?user=$uid" | \
    jq -r '.user.real_name // .user.name // "unknown"')
  echo "$name" > "$cache"
  echo "$name"
}

# Discover DM channels on startup
discover_dms() {
  local dms
  dms=$(curl -s -H "Authorization: Bearer $BOT_TOKEN" \
    "https://slack.com/api/conversations.list?types=im&limit=50" | \
    jq -r '.channels[]? | select(.is_im == true) | .id')
  for dm in $dms; do
    # Only add if not already in CHANNELS
    local found=0
    for existing in "${CHANNELS[@]}"; do
      [ "$existing" = "$dm" ] && found=1 && break
    done
    [ "$found" -eq 0 ] && CHANNELS+=("$dm")
  done
  log "Monitoring ${#CHANNELS[@]} channels: ${CHANNELS[*]}"
}

poll_channel() {
  local channel="$1"
  local ts_file="$STATE_DIR/ts-$channel"
  local oldest
  oldest=$(cat "$ts_file" 2>/dev/null || echo "0")

  local response
  response=$(curl -s -H "Authorization: Bearer $BOT_TOKEN" \
    "https://slack.com/api/conversations.history?channel=$channel&oldest=$oldest&limit=10")

  local ok
  ok=$(echo "$response" | jq -r '.ok')
  if [ "$ok" != "true" ]; then return 0; fi

  # Advance timestamp past ALL messages (including bot) to avoid getting stuck
  local max_ts
  max_ts=$(echo "$response" | jq -r '[.messages[]?.ts // empty] | map(tonumber) | max // empty')
  if [ -n "$max_ts" ]; then
    echo "$max_ts" > "$ts_file"
  fi

  # Process human messages only: skip bot's own, sort ascending by ts
  echo "$response" | jq -r --arg bot "$BOT_USER_ID" \
    '[.messages[]? | select(.user != $bot and .bot_id == null and .subtype == null)] | sort_by(.ts) | .[] | "\(.ts)|\(.user)|\(.text)"' | \
  {
  while IFS='|' read -r ts user text; do
    [ -z "$ts" ] && continue
    local username
    username=$(resolve_user "$user")
    local send_err
    send_err=$(gt mail send mayor/ -s "slack:${username}:${channel}" -m "$text" 2>&1) && \
      log "→ ${username}: ${text:0:80}" || \
      log "FAIL forwarding from ${username}: ${send_err}"
  done
  true
  }
}

# Initialize: set timestamps to NOW so we don't replay old messages
init_timestamps() {
  local now
  now=$(date +%s)
  for channel in "${CHANNELS[@]}"; do
    local ts_file="$STATE_DIR/ts-$channel"
    [ ! -f "$ts_file" ] && echo "$now" > "$ts_file"
  done
}

# Main
log "=== Slack Relay starting ==="
discover_dms
init_timestamps
log "Polling every ${POLL_INTERVAL}s"

while true; do
  for channel in "${CHANNELS[@]}"; do
    poll_channel "$channel"
  done
  sleep "$POLL_INTERVAL"
done
