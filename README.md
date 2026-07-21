# Claude Sandbox

A Docker container for running Claude Code with common development tools (Python, uv, Node.js, pnpm) and [GSD](https://github.com/open-gsd/gsd-core) preinstalled.

## How it works

The image is immutable: Claude Code and GSD are baked in at build time. State that needs to survive across runs (auth, conversation history, plugins, custom skills) lives outside the image — either in a named docker volume (recommended, via the compose template) or in a host bind mount (via `docker run`).

This repo contains two compose files for two distinct purposes:

| File | Purpose |
|---|---|
| `docker-compose.yml` (repo root) | Builds the `claude-sandbox` image. Run from this repo. |
| `template/docker-compose.yml` | Project template. Copy into a project to launch the sandbox. |

GSD itself lives at `/opt/gsd/` inside the image and is symlinked into `~/.claude/{skills,commands,agents,hooks}/gsd-*` on container start. Rebuilding the image with a newer GSD updates `/opt/gsd/`; the symlinks resolve to the new version automatically, so the state volume never shadows or fights image upgrades.

The entrypoint launches `claude` with `--dangerously-skip-permissions` by default — GSD's hook-driven workflow assumes this. The flag only applies inside this sandboxed container; if you need interactive permission prompts, override the entrypoint or run `claude` directly inside `sandbox bash`.

## Prerequisites

- Docker + Docker Compose v2
- One of:
  - An Anthropic API key (`ANTHROPIC_API_KEY`), or
  - A Claude account for OAuth login via `/login`

## Build the image

From this repo:

```bash
docker compose build
```

On Linux, override `USER_UID` so mounted file permissions match:

```bash
USER_UID=$(id -u) docker compose build
```

## Quick start (recommended): docker compose

Copy `template/docker-compose.yml` from this repo into the root of your project (renaming it to `docker-compose.yml` there), then from your project:

```bash
docker compose run --service-ports --rm sandbox
```

That's it. (`--service-ports` does nothing until you uncomment `ports:` in the template, but plain `run` silently ignores `ports:` — build the habit now so exposed ports work the day you need them.) Compose auto-prefixes the `claude-home` volume with the project name (defaulted from the directory basename), so it materializes as e.g. `myproject_claude-home`. Each project directory gets its own isolated volume — auth, history, plugins, and custom skills don't leak between projects.

### First login

```bash
docker compose run --service-ports --rm sandbox /login
```

Open the printed URL in your host browser, complete login, and credentials are saved to the named volume for future runs.

### One-shot prompt

```bash
docker compose run --service-ports --rm sandbox -p "Write a Python script that prints fibonacci numbers"
```

### Resume a previous session

```bash
docker compose run --service-ports --rm sandbox --continue        # most recent session
docker compose run --service-ports --rm sandbox --resume         # interactive picker
docker compose run --service-ports --rm sandbox --resume <id>    # specific session
```

The entrypoint forwards these flags to `claude`. Resuming works across `--rm` restarts because session transcripts live under `~/.claude/projects/` inside the `claude-home` volume, and the project is always mounted at the same path (`/home/sandbox/workspace`), which is how Claude Code keys sessions to a project. Note that `docker compose down -v` deletes session history along with the rest of the project's state.

### Drop into a shell

```bash
docker compose run --service-ports --rm sandbox bash
```

(Don't use `--entrypoint bash` — that bypasses the GSD symlink setup. The entrypoint detects `bash`/`sh` as the first argument and execs a shell after running setup.)

### Reset state for the project

```bash
docker compose down -v
```

### Customize

Edit the project's `docker-compose.yml` to expose ports, add environment variables, or mount extra directories — see the commented blocks in the template.

> **Why `--service-ports`?** `docker compose run` ignores the `ports:` section by default (a deliberate Docker behavior to prevent collisions with an already-running `up` instance). The flag makes `run` publish them, and is harmless when no ports are declared — which is why every command above includes it. Alternatively, `docker compose up` honors `ports:` without any extra flag.

## Alternate: docker run

For ad-hoc use without a `docker-compose.yml`:

```bash
docker run -it --rm \
  -v "$(pwd):/home/sandbox/workspace" \
  -v claude-sandbox-home:/home/sandbox/.claude \
  claude-sandbox
```

Or with a host bind-mount instead of a named volume:

```bash
docker run -it --rm \
  -v "$(pwd):/home/sandbox/workspace" \
  -v "$(pwd)/.claude-sandbox:/home/sandbox/.claude" \
  claude-sandbox
```

With an API key:

```bash
docker run -it --rm \
  -e ANTHROPIC_API_KEY \
  -v "$(pwd):/home/sandbox/workspace" \
  -v claude-sandbox-home:/home/sandbox/.claude \
  claude-sandbox
```

Expose ports:

```bash
docker run -it --rm \
  -p 3000:3000 -p 5173:5173 \
  -v "$(pwd):/home/sandbox/workspace" \
  -v claude-sandbox-home:/home/sandbox/.claude \
  claude-sandbox
```

## Git over SSH

The image includes the OpenSSH client with GitHub's host keys pre-pinned (fetched from GitHub's TLS-authenticated meta API at build time), so no host-key prompt appears on first clone. What it deliberately does **not** include is any credential — you choose how to provide one, and the choice has real security weight because this sandbox runs an autonomous agent with permissions skipped plus whatever your project's dependencies execute.

**Preferred: ssh-agent forwarding.** Mount the host agent's socket instead of key files. The container can request signatures while it runs, but the private key never enters the container and cannot be stolen for later use. This is also the only option for hardware-backed keys (Secure Enclave, YubiKey).

```yaml
# docker-compose.yml (macOS / Docker Desktop)
services:
  sandbox:
    volumes:
      - /run/host-services/ssh-auth.sock:/ssh-agent   # magic Docker Desktop path
    environment:
      SSH_AUTH_SOCK: /ssh-agent
```

On Linux, mount the real socket path: `- ${SSH_AUTH_SOCK}:/ssh-agent`. Either way, load your key into the host agent first (`ssh-add`; on macOS `ssh-add --apple-load-keychain`) — an empty agent forwards successfully but authenticates nothing.

**Custom agents (1Password, Secretive, etc.):** Docker Desktop forwards whatever `SSH_AUTH_SOCK` its backend saw at launch — the *default* launchd agent, not the agent named by `IdentityAgent` in your `~/.ssh/config` — and macOS cannot bind-mount an arbitrary host socket into a container. `launchctl setenv` alone is not reliably picked up; what works is quitting Docker Desktop and relaunching it with the variable set in the launching environment:

```bash
osascript -e 'quit app "Docker Desktop"'
SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" open -a "Docker Desktop"
```

This does not survive a reboot (Docker Desktop auto-starts with the default environment) — persist it with a LaunchAgent plist that runs `launchctl setenv SSH_AUTH_SOCK ...` at login, before Docker Desktop starts. Side benefit of agents like 1Password: they prompt per signing request, so every container use of your key is visible and consented.

**Fallback: read-only single-key mount.** If no agent is available, mount exactly one key, read-only:

```yaml
      - ~/.ssh/id_ed25519:/home/sandbox/.ssh/id_ed25519:ro
```

Understand the tradeoff: `:ro` prevents tampering but not reading — any process in the container can copy the key. Mitigate by using a dedicated low-privilege key (e.g. a per-repo deploy key) rather than your main identity, and never mount the whole `~/.ssh` directory (it exposes every identity plus your SSH config). On Linux, the key file's owner must match the container UID (`USER_UID` build arg) for OpenSSH's permission checks to pass.

For hosts other than GitHub, add their keys inside the container session (`ssh-keyscan gitlab.com >> ~/.ssh/known_hosts`) or extend `/etc/ssh/ssh_known_hosts` in the Dockerfile.

## GitHub CLI (`gh`)

The image includes the GitHub CLI, installed from GitHub's official apt repo. Like SSH, it ships with **no credential** — you supply one, and the choice carries the same security weight (autonomous agent, permissions skipped, arbitrary dependency code).

Auth is **token-only, passed through the environment** — `gh` reads `GH_TOKEN` automatically:

```yaml
    environment:
      GH_TOKEN: ${GH_TOKEN}
```

This is deliberate. Running `gh auth login` interactively would write a reusable OAuth credential to `gh`'s config dir; persisting that across `--rm` would mean pointing `GH_CONFIG_DIR` into the `claude-home` volume, leaving an exfiltratable secret on disk that any process in the container could read. An env-var token exists only while the container runs — the same reasoning that makes ssh-agent forwarding preferred over mounted key files. Prefer a short-lived, minimally-scoped token (a fine-grained PAT or `gh auth token` output).

## Playwright / browser testing

The image ships Playwright with headless Chromium preinstalled (browsers live at `/opt/playwright` inside the image via `PLAYWRIGHT_BROWSERS_PATH`, so they survive `--rm` and upgrade with image rebuilds). The `playwright` CLI is on PATH globally.

- **Headless only** — the container has no display server. Playwright defaults to headless, so tests and `playwright screenshot` just work; `--headed` and `codegen` won't.
- **Version matching:** if your project installs `@playwright/test` locally (the usual setup), Playwright looks up a browser build matching *that* version. Keep the project's version in line with the image's (`playwright --version` inside the container), or run `npx playwright install chromium` in the container to fetch the matching build (lands in `/opt/playwright`, but is lost on `--rm` — prefer version matching).
- **Only Chromium is baked in.** For Firefox/WebKit, add them to the `playwright install` line in the Dockerfile and rebuild.
- The template sets `ipc: host` — Chromium can crash against Docker's default 64 MB `/dev/shm` without it.

## Notes

- **File permissions:** the container runs as a non-root user. Default UID is 501 (macOS). On Linux, rebuild with `USER_UID=$(id -u) docker compose build`.
- **GSD upgrades:** rebuild the image (`docker compose build` from this repo). The next `docker compose run` in any project picks up the new GSD without any state-volume churn — the symlinks just point to the new version.
- **User-installed skills/plugins** (anything under `~/.claude/` that isn't a `gsd-*` symlink) persists in the `claude-home` volume and is untouched by image upgrades.

## Included tools

| Tool       | Description                  |
|------------|------------------------------|
| Node.js 22 | JavaScript runtime           |
| npm / npx  | Node package manager and runner |
| pnpm       | Fast, disk-efficient package manager |
| Python 3   | Python interpreter           |
| pip        | Python package installer     |
| uv / uvx   | Fast Python package manager  |
| git        | Version control              |
| gh         | GitHub CLI (token-only auth via `GH_TOKEN`) |
| build-essential | C/C++ compiler toolchain |
| jq         | JSON processor               |
| openssl    | TLS/crypto toolkit           |
| postgresql-client | psql CLI              |
| @opengsd/gsd-core | Spec-driven workflow for Claude Code |
| Playwright | Browser automation & E2E testing (Chromium baked in, headless) |
| pre-commit | Git hook framework (hook envs persist in the `claude-home` volume) |

## Documentation

- [Claude Code docs](https://code.claude.com/docs/en/overview)
- [GSD Core repo](https://github.com/open-gsd/gsd-core)
- [GSD Core docs](https://github.com/open-gsd/gsd-core/blob/main/docs/README.md)
