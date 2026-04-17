#!/bin/bash

# Force the state volume to point at the image-baked binary so rebuilds
# actually upgrade Claude. The native installer/updater otherwise writes a
# versioned binary into ~/.local/share/claude/versions/ and repoints the
# symlink at it, shadowing /usr/local/bin/claude across container runs.
mkdir -p "$HOME/.local/bin"
ln -sfn /usr/local/bin/claude "$HOME/.local/bin/claude"
rm -rf "$HOME/.local/share/claude"

# Sync GSD commands from the image seed only when the image has changed.
# Skipping redundant syncs avoids disrupting concurrent containers that
# share this state directory.
mkdir -p "$HOME/.claude"
STAMP=$(cat /opt/gsd-seed/.build-stamp 2>/dev/null)
MARKER="$HOME/.claude/.gsd-stamp"
if [ ! -f "$MARKER" ] || [ "$(cat "$MARKER")" != "$STAMP" ]; then
    # Drop legacy commands/gsd/ from pre-skills GSD installs so /gsd:* doesn't
    # shadow the new /gsd-* skills. Matches the cleanup the GSD installer
    # itself performs on --global installs (bin/install.js).
    rm -rf "$HOME/.claude/commands/gsd"
    cp -r /opt/gsd-seed/* "$HOME/.claude/" 2>/dev/null
    echo "$STAMP" > "$MARKER"
fi

# Ensure .claude-state is gitignored in the workspace so Claude skips it
GITIGNORE="/home/sandbox/workspace/.gitignore"
if ! grep -qx '.claude-state/' "$GITIGNORE" 2>/dev/null; then
    echo '.claude-state/' >> "$GITIGNORE"
fi

exec claude "$@"
