#!/bin/bash
set -e

# Symlink GSD content from the image-only path into the user's ~/.claude/.
# Per-entry symlinks (not whole-directory symlinks) so user-installed skills,
# plugins, settings, and history coexist with GSD without conflict. On image
# rebuild, /opt/gsd/ contains the new GSD version and the symlinks resolve
# to the new content automatically — no sync, no stamp, no shadowing.
GSD_ROOT="/opt/gsd"
CLAUDE_DIR="$HOME/.claude"

mkdir -p "$CLAUDE_DIR"

for dir in skills commands agents hooks; do
    src_dir="$GSD_ROOT/$dir"
    dst_dir="$CLAUDE_DIR/$dir"

    # Drop stale gsd-* symlinks first so renamed/removed entries don't linger.
    # This runs BEFORE the source-dir check on purpose: GSD dropped commands/
    # outright in 1.8.0, and a sweep gated behind `[ -d $src_dir ]` would skip
    # the very directory whose links went stale, leaving them dangling forever
    # (GSD's own migrations only see its install dir, never ~/.claude).
    if [ -d "$dst_dir" ]; then
        find "$dst_dir" -maxdepth 1 -name 'gsd-*' -type l -delete 2>/dev/null || true
    fi

    [ -d "$src_dir" ] || continue
    mkdir -p "$dst_dir"

    for src in "$src_dir"/gsd-*; do
        [ -e "$src" ] || continue
        ln -sfn "$src" "$dst_dir/$(basename "$src")"
    done
done

# GSD ships a helper tree at the root of CLAUDE_CONFIG_DIR — `gsd-core/` as of
# GSD 1.8.0, `get-shit-done/` before that. Symlink whichever exists wholesale
# (GSD-owned, never user-modified) and drop the other name if a previous image's
# symlink is still sitting in the mounted volume, dangling.
for tree in gsd-core get-shit-done; do
    if [ -d "$GSD_ROOT/$tree" ]; then
        ln -sfn "$GSD_ROOT/$tree" "$CLAUDE_DIR/$tree"
    elif [ -L "$CLAUDE_DIR/$tree" ]; then
        rm -f "$CLAUDE_DIR/$tree"
    fi
done

# Symlink GSD-namespaced metadata files at the root of CLAUDE_CONFIG_DIR
# (manifest, install-state, package.json read by /gsd-help, etc.).
for f in "$GSD_ROOT"/gsd-*.json "$GSD_ROOT/package.json"; do
    [ -e "$f" ] || continue
    ln -sfn "$f" "$CLAUDE_DIR/$(basename "$f")"
done

# ~/.claude.json holds onboarding flags, accepted-agreements state, and OAuth
# account metadata. It lives at $HOME (sibling of ~/.claude/), so it's outside
# the mounted volume and would reset every --rm. Persist it by moving the real
# file into the volume and symlinking ~/.claude.json to it. Paranoid filename
# avoids any chance Claude Code ever scans ~/.claude/ for a literal .claude.json.
HOME_CONFIG="$HOME/.claude.json"
PERSISTED_CONFIG="$CLAUDE_DIR/.claude-json-persisted"
if [ ! -e "$PERSISTED_CONFIG" ]; then
    if [ -f "$HOME_CONFIG" ] && [ ! -L "$HOME_CONFIG" ]; then
        cp "$HOME_CONFIG" "$PERSISTED_CONFIG"
    else
        echo '{}' > "$PERSISTED_CONFIG"
    fi
fi
ln -sfn "$PERSISTED_CONFIG" "$HOME_CONFIG"

# settings.json contains GSD's hook wiring (SessionStart, PreToolUse,
# PostToolUse, statusLine) — without it, none of the GSD hooks fire.
# Symlink it only if the user hasn't created their own real settings.json.
# Users who need to override GSD settings should use settings.local.json,
# which Claude Code merges on top.
if [ ! -e "$CLAUDE_DIR/settings.json" ] || [ -L "$CLAUDE_DIR/settings.json" ]; then
    ln -sfn "$GSD_ROOT/settings.json" "$CLAUDE_DIR/settings.json"
fi

# Dispatch: a shell command drops into a shell (GSD links already in place);
# anything else (or no args) goes to claude.
case "${1:-}" in
    bash|sh)
        exec "$@"
        ;;
    *)
        exec claude --dangerously-skip-permissions "$@"
        ;;
esac
