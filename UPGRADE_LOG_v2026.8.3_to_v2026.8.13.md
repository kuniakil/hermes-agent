# Upgrade Log: v2026.8.3 → v2026.8.13

**Upgrade Date**: 2026-08-14
**Official Release**: [Hermes Agent v2026.8.13](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.8.13)

## Summary

- **1,620 commits** between v2026.8.3 and v2026.8.13
- **2,226 files changed**, +238,517 / -74,528 lines
- Official Docker architecture stability:
  - `Dockerfile`: 0 changes upstream
  - `docker/stage2-hook.sh`: Official added loopback `API_SERVER_KEY` generation logic (cleanly auto-merged with our SSH / PYTHONPATH customizations)
- Included full UTF-8 locale + rsync support

## Custom Commits Applied

| Commit Hash | Description |
|-------------|-------------|
| `06aa6c5e0d` | chore: add .env with HERMES_IMAGE for docker-compose |
| `47fdcef89c` | chore: add ghcr-publish workflow for Docker image build |
| `9f8bdeb56e` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| `c4248b3d6f` | feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture |
| `2ef6fb082a` | feat(docker): add rsync, locales, and full UTF-8 support |
| `6a795ae450` | chore: bump HERMES_IMAGE tag to v2026.8.13 |

## Conflicts Encountered

**Zero conflicts.** All commits cherry-picked cleanly. `docker/stage2-hook.sh` auto-merged without manual intervention.

## CI/CD and Deployment Note

- Docker image build triggered via GitHub Actions (`gh workflow run ghcr-publish.yml`).
- Local `.env` updated to `ghcr.io/kuniakil/hermes-agent:v2026.8.13`.
- Kubernetes k3s (n100) manifests under `~/kubernetes/hermes/overlays/n100` synchronized with new image tag `v2026.8.13`.
