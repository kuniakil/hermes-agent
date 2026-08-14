# Upgrade Log: v2026.7.7.2 to v2026.7.20

This document tracks the upgrade from custom branch version `v2026.7.7.2` to the official upstream version `v2026.7.20` ("The Quicksilver Release").

## 1. Upstream Changes Summary (v2026.7.20)
* **Build Stability**: Full transition to Acquire::Retries=3, `--retry 3` for apt-get and curl operations to avoid transient network CI failures.
* **s6-overlay Improvements**: Changed `ADD` instruction to `curl --retry 3` for s6-overlay files downloading.
* **Tini Shim**: Moved from simple symlinking to a dedicated shell script (`docker/tini-shim.sh`) which strips tini arguments before exec-ing `/init` to fix boot-loop bugs (#66679).
* **Playwright Retry Logic**: Retries installation up to 3 times inside the Docker build process.
* **ENV Variable integration**: Added `ENV HERMES_TUI_DIR=/opt/hermes/ui-tui` officially in Dockerfile.

## 2. Applied Custom Commits
The following custom commits were cherry-picked on top of upstream `v2026.7.20`:

| Original Commit | New Commit | Title |
|-----------------|------------|-------|
| `73b0ecaf3` | `33deb44ae` | feat: integrate SSH into official s6-overlay architecture (Resolved conflict in Dockerfile) |
| `aa9283d68` | `9deea2144` | chore: add .env with HERMES_IMAGE for docker-compose |
| `2eb8b970b` | `c4610d73a` | chore: add ghcr-publish workflow for Docker image build |
| `1ec45e5f8` | `9154d1c66` | feat: add entrypoint-ssh.sh for Zeabur compatibility |
| `10b755299` | `e67aa6aef` | fix: handle non-PID 1 environment (Zeabur) |
| `ec125c963` | `e72ef63b1` | fix: use su-exec instead of main-wrapper.sh for Zeabur |
| `0d457f64a` | `cf74eecb4` | fix: use su instead of su-exec for Zeabur |
| `4546183f8` | `2b3a76a43` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| `f3c1955c5` | `a1e642bff` | fix(docker): export HERMES_TUI_DIR in SSH session rc to skip runtime npm install |
| `3cc124710` | `2d97f19fc` | docs: add GEMINI.md upgrade SOP and behavior rules |
| `00b0530ad` | `a669b46fa` | docs: update GEMINI.md upgrade SOP to use GitHub CI/CD workflow instead of local build |
| `c356e7e19` | `aeab2eab8` | docs: improve GEMINI.md to enforce checkout+cherry-pick branch workflow and add conflict guidelines |
| `9f880affc` | `6fb694767` | docs: update upgrade log to document hotfixes and C/C++ toolchain addition |
| `1ee05f697` | `09922388d` | docs: add upgrade log v2026.6.5→v2026.6.19, update GEMINI.md SOP, restore v5.16 upgrade log |
| `56646cdf1` | `67adcdbf7` | docs: document SSH hermes --tui EACCES hotfix in upgrade log |
| `975af3dc7` | `c01a454af` | chore: bump HERMES_IMAGE tag to v2026.7.7.2 |
| `df7b23a56` | `badc54d33` | docs: add upgrade log and execution plan v2026.6.19 to v2026.7.7.2 |
| (New)           | `de7bdbefc` | chore: bump HERMES_IMAGE tag to v2026.7.20 |

## 3. Conflict Resolution Detail

### Dockerfile (Apt installation block)
* **Conflict**: Merge conflict between official `Acquire::Retries=3` introduction and our custom `openssh-server` package requirement along with the ssh-keygen setup commands.
* **Resolution**: Merged both changes. Retained official retry flags, our SSH server packages, and the host key initialization line:
```dockerfile
RUN apt-get -o Acquire::Retries=3 update && \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
    ca-certificates curl iputils-ping python3 python-is-python3 ripgrep ffmpeg gcc g++ make cmake python3-dev python3-venv libffi-dev libolm-dev procps git openssh-client openssh-server docker-cli xz-utils && \
    mkdir -p /var/run/sshd && ssh-keygen -A && \
    rm -rf /var/lib/apt/lists/*
```
* Note: `ENV HERMES_TUI_DIR=/opt/hermes/ui-tui` was natively integrated by upstream at line 295. We kept the official line.
