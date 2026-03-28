#!/bin/bash

# Ensure Claude finds the native binary at the expected path
if [ ! -e "$HOME/.local/bin/claude" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -s /usr/local/bin/claude "$HOME/.local/bin/claude"
fi

# Sync GSD commands from the image seed only when the image has changed.
# Skipping redundant syncs avoids disrupting concurrent containers that
# share this state directory.
mkdir -p "$HOME/.claude"
STAMP=$(cat /opt/gsd-seed/.build-stamp 2>/dev/null)
MARKER="$HOME/.claude/.gsd-stamp"
if [ ! -f "$MARKER" ] || [ "$(cat "$MARKER")" != "$STAMP" ]; then
    cp -r /opt/gsd-seed/* "$HOME/.claude/" 2>/dev/null
    echo "$STAMP" > "$MARKER"
fi

# Ensure .claude-state is gitignored in the workspace so Claude skips it
GITIGNORE="/home/sandbox/workspace/.gitignore"
if ! grep -qx '.claude-state/' "$GITIGNORE" 2>/dev/null; then
    echo '.claude-state/' >> "$GITIGNORE"
fi

exec claude "$@"
