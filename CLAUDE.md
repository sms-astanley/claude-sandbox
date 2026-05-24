# claude-sandbox

Docker container packaging Claude Code + [GSD (open-gsd/get-shit-done-redux)](https://github.com/open-gsd/get-shit-done-redux) with a dev toolchain.

## Architecture

The image is immutable. State lives outside it. Three rules govern everything:

1. **GSD lives at `/opt/gsd/` inside the image — never in the mounted volume.** The entrypoint symlinks each entry from `/opt/gsd/` into `~/.claude/` on every container start. Image rebuilds update `/opt/gsd/`; symlinks resolve to the new content automatically. The mounted volume cannot shadow GSD.
2. **Only `~/.claude/` is mounted from the host.** HOME stays at the image default (`/home/sandbox`); `.local/bin/`, PATH, the `claude` binary, and GSD all stay in the image. No `$HOME` redirection, no sync-from-seed, no stamp files — those were the old `.claude-state/` design's workarounds for shadowing.
3. **`gsd-sdk` must be on PATH globally.** GSD agents invoke `gsd-sdk query <handler>` directly. Installing via `npx` leaves the shim in an ephemeral cache and breaks workflows; the Dockerfile uses `npm install -g @opengsd/get-shit-done-redux` to get `/usr/local/bin/gsd-sdk`.

## Files

| File | Role |
|---|---|
| `Dockerfile` | Builds the image. Installs OS deps + uv + pnpm + Claude Code + GSD globally (npm) + GSD content to `/opt/gsd` via `CLAUDE_CONFIG_DIR`. |
| `entrypoint.sh` | On every start: creates per-entry symlinks for `~/.claude/{skills,commands,agents,hooks}/gsd-*`, plus `settings.json`, `get-shit-done/`, and GSD root metadata. Dispatches first arg: `bash`/`sh` → shell, anything else → `claude "$@"`. |
| `docker-compose.yml` | Repo-root compose file for **building only** (`docker compose build`). Has a `build:` block, no run-time mounts. |
| `template/docker-compose.yml` | Template **for users to copy into their projects**. Has the workspace bind mount + named `claude-home` volume. References `image: claude-sandbox:latest` (no `build:` block). |
| `README.md` | User-facing docs. Distinguishes the two compose files clearly. |

## Workflows

```bash
# Build/upgrade the image (from this repo)
docker compose build

# Use the sandbox (from any project that has copied template/docker-compose.yml in)
docker compose run --rm sandbox            # interactive claude
docker compose run --rm sandbox bash       # shell (entrypoint still runs symlink setup)
docker compose run --rm sandbox -p "..."   # one-shot prompt
docker compose down -v                     # reset the project's state volume
```

The named volume `claude-home` is auto-prefixed by compose with the project name (directory basename), so each project gets isolated state automatically.

## Gotchas to remember

- **Never tell users to run `--entrypoint bash`.** That bypasses `entrypoint.sh` and GSD's symlinks won't exist. The dispatch in `entrypoint.sh` is why `sandbox bash` works correctly.
- **`settings.json` must be symlinked from `/opt/gsd/`** — it carries GSD's hook wiring (SessionStart, PreToolUse, PostToolUse, statusLine). Without it the skills/agents are useless because no hooks fire. The entrypoint only links it if no real user file is present (symlinks count as "not real"); user overrides should go in `settings.local.json`.
- **The Dockerfile does `npm install -g` AND a separate installer run.** The global install gives the `gsd-sdk` binary on PATH; the installer run with `CLAUDE_CONFIG_DIR=/opt/gsd get-shit-done-redux --claude --global --yes` lays down skills/agents/hooks/settings.json into `/opt/gsd/`. Removing either step breaks GSD.
- **GSD redux replaced both `@gsd-build/sdk` and `get-shit-done-cc`.** The old `gsd-sdk-shim.sh` is obsolete — the new package's `bin/gsd-sdk.js` already implements the `query` subcommand.
- **GSD redux has no commands/ entries — everything is skills.** `/opt/gsd/commands/` exists but is empty. The entrypoint's loop over `skills commands agents hooks` is robust to this (empty glob is skipped via `[ -e "$src" ] || continue`).
- **On Linux, build with `USER_UID=$(id -u) docker compose build`** so mounted file permissions match the host user. macOS defaults to 501 which is the build-arg default.
