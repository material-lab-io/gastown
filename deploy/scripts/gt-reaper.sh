#!/usr/bin/env bash
# gt-reaper.sh — Stale Process Reaper for Gas Town
# Runs periodically via systemd timer to clean up orphaned processes.
#
# Detects:
#   1. Orphaned Claude processes whose tmux session no longer exists
#   2. Orphaned child processes (node, python) from dead Claude sessions
#   3. GPU processes not in the whitelist
#
# Safety:
#   - Only kills processes owned by $USER (kanaba)
#   - Never kills processes in attached tmux sessions
#   - Dry-run mode: REAPER_DRY_RUN=1
#   - Whitelist for known-good processes

set -euo pipefail

LOGFILE="$HOME/.openclaw/workspaces/mayor/reaper.log"
WHITELIST="$HOME/.openclaw/workspaces/mayor/reaper-whitelist.txt"
DRY_RUN="${REAPER_DRY_RUN:-0}"
KILL_COUNT=0
KILL_DETAILS=""

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
}

log_and_record() {
    log "$*"
    KILL_DETAILS="${KILL_DETAILS}${*}\n"
    KILL_COUNT=$((KILL_COUNT + 1))
}

is_whitelisted() {
    local process_name="$1"
    if [[ ! -f "$WHITELIST" ]]; then
        return 1
    fi
    while IFS= read -r pattern; do
        # Skip comments and blank lines
        [[ -z "$pattern" || "$pattern" == \#* ]] && continue
        if [[ "$process_name" == *"$pattern"* ]]; then
            return 0
        fi
    done < "$WHITELIST"
    return 1
}

kill_process() {
    local pid="$1"
    local reason="$2"

    # Safety: only kill our own processes
    local owner
    owner=$(ps -o user= -p "$pid" 2>/dev/null || true)
    if [[ "$owner" != "kanaba" ]]; then
        log "SKIP pid=$pid owner=$owner (not kanaba): $reason"
        return
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        log_and_record "DRY-RUN would kill pid=$pid: $reason"
        return
    fi

    log_and_record "KILL pid=$pid: $reason"
    kill -TERM "$pid" 2>/dev/null || true
    # Wait up to 5 seconds for graceful shutdown
    for _ in $(seq 1 10); do
        if ! kill -0 "$pid" 2>/dev/null; then
            return
        fi
        sleep 0.5
    done
    # Still alive — force kill
    kill -9 "$pid" 2>/dev/null || true
    log "SIGKILL pid=$pid (did not exit after SIGTERM)"
}

kill_tree() {
    local parent_pid="$1"
    local reason="$2"
    # Kill children first (bottom-up)
    local children
    children=$(pgrep -P "$parent_pid" 2>/dev/null || true)
    for child in $children; do
        kill_tree "$child" "child of $parent_pid: $reason"
    done
    kill_process "$parent_pid" "$reason"
}

# --- Main ---

log "=== Reaper run started (dry_run=$DRY_RUN) ==="

# 1. Get active Gas Town tmux sessions
declare -A ACTIVE_SESSIONS
declare -A ATTACHED_SESSIONS

while IFS= read -r line; do
    session_name=$(echo "$line" | cut -d: -f1)
    ACTIVE_SESSIONS["$session_name"]=1
    if echo "$line" | grep -q '(attached)'; then
        ATTACHED_SESSIONS["$session_name"]=1
    fi
done < <(tmux list-sessions 2>/dev/null || true)

active_count=${#ACTIVE_SESSIONS[@]}
log "Active tmux sessions: $active_count"

# 2. Find orphaned Claude processes
# Claude processes for Gas Town contain "[GAS TOWN]" in their cmdline
while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue

    # Read the full cmdline
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
    [[ -z "$cmdline" ]] && continue

    # Only target Gas Town claude processes
    if [[ "$cmdline" != *"[GAS TOWN]"* ]]; then
        continue
    fi

    # Skip tmux server processes (they contain "tmux new-session" in cmdline)
    if [[ "$cmdline" == *"tmux new-session"* || "$cmdline" == *"tmux: server"* ]]; then
        continue
    fi

    # Check if this process's tmux session still exists
    session_found=0

    # Method 1: Check if process is running in a known tmux pane by TTY
    # ps returns e.g. "pts/28", tmux returns "/dev/pts/28"
    proc_tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    if [[ -n "$proc_tty" && "$proc_tty" != "?" ]]; then
        for sess in "${!ACTIVE_SESSIONS[@]}"; do
            sess_ttys=$(tmux list-panes -t "$sess" -F '#{pane_tty}' 2>/dev/null || true)
            for tty in $sess_ttys; do
                tty_normalized="${tty#/dev/}"
                if [[ "$tty_normalized" == "$proc_tty" ]]; then
                    session_found=1
                    if [[ -n "${ATTACHED_SESSIONS[$sess]:-}" ]]; then
                        log "SKIP pid=$pid in attached session $sess"
                    fi
                    break 2
                fi
            done
        done
    fi

    # Method 2: For processes with tty=? (backgrounded), check if their
    # parent tmux session is still alive by walking up the process tree
    if [[ "$session_found" == "0" && ("$proc_tty" == "?" || -z "$proc_tty") ]]; then
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
        if [[ -n "$ppid" && "$ppid" != "1" && "$ppid" != "0" ]]; then
            parent_cmd=$(ps -o comm= -p "$ppid" 2>/dev/null || true)
            # If parent is tmux, check if that tmux session still exists
            if [[ "$parent_cmd" == "tmux"* ]]; then
                session_found=1
            fi
        fi
    fi

    if [[ "$session_found" == "0" ]]; then
        # Process's tmux session is gone — it's orphaned
        log_and_record "ORPHAN claude pid=$pid cmdline=$(echo "$cmdline" | head -c 120)"
        kill_tree "$pid" "orphaned claude process (no tmux session)"
    fi
done < <(pgrep -u kanaba -f "claude" 2>/dev/null || true)

# 3. Find orphaned shell processes from Claude
# These are bash processes spawned by claude that reference shell-snapshots
# and whose parent is init (1) — meaning their claude parent died
while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)
    [[ -z "$ppid" ]] && continue

    # Only target processes whose parent is init (orphaned)
    if [[ "$ppid" != "1" ]]; then
        continue
    fi

    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
    # Claude shell snapshots leave distinctive markers
    if [[ "$cmdline" == *"shell-snapshots"* || "$cmdline" == *"claude-"*"-cwd"* ]]; then
        log_and_record "ORPHAN shell pid=$pid cmdline=$(echo "$cmdline" | head -c 120)"
        kill_tree "$pid" "orphaned claude shell subprocess"
    fi
done < <(pgrep -u kanaba -f "bash" 2>/dev/null || true)

# 4. Check GPU processes against whitelist
if command -v nvidia-smi &>/dev/null; then
    while IFS=, read -r gpu_pid gpu_name gpu_mem; do
        gpu_pid=$(echo "$gpu_pid" | tr -d ' ')
        gpu_name=$(echo "$gpu_name" | tr -d ' ')
        gpu_mem=$(echo "$gpu_mem" | tr -d ' ')
        [[ -z "$gpu_pid" ]] && continue

        # Skip non-kanaba processes
        owner=$(ps -o user= -p "$gpu_pid" 2>/dev/null || true)
        if [[ "$owner" != "kanaba" ]]; then
            continue
        fi

        if is_whitelisted "$gpu_name"; then
            continue
        fi

        # Check if the process is part of an active tmux session
        proc_tty=$(ps -o tty= -p "$gpu_pid" 2>/dev/null | tr -d ' ' || true)
        in_session=0
        if [[ -n "$proc_tty" && "$proc_tty" != "?" ]]; then
            for sess in "${!ACTIVE_SESSIONS[@]}"; do
                sess_ttys=$(tmux list-panes -t "$sess" -F '#{pane_tty}' 2>/dev/null || true)
                for tty in $sess_ttys; do
                    if [[ "${tty#/dev/}" == "$proc_tty" ]]; then
                        in_session=1
                        break 2
                    fi
                done
            done
        fi

        if [[ "$in_session" == "0" ]]; then
            log_and_record "GPU-HOG pid=$gpu_pid name=$gpu_name mem=$gpu_mem (not whitelisted, no session)"
            kill_process "$gpu_pid" "GPU hog not in whitelist: $gpu_name ($gpu_mem)"
        fi
    done < <(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null || true)
fi

# 5. Summary
log "=== Reaper run complete: $KILL_COUNT actions ==="

if [[ "$KILL_COUNT" -gt 0 ]]; then
    prefix=""
    [[ "$DRY_RUN" == "1" ]] && prefix="[DRY-RUN] "
    summary="${prefix}Reaper: cleaned $KILL_COUNT processes"
    details=$(echo -e "$KILL_DETAILS")

    # Send mail to mayor if gt is available
    if command -v gt &>/dev/null; then
        gt mail send mayor/ -s "$summary" -m "$details" 2>/dev/null || true
    fi
fi
