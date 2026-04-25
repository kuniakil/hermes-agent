FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b AS uv_source
FROM tianon/gosu:1.19-trixie@sha256:3b176695959c71e123eb390d427efc665eeb561b1540e82679c15e992006b8b9 AS gosu_source
FROM debian:13.4

# Disable Python stdout buffering to ensure logs are printed immediately
ENV PYTHONUNBUFFERED=1

# Store Playwright browsers outside the volume mount so the build-time
# install survives the /opt/data volume overlay at runtime.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# Limit Node memory to prevent OOM during build
ENV NODE_OPTIONS="--max-old-space-size=4096"

# Install system dependencies in one layer, clear APT cache
# tini reaps orphaned zombie processes (MCP stdio subprocesses, git, bun, etc.)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential nodejs npm python3 ripgrep ffmpeg gcc python3-dev libffi-dev procps git openssh-client docker-cli tini && \
    rm -rf /var/lib/apt/lists/*

# Non-root user for runtime; UID can be overridden via HERMES_UID at runtime
RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/
COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

WORKDIR /opt/hermes

# ---------- Source code ----------
COPY --chown=hermes:hermes . .

# ---------- Build dependencies and assets ----------
# Install dependencies for everything
RUN npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell

# Install esbuild and typescript globally to ensure they are always in the PATH for builds
RUN npm install -g esbuild typescript

# Build web dashboard
RUN cd web && npm install --prefer-offline --no-audit && npm run build

# Build TUI - we must ensure @hermes/ink is built first to produce ink-bundle.js
RUN cd ui-tui/packages/hermes-ink && \
    mkdir -p dist && \
    esbuild src/entry-exports.ts --bundle --platform=node --format=esm --packages=external --outfile=dist/ink-bundle.js && \
    ls -l dist/ink-bundle.js

# Now build the rest of ui-tui
RUN cd ui-tui && npm install --prefer-offline --no-audit && npx tsc -p tsconfig.build.json && chmod +x dist/entry.js

# ---------- Permissions ----------
# Make install dir world-readable so any HERMES_UID can read it at runtime.
# The venv needs to be traversable too.
USER root
RUN chmod -R a+rX /opt/hermes
# Start as root so the entrypoint can usermod/groupmod + gosu.
# If HERMES_UID is unset, the entrypoint drops to the default hermes user (10000).

# ---------- Python virtualenv ----------
RUN uv venv && \
    uv pip install --no-cache-dir -e ".[all]"

# ---------- Runtime ----------
ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
ENV HERMES_HOME=/opt/data
ENV PATH="/opt/data/.local/bin:${PATH}"
VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/usr/bin/tini", "-g", "--", "/opt/hermes/docker/entrypoint.sh" ]
