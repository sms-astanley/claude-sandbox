# Claude Sandbox

A Docker container for running Claude Code with common development tools (Python, uv, Node.js, pnpm) and [GSD](https://github.com/open-gsd/get-shit-done-redux) preinstalled.

## How it works

The image is immutable: Claude Code and GSD are baked in at build time. State that needs to survive across runs (auth, conversation history, plugins, custom skills) lives outside the image — either in a named docker volume (recommended, via the compose template) or in a host bind mount (via `docker run`).

This repo contains two compose files for two distinct purposes:

| File | Purpose |
|---|---|
| `docker-compose.yml` (repo root) | Builds the `claude-sandbox` image. Run from this repo. |
| `template/docker-compose.yml` | Project template. Copy into a project to launch the sandbox. |

GSD itself lives at `/opt/gsd/` inside the image and is symlinked into `~/.claude/{skills,commands,agents,hooks}/gsd-*` on container start. Rebuilding the image with a newer GSD updates `/opt/gsd/`; the symlinks resolve to the new version automatically, so the state volume never shadows or fights image upgrades.

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
docker compose run --rm sandbox
```

That's it. Compose auto-prefixes the `claude-home` volume with the project name (defaulted from the directory basename), so it materializes as e.g. `myproject_claude-home`. Each project directory gets its own isolated volume — auth, history, plugins, and custom skills don't leak between projects.

### First login

```bash
docker compose run --rm sandbox /login
```

Open the printed URL in your host browser, complete login, and credentials are saved to the named volume for future runs.

### One-shot prompt

```bash
docker compose run --rm sandbox -p "Write a Python script that prints fibonacci numbers"
```

### Drop into a shell

```bash
docker compose run --rm sandbox bash
```

(Don't use `--entrypoint bash` — that bypasses the GSD symlink setup. The entrypoint detects `bash`/`sh` as the first argument and execs a shell after running setup.)

### Reset state for the project

```bash
docker compose down -v
```

### Customize

Edit the project's `docker-compose.yml` to expose ports, add environment variables, or mount extra directories — see the commented blocks in the template.

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

With `--dangerously-skip-permissions` (how GSD is intended to run):

```bash
docker run -it --rm \
  -v "$(pwd):/home/sandbox/workspace" \
  -v claude-sandbox-home:/home/sandbox/.claude \
  claude-sandbox --dangerously-skip-permissions
```

Expose ports:

```bash
docker run -it --rm \
  -p 3000:3000 -p 5173:5173 \
  -v "$(pwd):/home/sandbox/workspace" \
  -v claude-sandbox-home:/home/sandbox/.claude \
  claude-sandbox
```

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
| build-essential | C/C++ compiler toolchain |
| jq         | JSON processor               |
| openssl    | TLS/crypto toolkit           |
| postgresql-client | psql CLI              |
| @opengsd/get-shit-done-redux | Spec-driven workflow for Claude Code |

## Documentation

- [Claude Code docs](https://code.claude.com/docs/en/overview)
- [GSD (redux) repo](https://github.com/open-gsd/get-shit-done-redux)
- [GSD user guide](https://github.com/open-gsd/get-shit-done-redux/blob/main/docs/USER-GUIDE.md)
