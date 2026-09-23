# Upgrade Log: v2026.7.20 to v2026.7.30

This document tracks the upgrade from custom branch version `v2026.7.20` to the official upstream version `v2026.7.30` ("The Sapphire Release").

## 1. Upstream Changes Summary (v2026.7.30)
* **Build Stability**: Continued use of `Acquire::Retries=3` for `apt-get` and added `--retry 3` for s6-overlay tarball downloads via `curl`.
* **Tini Shim**: Moved to `docker/tini-shim.sh` with enhanced checks for legacy entrypoint invocations.
* **Playwright Retry**: Retries installation up to 3 times inside the Docker build process.
* **ENV Variables**: Added `ENV HERMES_TUI_DIR=/opt/hermes/ui-tui` officially in Dockerfile.
* **Apps Workspace**: Added `COPY apps/shared/ apps/shared/` to support shared UI components across monorepo workspace.

## 2. Applied Custom Commits
The following custom commits were cherry-picked on top of upstream `v2026.7.30`:

| Original Commit | New Commit | Title |
|-----------------|------------|-------|
| `33deb44ae` | `bc325133a` | feat: integrate SSH into official s6-overlay architecture |
| `9deea2144` | `eb7e5dcb8` | chore: add .env with HERMES_IMAGE for docker-compose |
| `c4610d73a` | `8c65f00af` | chore: add ghcr-publish workflow for Docker image build |
| `9154d1c66` | `adb7f5713` | feat: add entrypoint-ssh.sh for Zeabur compatibility |
| `e67aa6aef` | `f255af53c` | fix: handle non-PID 1 environment (Zeabur) |
| `e72ef63b1` | `5152c99a5` | fix: use su-exec instead of main-wrapper.sh for Zeabur |
| `cf74eecb4` | `75e0c5f5f` | fix: use su instead of su-exec for Zeabur |
| `2b3a76a43` | `e3252b8da` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| `a1e642bff` | `fc9de73ed` | fix(docker): export HERMES_TUI_DIR in SSH session rc |

> Note: `.env` image tag updates are managed via Kustomize overlay (`hermes/overlays/n100`) in Kubernetes.

## 3. Conflict Resolution Detail

### Dockerfile
* **Conflict**: Merge conflict between upstream SQLite build setup / `NODE_OPTIONS` block and our SSH package additions.
* **Resolution**: Kept upstream SQLite build instructions and `NODE_OPTIONS`, while preserving `openssh-server`, `openssh-client`, and the ssh-keygen initialization line in the apt-get block:
```dockerfile
RUN apt-get -o Acquire::Retries=3 update && \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
    ca-certificates curl iputils-ping python3 python-is-python3 ripgrep ffmpeg gcc g++ make cmake python3-dev python3-venv libffi-dev libolm-dev procps git openssh-client openssh-server docker-cli xz-utils && \
    mkdir -p /var/run/sshd && ssh-keygen -A && \
    rm -rf /var/lib/apt/lists/*
```
