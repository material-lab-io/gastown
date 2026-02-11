#!/bin/bash
# Link this polecat's Claude Code memory to the shared rig crew-memory dir.
# ENV: GT_WORKTREE_PATH, GT_RIG_PATH

CREW_MEMORY="$GT_RIG_PATH/crew-memory"
if [ ! -d "$CREW_MEMORY" ]; then
    mkdir -p "$CREW_MEMORY"
fi

# Encode the worktree path the way Claude Code does: /foo/bar → -foo-bar
ENCODED=$(echo "$GT_WORKTREE_PATH" | sed 's|/|-|g')
CLAUDE_MEMORY_DIR="$HOME/.claude/projects/${ENCODED}/memory"

# If it's already a symlink or the shared dir, skip
if [ -L "$CLAUDE_MEMORY_DIR" ]; then
    exit 0
fi

# Back up any existing memory, then symlink
if [ -d "$CLAUDE_MEMORY_DIR" ]; then
    # Merge existing memory into shared dir
    cp -n "$CLAUDE_MEMORY_DIR"/* "$CREW_MEMORY/" 2>/dev/null || true
    rm -rf "$CLAUDE_MEMORY_DIR"
fi

mkdir -p "$(dirname "$CLAUDE_MEMORY_DIR")"
ln -s "$CREW_MEMORY" "$CLAUDE_MEMORY_DIR"
echo "Linked crew memory: $CLAUDE_MEMORY_DIR → $CREW_MEMORY"
