# Claude Sandbox

A Docker container for running Claude Code with common development tools (Python, uv, Node.js, npm, npx).

## Prerequisites

- Docker installed and running
- One of the following for authentication:
  - An Anthropic API key (`ANTHROPIC_API_KEY`), **or**
  - A Claude account for OAuth login via `/login`

## Build

```bash
docker build -t claude-sandbox .
```

The container user defaults to UID 501 (macOS default). On Linux, pass your UID so mounted file permissions match:

```bash
docker build --build-arg USER_UID=$(id -u) -t claude-sandbox .
```

## Quick Start

From your project directory:

```bash
mkdir -p .claude-state
docker run -it --rm \
  -v "$(pwd)/.claude-state:/home/sandbox/state" \
  -v "$(pwd):/home/sandbox/workspace" \
  claude-sandbox
```

This mounts two things:
- **`.claude-state/`** — persists Claude credentials, settings, and history across runs
- **Current directory** — your project files, editable on the host and visible inside the container

Files created or modified by Claude appear directly in your local directory for use with your editor, git, and other host tools.

> **Important:** `.claude-state/` contains OAuth tokens. The container automatically appends `.claude-state/` to your workspace `.gitignore` to prevent committing secrets.

GSD skills (`/gsd:new-project`, `/gsd:help`, etc.) are pre-installed in the container and automatically seeded into `.claude-state/` on first run.

## Authentication

### Option A: API key

```bash
export ANTHROPIC_API_KEY=sk-ant-...
docker run -it --rm \
  -e ANTHROPIC_API_KEY \
  -v "$(pwd)/.claude-state:/home/sandbox/state" \
  -v "$(pwd):/home/sandbox/workspace" \
  claude-sandbox
```

### Option B: OAuth login (`/login`)

The `/login` flow displays a URL that you open in your host browser — no browser is needed inside the container.

**First-time login:**

```bash
mkdir -p .claude-state
docker run -it --rm \
  -v "$(pwd)/.claude-state:/home/sandbox/state" \
  claude-sandbox /login
```

Copy the URL, open it in your host browser, and complete the login. Credentials are saved to `.claude-state/` in your current directory and reused on subsequent runs.

## Run

### Standard usage

```bash
docker run -it --rm \
  -v "$(pwd)/.claude-state:/home/sandbox/state" \
  -v "$(pwd):/home/sandbox/workspace" \
  claude-sandbox
```

### With `--dangerously-skip-permissions`

```bash
docker run -it --rm \
  -v "$(pwd)/.claude-state:/home/sandbox/state" \
  -v "$(pwd):/home/sandbox/workspace" \
  claude-sandbox --dangerously-skip-permissions
```

### One-shot prompt

```bash
docker run -it --rm \
  -v "$(pwd)/.claude-state:/home/sandbox/state" \
  -v "$(pwd):/home/sandbox/workspace" \
  claude-sandbox -p "Write a Python script that prints fibonacci numbers"
```

### Mount a different project directory

```bash
docker run -it --rm \
  -v "$(pwd)/.claude-state:/home/sandbox/state" \
  -v /path/to/your/repo:/home/sandbox/workspace \
  claude-sandbox
```

### Mount additional directories

```bash
docker run -it --rm \
  -v "$(pwd)/.claude-state:/home/sandbox/state" \
  -v "$(pwd):/home/sandbox/workspace" \
  -v ~/datasets:/home/sandbox/data:ro \
  claude-sandbox
```

### Expose ports for web development

If Claude builds an app that runs a dev server inside the container, use `-p` to map ports to your host:

```bash
docker run -it --rm \
  -v "$(pwd)/.claude-state:/home/sandbox/state" \
  -v "$(pwd):/home/sandbox/workspace" \
  -p 3000:3000 \
  claude-sandbox
```

Then access the app at `http://localhost:3000` on your host machine. Add multiple `-p` flags for additional ports:

```bash
-p 3000:3000 \
-p 5173:5173 \
```

### Drop into a shell

```bash
docker run -it --rm \
  --entrypoint bash \
  -v "$(pwd)/.claude-state:/home/sandbox/state" \
  -v "$(pwd):/home/sandbox/workspace" \
  claude-sandbox
```

> **Note on file permissions:** The container runs as a non-root user (`sandbox`). The default UID is 501 (macOS). If you encounter permission errors on mounted files on Linux, rebuild with `--build-arg USER_UID=$(id -u)` to match your host user.

## Included Tools

| Tool       | Description                  |
|------------|------------------------------|
| Node.js 22 | JavaScript runtime           |
| npm / npx  | Node package manager and runner |
| Python 3   | Python interpreter           |
| pip        | Python package installer     |
| uv / uvx   | Fast Python package manager  |
| git        | Version control              |
| build-essential | C/C++ compiler toolchain |
| get-shit-done-cc | Task runner for Claude Code |

## Documentation

- [Claude Code Documentation](https://code.claude.com/docs/en/overview) — official docs for Claude Code CLI usage, configuration, and features
- [Get Shit Done User Guide](https://github.com/gsd-build/get-shit-done/blob/main/docs/USER-GUIDE.md) — usage guide for the get-shit-done-cc task runner
