#!/bin/bash

# Ensure Claude finds the native binary at the expected path
if [ ! -e "$HOME/.local/bin/claude" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -s /usr/local/bin/claude "$HOME/.local/bin/claude"
fi

# Seed GSD commands from the image if not already present
if [ ! -d "$HOME/.claude/commands/gsd" ]; then
    mkdir -p "$HOME/.claude"
    cp -r /opt/gsd-seed/* "$HOME/.claude/" 2>/dev/null
fi

# Ensure .claude-state is gitignored in the workspace so Claude skips it
GITIGNORE="/home/sandbox/workspace/.gitignore"
if ! grep -qx '.claude-state/' "$GITIGNORE" 2>/dev/null; then
    echo '.claude-state/' >> "$GITIGNORE"
fi

exec claude "$@"
