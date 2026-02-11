#!/usr/bin/env bash
# gt-janitor.sh — Hourly System Cleanup for Gas Town
# Handles heavier maintenance tasks that don't need to run every 10 minutes.
# Complements gt-reaper.sh (which handles orphaned processes).
#
# Cleans:
#   1. Completed Ralph worktrees (.ralph-complete marker)
#   2. Docker: exited containers, dangling images, build cache
#   3. Docker: old tagged images (keeps latest per repo)
#   4. Stale /tmp/claude-* files (owned by us)
#   5. Stale non-GT tmux sessions (idle > 24h, no pane activity)
#
# Safety:
#   - Only removes our own files/processes (kanaba)
#   - Docker prune uses -f but only targets dangling/exited
#   - Old image removal keeps latest tag per repository
#   - Dry-run mode: JANITOR_DRY_RUN=1

set -uo pipefail

LOGFILE="$HOME/.openclaw/workspaces/mayor/janitor.log"
DRY_RUN="${JANITOR_DRY_RUN:-0}"
SUMMARY=""
FREED_DOCKER=""

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
}

record() {
    log "$*"
    SUMMARY="${SUMMARY}${*}\n"
}

run_or_dry() {
    if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY-RUN: $*"
        record "DRY-RUN: $*"
    else
        eval "$@"
    fi
}

log "=== Janitor run started (dry_run=$DRY_RUN) ==="

# --- 1. Completed Ralph Worktrees ---
# Look for worktrees in $HOME matching polecat-*/.ralph-complete
ralph_cleaned=0
for marker in "$HOME"/polecat-*/.ralph-complete; do
    [[ -f "$marker" ]] || continue
    worktree_dir=$(dirname "$marker")
    worktree_name=$(basename "$worktree_dir")

    # Only clean if .ralph-complete is older than 1 hour (task definitely done)
    if [[ $(find "$marker" -mmin +60 2>/dev/null | wc -l) -gt 0 ]]; then
        record "RALPH-CLEANUP: removing completed worktree $worktree_name"
        run_or_dry "rm -rf '$worktree_dir'"
        ralph_cleaned=$((ralph_cleaned + 1))
    fi
done
[[ "$ralph_cleaned" -gt 0 ]] && record "Cleaned $ralph_cleaned completed Ralph worktrees"

# --- 2. Docker: Exited Containers ---
exited=$(docker ps -a --filter status=exited --format '{{.Names}}' 2>/dev/null || true)
if [[ -n "$exited" ]]; then
    count=$(echo "$exited" | wc -l)
    record "DOCKER: removing $count exited containers"
    if [[ "$DRY_RUN" != "1" ]]; then
        docker container prune -f >> "$LOGFILE" 2>&1
    fi
fi

# --- 3. Docker: Dangling Images ---
dangling=$(docker images -f dangling=true -q 2>/dev/null || true)
if [[ -n "$dangling" ]]; then
    count=$(echo "$dangling" | wc -l)
    record "DOCKER: pruning $count dangling images"
    if [[ "$DRY_RUN" != "1" ]]; then
        result=$(docker image prune -f 2>&1)
        freed=$(echo "$result" | grep "Total reclaimed space" || true)
        [[ -n "$freed" ]] && FREED_DOCKER="$FREED_DOCKER images: $freed; "
        log "$result"
    fi
fi

# --- 4. Docker: Build Cache ---
# Only prune if build cache exceeds 2 GB
cache_size=$(docker system df --format '{{.Size}}' 2>/dev/null | tail -1 || true)
# docker builder prune is cheap to run — always prune unused cache
if [[ "$DRY_RUN" != "1" ]]; then
    result=$(docker builder prune -f 2>&1)
    freed=$(echo "$result" | grep "^Total:" || true)
    if [[ -n "$freed" && "$freed" != "Total:	0B" ]]; then
        record "DOCKER: build cache pruned ($freed)"
        FREED_DOCKER="$FREED_DOCKER cache: $freed; "
    fi
fi

# --- 5. Docker: Old Tagged Images ---
# For repos with multiple tagged builds, keep latest + currently used, remove rest
# Only target repos known to produce large builds
for repo in legend-backend; do
    images=$(docker images "$repo" --format '{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}' 2>/dev/null | sort -t$'\t' -k3 -r || true)
    [[ -z "$images" ]] && continue

    # Keep the first (newest) image, remove the rest (skip "latest" tag)
    latest_id=""
    while IFS=$'\t' read -r tag id created; do
        [[ -z "$tag" ]] && continue

        # Always keep "latest" tag — just record its ID
        if [[ "$tag" == "latest" ]]; then
            latest_id="$id"
            continue
        fi

        # Keep if same ID as latest
        if [[ -n "$latest_id" && "$id" == "$latest_id" ]]; then
            continue
        fi

        # Keep if still used by a running container
        if docker ps --filter "ancestor=$repo:$tag" --format '{{.ID}}' 2>/dev/null | grep -q .; then
            continue
        fi

        # Old image — remove
        record "DOCKER: removing old image $repo:$tag (created $created)"
        run_or_dry "docker rmi '$repo:$tag' 2>/dev/null || true"
    done <<< "$images"
done

# --- 6. Stale Temp Files ---
tmp_cleaned=0
# Remove claude temp dirs older than 2 days (owned by us)
for d in /tmp/claude-xlsx-venv /tmp/claude-[0-9]*; do
    [[ -e "$d" ]] || continue
    # Only remove if we own it
    owner=$(stat -c '%U' "$d" 2>/dev/null || true)
    [[ "$owner" != "kanaba" ]] && continue
    # Only if older than 2 days
    if [[ $(find "$d" -maxdepth 0 -mtime +2 2>/dev/null | wc -l) -gt 0 ]]; then
        record "TEMP: removing $d"
        run_or_dry "rm -rf '$d'"
        tmp_cleaned=$((tmp_cleaned + 1))
    fi
done

# Remove stale cwd marker files (older than 1 day, owned by us)
for f in /tmp/claude-*-cwd; do
    [[ -f "$f" ]] || continue
    owner=$(stat -c '%U' "$f" 2>/dev/null || true)
    [[ "$owner" != "kanaba" ]] && continue
    if [[ $(find "$f" -mtime +1 2>/dev/null | wc -l) -gt 0 ]]; then
        run_or_dry "rm -f '$f'"
        tmp_cleaned=$((tmp_cleaned + 1))
    fi
done
[[ "$tmp_cleaned" -gt 0 ]] && record "Cleaned $tmp_cleaned stale temp files/dirs"

# --- 7. Stale Non-GT Tmux Sessions ---
# Kill tmux sessions that aren't Gas Town managed (gt-* or hq-*) and are idle > 24h
while IFS= read -r line; do
    session_name=$(echo "$line" | cut -d: -f1)
    [[ -z "$session_name" ]] && continue

    # Skip Gas Town sessions
    [[ "$session_name" == gt-* || "$session_name" == hq-* ]] && continue

    # Skip attached sessions
    echo "$line" | grep -q '(attached)' && continue

    # Check session creation time — skip if < 24h old
    created=$(echo "$line" | grep -oP 'created \K.*(?=\))' || true)
    [[ -z "$created" ]] && continue
    created_epoch=$(date -d "$created" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    age_hours=$(( (now_epoch - created_epoch) / 3600 ))

    if [[ "$age_hours" -ge 24 ]]; then
        # Check if any pane has had recent activity (last 1h)
        last_activity=$(tmux list-panes -t "$session_name" -F '#{pane_last_activity}' 2>/dev/null | sort -rn | head -1 || echo 0)
        if [[ -n "$last_activity" && "$last_activity" -gt 0 ]]; then
            activity_age=$(( now_epoch - last_activity ))
            if [[ "$activity_age" -lt 3600 ]]; then
                log "SKIP session $session_name: idle $age_hours hrs but pane active ${activity_age}s ago"
                continue
            fi
        fi
        record "TMUX: killing stale session $session_name (idle ${age_hours}h)"
        run_or_dry "tmux kill-session -t '$session_name' 2>/dev/null || true"
    fi
done < <(tmux list-sessions 2>/dev/null || true)

# --- Summary ---
log "=== Janitor run complete ==="

if [[ -n "$SUMMARY" ]]; then
    prefix=""
    [[ "$DRY_RUN" == "1" ]] && prefix="[DRY-RUN] "
    summary_text="${prefix}Janitor cleanup:\n$(echo -e "$SUMMARY")"
    log "$summary_text"

    # Send mail to mayor if gt is available and actions were taken
    if command -v gt &>/dev/null && [[ "$DRY_RUN" != "1" ]]; then
        gt mail send mayor/ -s "Janitor: cleanup complete" -m "$(echo -e "$summary_text")" 2>/dev/null || true
    fi
else
    log "Nothing to clean"
fi
