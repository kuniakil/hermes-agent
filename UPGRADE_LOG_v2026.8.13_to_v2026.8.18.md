# Upgrade Log: v2026.8.13 → v2026.8.18

**Upgrade Date**: 2026-08-18
**Official Release**: [Hermes Agent v2026.8.18](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.8.18)

## Summary

- **~30 commits** between v2026.8.13 and v2026.8.18
- **1723 files changed**, +192,706 / -10,161 lines
- Official Docker architecture stability:
  - `Dockerfile`: 0 changes upstream (identical between v2026.8.13 and v2026.8.18)
  - `docker/stage2-hook.sh`: 0 changes upstream
  - `docker/entrypoint-dispatch.sh`: 0 changes upstream
  - `docker/entrypoint-ssh.sh`: 0 changes upstream (our custom file)
  - `docker-compose.yml`: 0 changes upstream (official version unchanged since v2026.8.13)
- Official changes include:
  - Desktop app: glass/frost UI improvements, cross-machine group routing fix
  - Bot mode: multiple groups per bot support, fresh-room name uniquify fix
  - Delegation: subagents stay visible across parent-agent rebuilds
  - Version bump: pyproject.toml 0.20.1 → 0.20.4
  - Dev deps: mcp 1.28.1 → 2.0.0, httpx2 added, get-windows moved to optional

## Custom Commits Applied

| Commit Hash | Description |
|-------------|-------------|
| `06aa6c5e0d` | chore: add .env with HERMES_IMAGE for docker-compose |
| `47fdcef89c` | chore: add ghcr-publish workflow for Docker image build |
| `9f8bdeb56e` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| `c4248b3d6f` | feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture |
| `2ef6fb082a` | feat(docker): add rsync, locales, and full UTF-8 support |
| `a6aa9622b5` | feat(docker): install full Playwright Chromium with proper permissions |
| `6a795ae450` | chore: bump HERMES_IMAGE tag to v2026.8.13 |
| `4c478cec43` | docs: add upgrade log v2026.8.3 to v2026.8.13 |
| `b795ea8e43` | docs: update GEMINI.md with Playwright Chromium addition |
| `67cf1f4b51` | ci: add platform choice to workflow defaulting to amd64 |
| `57f9ec84c7` | docs: update workflow trigger example with platforms parameter |

## Conflicts Encountered

**Zero conflicts.** All 11 commits cherry-picked cleanly. No Docker file conflicts due to upstream stability.

## CI/CD and Deployment Note

- Docker image build triggered via GitHub Actions (`gh workflow run ghcr-publish.yml`).
- Local `.env` updated to `ghcr.io/kuniakil/hermes-agent:v2026.8.18`.
- Kubernetes k3s (n100) manifests under `~/kubernetes/hermes/overlays/n100` synchronized with new image tag `v2026.8.18`.
