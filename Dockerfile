FROM node:22-bookworm-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    jq \
    openssl \
    openssh-client \
    postgresql-client \
    psmisc \
    && rm -rf /var/lib/apt/lists/*

# Pin GitHub's SSH host keys system-wide. Fetched from the TLS-authenticated
# meta API (stronger than ssh-keyscan's trust-on-first-use), baked at build
# time because nothing outside ~/.claude persists across --rm — without this,
# every fresh container would prompt (or blindly accept) GitHub's host key.
RUN curl -fsSL https://api.github.com/meta \
    | jq -r '.ssh_keys[] | "github.com \(.)"' > /etc/ssh/ssh_known_hosts \
    && grep -q ssh-ed25519 /etc/ssh/ssh_known_hosts

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Create a non-root user matching the host UID (default 501 for macOS)
ARG USER_UID=501
RUN useradd -m -s /bin/bash -u ${USER_UID} sandbox
# Docker Desktop's forwarded ssh-agent socket (/run/host-services/
# ssh-auth.sock) arrives as root:root mode 660. Group-root membership is
# the minimal grant that lets the non-root user reach it — on
# bookworm-slim nothing of consequence is group-root writable, and the
# alternative (root entrypoint wrapper that chowns then drops privileges)
# puts an actual root process in every container start.
RUN usermod -aG root sandbox
USER sandbox

# Install Claude Code via the native installer (the supported install
# method; it supports in-place self-updates). It lands at
# ~/.local/bin/claude as a launcher into versioned binaries under
# ~/.local/share/claude/. HOME is fixed at /home/sandbox in this image, so
# this single native install is canonical — we put ~/.local/bin on PATH
# instead of copying the launcher to /usr/local/bin. (That copy used to
# leave two `claude` binaries in the image; current Claude Code flags the
# copy as a leftover "npm-global" install via the multi-install warning.)
ENV PATH="/home/sandbox/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash

USER root
# Install GSD globally so `gsd-tools` is on PATH (GSD agents/hooks invoke
# `gsd-tools ...`). npx alone leaves the shim in an npx-cache dir that
# won't survive into the running container.
RUN npm install -g @opengsd/gsd-core@latest

# Playwright for automated testing/QA. Browsers go to an image-only path
# (like /opt/gsd) instead of the default ~/.cache/ms-playwright — the home
# cache isn't in the mounted volume, so browsers there would be lost on
# every --rm and re-downloaded each run. ENV covers both the build-time
# install below and runtime resolution. Global @playwright/test puts the
# `playwright` CLI on PATH (same rationale as gsd-tools above); chromium
# only, to keep the image size down. chown lets a project pin a different
# Playwright version and `playwright install chromium` its matching
# browser at runtime (ephemeral, but possible).
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright
RUN npm install -g @playwright/test@latest && \
    playwright install --with-deps chromium && \
    rm -rf /var/lib/apt/lists/* && \
    chown -R sandbox:sandbox /opt/playwright

# Lay down GSD content into an image-only path. The entrypoint symlinks
# each gsd-* entry into ~/.claude/{skills,commands,...} at runtime, so
# image rebuilds always deliver the latest GSD without the mounted volume
# shadowing it.
RUN mkdir -p /opt/gsd && chown sandbox:sandbox /opt/gsd
USER sandbox
RUN CLAUDE_CONFIG_DIR=/opt/gsd \
    gsd-core --claude --global

# pre-commit for git hook management. Installed via uv tool → ~/.local/bin
# (already on PATH). Hook environments default to ~/.cache/pre-commit,
# which is outside the mounted volume and would be rebuilt on every --rm;
# point PRE_COMMIT_HOME into the claude-home volume so they persist.
# The dot-prefixed name keeps it out of Claude Code's way inside ~/.claude
# (same pattern as .claude-json-persisted).
ENV PRE_COMMIT_HOME=/home/sandbox/.claude/.pre-commit-cache
RUN uv tool install pre-commit

WORKDIR /home/sandbox/workspace

COPY --chown=sandbox:sandbox entrypoint.sh /home/sandbox/entrypoint.sh

ENTRYPOINT ["/home/sandbox/entrypoint.sh"]
