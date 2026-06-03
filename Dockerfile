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
    postgresql-client \
    psmisc \
    && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Create a non-root user matching the host UID (default 501 for macOS)
ARG USER_UID=501
RUN useradd -m -s /bin/bash -u ${USER_UID} sandbox
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

# Lay down GSD content into an image-only path. The entrypoint symlinks
# each gsd-* entry into ~/.claude/{skills,commands,...} at runtime, so
# image rebuilds always deliver the latest GSD without the mounted volume
# shadowing it.
RUN mkdir -p /opt/gsd && chown sandbox:sandbox /opt/gsd
USER sandbox
RUN CLAUDE_CONFIG_DIR=/opt/gsd \
    gsd-core --claude --global

WORKDIR /home/sandbox/workspace

COPY --chown=sandbox:sandbox entrypoint.sh /home/sandbox/entrypoint.sh

ENTRYPOINT ["/home/sandbox/entrypoint.sh"]
