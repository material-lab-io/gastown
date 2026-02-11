#!/bin/bash
# gt-deploy installer
# Symlinks config files into place and enables systemd units.
#
# Usage:
#   ./install.sh            # Install everything
#   ./install.sh --dry-run  # Show what would be done without doing it

set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
GT_DIR="$HOME/.gt"
SCRIPTS_DIR="$HOME/.openclaw/workspaces/mayor"
SYSTEMD_DIR="$HOME/.config/systemd/user"
TOWN_DIR="$HOME/gt/mayor"

run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "[dry-run] $*"
    else
        eval "$@"
    fi
}

link() {
    local src="$1" dst="$2"
    if [[ -L "$dst" ]]; then
        local current
        current=$(readlink "$dst")
        if [[ "$current" == "$src" ]]; then
            echo "  ok: $dst (already linked)"
            return
        fi
        echo "  relink: $dst → $src (was $current)"
        run "rm '$dst'"
    elif [[ -e "$dst" ]]; then
        echo "  backup: $dst → ${dst}.bak"
        run "mv '$dst' '${dst}.bak'"
    else
        echo "  link: $dst → $src"
    fi
    run "ln -s '$src' '$dst'"
}

echo "=== gt-deploy installer ==="
[[ "$DRY_RUN" == "1" ]] && echo "(dry-run mode)"

# 0. Validate .env
if [[ ! -f "$GT_DIR/.env" ]]; then
    echo ""
    echo "WARNING: $GT_DIR/.env not found."
    echo "  Copy .env.example to $GT_DIR/.env and fill in your secrets."
    echo "  The Slack relay will not work without SLACK_BOT_TOKEN."
    echo ""
fi

# 1. Hooks
echo ""
echo "--- Hooks ---"
mkdir -p "$GT_DIR"
link "$REPO_DIR/hooks/hooks-base.json" "$GT_DIR/hooks-base.json"

# 2. Scripts
echo ""
echo "--- Scripts ---"
mkdir -p "$SCRIPTS_DIR"
for script in "$REPO_DIR"/scripts/*; do
    name=$(basename "$script")
    link "$script" "$SCRIPTS_DIR/$name"
done
# Make scripts executable
if [[ "$DRY_RUN" != "1" ]]; then
    chmod +x "$REPO_DIR"/scripts/*.sh
fi

# 3. Systemd units
echo ""
echo "--- Systemd units ---"
mkdir -p "$SYSTEMD_DIR"
for unit in "$REPO_DIR"/systemd/*; do
    name=$(basename "$unit")
    link "$unit" "$SYSTEMD_DIR/$name"
done

if [[ "$DRY_RUN" != "1" ]]; then
    echo "  Reloading systemd user daemon..."
    systemctl --user daemon-reload

    echo "  Enabling timers..."
    systemctl --user enable gt-reaper.timer gt-janitor.timer
    systemctl --user start gt-reaper.timer gt-janitor.timer

    echo "  Enabling slack-relay..."
    systemctl --user enable slack-relay.service
    # Don't auto-start — user should verify .env first
    echo "  (run 'systemctl --user start slack-relay' after verifying ~/.gt/.env)"
fi

# 4. Town config
echo ""
echo "--- Town config ---"
mkdir -p "$TOWN_DIR"
for f in town.json rigs.json overseer.json daemon.json; do
    link "$REPO_DIR/town/$f" "$TOWN_DIR/$f"
done

# 5. CLAUDE.md files
echo ""
echo "--- CLAUDE.md ---"
mkdir -p "$HOME/gt"
link "$REPO_DIR/town/CLAUDE.md" "$HOME/gt/CLAUDE.md"
mkdir -p "$TOWN_DIR"
link "$REPO_DIR/mayor/CLAUDE.md" "$TOWN_DIR/CLAUDE.md"

# 6. Mayor commands
echo ""
echo "--- Mayor commands ---"
mkdir -p "$TOWN_DIR/.claude/commands"
link "$REPO_DIR/mayor/commands/handoff.md" "$TOWN_DIR/.claude/commands/handoff.md"

# 7. Setup hooks (template — copy to each rig's .runtime/setup-hooks/)
echo ""
echo "--- Setup hooks ---"
echo "  Template: $REPO_DIR/setup-hooks/01-crew-memory.sh"
echo "  Copy to each rig's .runtime/setup-hooks/ as needed:"
echo "    cp $REPO_DIR/setup-hooks/01-crew-memory.sh ~/gt/<rig>/.runtime/setup-hooks/"

# 8. Agent context
echo ""
echo "--- Agent context ---"
for f in "$REPO_DIR"/agent-context/*; do
    name=$(basename "$f")
    link "$f" "$SCRIPTS_DIR/$name"
done

echo ""
echo "=== Done ==="
echo ""
echo "Next steps:"
echo "  1. Ensure ~/.gt/.env exists with SLACK_BOT_TOKEN"
echo "  2. Run: gt hooks sync"
echo "  3. Run: systemctl --user start slack-relay"
echo "  4. Verify: systemctl --user status slack-relay gt-reaper.timer gt-janitor.timer"
