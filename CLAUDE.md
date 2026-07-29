# claude-sandbox

Docker container packaging Claude Code + [GSD Core (open-gsd/gsd-core)](https://github.com/open-gsd/gsd-core) with a dev toolchain.

## Architecture

The image is immutable. State lives outside it. Three rules govern everything:

1. **GSD lives at `/opt/gsd/` inside the image — never in the mounted volume.** The entrypoint symlinks each entry from `/opt/gsd/` into `~/.claude/` on every container start. Image rebuilds update `/opt/gsd/`; symlinks resolve to the new content automatically. The mounted volume cannot shadow GSD.
2. **Only `~/.claude/` is mounted from the host.** HOME stays at the image default (`/home/sandbox`); `.local/bin/`, PATH, the `claude` binary, and GSD all stay in the image. No `$HOME` redirection, no sync-from-seed, no stamp files — those were the old `.claude-state/` design's workarounds for shadowing.
3. **`gsd-tools` must be on PATH globally.** GSD agents/hooks invoke `gsd-tools <subcommand>` directly. Installing via `npx` leaves the shim in an ephemeral cache and breaks workflows; the Dockerfile uses `npm install -g @opengsd/gsd-core` to get `/usr/local/bin/gsd-tools` (and the `gsd-core` installer binary).

## Files

| File | Role |
|---|---|
| `Dockerfile` | Builds the image. Installs OS deps + uv + pnpm + Claude Code + GSD globally (npm) + GSD content to `/opt/gsd` via `CLAUDE_CONFIG_DIR` + Playwright with Chromium to `/opt/playwright`. |
| `entrypoint.sh` | On every start: creates per-entry symlinks for `~/.claude/{skills,commands,agents,hooks}/gsd-*`, plus `settings.json`, `get-shit-done/`, and GSD root metadata. Also persists `~/.claude.json` by symlinking it to `~/.claude/.claude-json-persisted` inside the volume. Dispatches first arg: `bash`/`sh` → shell, anything else → `claude "$@"`. |
| `docker-compose.yml` | Repo-root compose file for **building only** (`docker compose build`). Has a `build:` block, no run-time mounts. |
| `template/docker-compose.yml` | Template **for users to copy into their projects**. Has the workspace bind mount + named `claude-home` volume. References `image: claude-sandbox:latest` (no `build:` block). |
| `README.md` | User-facing docs. Distinguishes the two compose files clearly. |

## Workflows

```bash
# Build/upgrade the image (from this repo)
docker compose build

# Use the sandbox (from any project that has copied template/docker-compose.yml in)
docker compose run --service-ports --rm sandbox            # interactive claude
docker compose run --service-ports --rm sandbox bash       # shell (entrypoint still runs symlink setup)
docker compose run --service-ports --rm sandbox -p "..."   # one-shot prompt
docker compose down -v                     # reset the project's state volume
```

The named volume `claude-home` is auto-prefixed by compose with the project name (directory basename), so each project gets isolated state automatically.

## Gotchas to remember

- **All documented `docker compose run` commands must include `--service-ports`.** Plain `run` silently ignores `ports:` (deliberate Docker behavior to avoid colliding with an `up` instance), so users who uncomment the template's ports block get no port mapping. The flag is a no-op when no ports are declared, so it's always safe to include.
- **Never tell users to run `--entrypoint bash`.** That bypasses `entrypoint.sh` and GSD's symlinks won't exist. The dispatch in `entrypoint.sh` is why `sandbox bash` works correctly.
- **`~/.claude.json` must be symlinked into the volume.** It lives at `$HOME` (sibling of `~/.claude/`), so it's outside the mounted volume by default. Without the symlink, onboarding flags, accepted-agreements state, and OAuth account metadata reset on every `--rm` even though `.credentials.json` (inside the volume) persists. The real file lives at `~/.claude/.claude-json-persisted` (paranoid name to avoid any chance of Claude Code scanning for a literal `.claude.json` inside `~/.claude/`).
- **`settings.json` must be symlinked from `/opt/gsd/`** — it carries GSD's hook wiring (SessionStart, PreToolUse, PostToolUse, statusLine). Without it the skills/agents are useless because no hooks fire. The entrypoint only links it if no real user file is present (symlinks count as "not real"); user overrides should go in `settings.local.json`.
- **The Dockerfile does `npm install -g` AND a separate installer run.** The global install gives the `gsd-tools` and `gsd-core` binaries on PATH; the installer run with `CLAUDE_CONFIG_DIR=/opt/gsd gsd-core --claude --global` lays down skills/agents/hooks/settings.json into `/opt/gsd/`. Passing an explicit runtime flag (`--claude`) plus location (`--global`) makes the installer non-interactive — no `--yes` flag exists in `gsd-core`. Removing either step breaks GSD.
- **Package rename history.** `@opengsd/get-shit-done-redux` → `@opengsd/gsd-core` (repo `open-gsd/get-shit-done-redux` → `open-gsd/gsd-core`). Binaries `get-shit-done-redux` → `gsd-core` (installer) and `gsd-sdk` → `gsd-tools` (CLI used by agents/hooks). Both repo and old npm tarball still resolve via redirect, but pin to the new names.
- **GSD has no commands/ entries — everything is skills.** As of GSD 1.8.0 `/opt/gsd/commands/` doesn't exist at all (earlier versions shipped it empty). The entrypoint's loop over `skills commands agents hooks` is robust to both (`[ -d "$src_dir" ] || continue`, plus `[ -e "$src" ] || continue` for the empty glob).
- **The root helper tree is `gsd-core/`; `get-shit-done/` is long gone.** GSD renamed it via installer migration `2026-06-02-rename-get-shit-done-to-gsd-core`, i.e. *before* 1.7.0 — so the entrypoint's original `get-shit-done` block was dead code and `~/.claude/gsd-core/` went unlinked on 1.7.0 and 1.8.0 alike. Verified against a real project volume: no `get-shit-done` link ever existed, and no `gsd-core` link either. The entrypoint now links whichever name is present and prunes a leftover symlink under the other (insurance; expected never to fire). Root-level links aren't covered by the `find -name 'gsd-*' -type l -delete` sweep, which only runs inside `skills/commands/agents/hooks`. Don't link `/opt/gsd/scripts/` — those are GSD's own build scripts (changesets, codegen), not runtime, and `scripts` is too generic a name to plant in `~/.claude`.
- **GSD's installer migrations are scoped to the install dir, not your project.** `gsd-install-state.json` tracks `schemaVersion` + `appliedMigrations`, all concerning install layout. Because `/opt/gsd` is rebuilt clean on every image build, migrations always run against a pristine tree and are trivially satisfied — and they have zero visibility into `~/.claude/`, where our symlinks live. Anything wrong on the volume side is ours to fix in `entrypoint.sh`; GSD will never repair it.
- **GSD exposes slash commands as skills, not `commands/` entries.** The npm package ships `commands/gsd/*.md`, but the `--claude` install path deliberately registers them as `gsd-<cmd>` skills (see `scripts/fix-slash-commands.cjs`: the installer rewrites `/gsd:<cmd>` → `gsd-<cmd>` for "runtimes that register skills under the canonical hyphen form"). So the file manifest has no `commands/` entries and `/opt/gsd/commands/` is absent — invoke `/gsd-<cmd>`, and don't "fix" the missing commands dir.
- **GSD 1.8.0's `settings.json` and skills use absolute `/opt/gsd/...` paths** (a consequence of installing with `CLAUDE_CONFIG_DIR=/opt/gsd`), and the skills' `gsd-tools` resolution chain falls back to `command -v gsd-tools`. So hooks fire even when a root-tree symlink is missing — meaning a broken rename fails quietly rather than loudly. Verify links explicitly after a GSD major/minor bump instead of assuming a working session means correct wiring.
- **Playwright browsers live at `/opt/playwright`, not `~/.cache/ms-playwright`.** `PLAYWRIGHT_BROWSERS_PATH` is set in the image. The default home-cache path is outside the mounted volume, so browsers there would be lost on every `--rm` and re-downloaded. Chromium only; `--with-deps` handles the OS libraries. `/opt/playwright` is chowned to `sandbox` so a project pinning a different Playwright version can `npx playwright install chromium` its matching build at runtime (ephemeral). The template sets `ipc: host` because Chromium crashes against Docker's default 64 MB `/dev/shm`.
- **`corepack enable` runs as root; `corepack prepare` must run as `sandbox`.** They're split across the Dockerfile deliberately. `enable` writes global shims (needs root), but `prepare` downloads the pnpm tarball into `$HOME/.cache/node/corepack` — so running it as root warms the *wrong* user's cache and every container start re-downloads pnpm (`! Corepack is about to download ...pnpm-*.tgz`). Unlike Playwright/pre-commit this needs no `/opt` path or env var: `$HOME/.cache` is image-only, since the mount covers only `~/.claude`. Verify with `pnpm --version` in a fresh container — a corepack download line means the split regressed.
- **`PRE_COMMIT_HOME` points into the claude-home volume** (`~/.claude/.pre-commit-cache`). The default `~/.cache/pre-commit` is outside the mounted volume, so hook environments would re-download/rebuild on every `--rm`. Dot-prefixed name inside `~/.claude` follows the `.claude-json-persisted` pattern. Consequence: `docker compose down -v` also wipes pre-commit envs (they rebuild on next use).
- **SSH: agent forwarding over key mounts, always.** The container runs `--dangerously-skip-permissions` + arbitrary npm installs, so treat it as hostile to secrets: a mounted key file can be read/exfiltrated; a forwarded agent socket can only sign while the container runs. Docs must never show mounting all of `~/.ssh`. `openssh-client` is explicitly installed (Debian `git` only *recommends* it; `--no-install-recommends` drops it). GitHub host keys are baked into `/etc/ssh/ssh_known_hosts` from `api.github.com/meta` (TLS-authenticated) because nothing outside `~/.claude` persists — without baking, every fresh container re-prompts for host keys.
- **GitHub CLI (`gh`) auth is token-only, never persisted.** `gh` is installed from its official apt repo. Auth is passed via `GH_TOKEN` in the environment (the template documents this), *not* `gh auth login` into a volume-backed `GH_CONFIG_DIR`. Same posture as SSH: the container runs `--dangerously-skip-permissions` + arbitrary npm installs, so an on-disk credential in the volume would be a reusable, exfiltratable secret surviving across `--rm`; an env-var token exists only while the container runs. Do not add `GH_CONFIG_DIR` into the claude-home volume — that would reintroduce the persisted-credential problem we deliberately avoid.
- **On Linux, build with `USER_UID=$(id -u) docker compose build`** so mounted file permissions match the host user. macOS defaults to 501 which is the build-arg default.
