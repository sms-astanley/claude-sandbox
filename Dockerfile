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
    && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Create a non-root user matching the host UID (default 501 for macOS)
ARG USER_UID=501
RUN useradd -m -s /bin/bash -u ${USER_UID} sandbox
USER sandbox

# Install Claude Code via native installer, then copy to a global path
# so the binary works regardless of HOME
RUN curl -fsSL https://claude.ai/install.sh | bash
USER root
RUN cp /home/sandbox/.local/bin/claude /usr/local/bin/claude
USER sandbox

# Set HOME to a state directory so all Claude config (~/.claude/ and
# ~/.claude.json) lands inside a single mountable path
ENV HOME="/home/sandbox/state"
ENV PATH="/home/sandbox/state/.local/bin:${PATH}"
RUN mkdir -p /home/sandbox/state

# Install GSD skills into a staging area baked into the image
RUN npx get-shit-done-cc@latest --claude --global
USER root
RUN cp -r /home/sandbox/state/.claude /opt/gsd-seed
USER sandbox

COPY --chown=sandbox:sandbox entrypoint.sh /home/sandbox/entrypoint.sh

WORKDIR /home/sandbox/workspace

ENTRYPOINT ["/home/sandbox/entrypoint.sh"]
