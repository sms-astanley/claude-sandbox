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
    [ -d "$src_dir" ] || continue
    mkdir -p "$dst_dir"

    # Drop stale gsd-* symlinks first so renamed/removed entries don't linger.
    find "$dst_dir" -maxdepth 1 -name 'gsd-*' -type l -delete 2>/dev/null || true

    for src in "$src_dir"/gsd-*; do
        [ -e "$src" ] || continue
        ln -sfn "$src" "$dst_dir/$(basename "$src")"
    done
done

# GSD ships a get-shit-done/ helper tree at the root of CLAUDE_CONFIG_DIR.
# Symlink it wholesale — GSD-owned, never user-modified.
if [ -d "$GSD_ROOT/get-shit-done" ]; then
    ln -sfn "$GSD_ROOT/get-shit-done" "$CLAUDE_DIR/get-shit-done"
fi

# Symlink GSD-namespaced metadata files at the root of CLAUDE_CONFIG_DIR
# (manifest, install-state, package.json read by /gsd-help, etc.).
for f in "$GSD_ROOT"/gsd-*.json "$GSD_ROOT/package.json"; do
    [ -e "$f" ] || continue
    ln -sfn "$f" "$CLAUDE_DIR/$(basename "$f")"
done

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
        exec claude "$@"
        ;;
esac
