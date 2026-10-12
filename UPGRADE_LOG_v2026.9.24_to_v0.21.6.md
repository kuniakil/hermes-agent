# Upgrade Log: v2026.9.24 → v0.21.6

**Date**: 2026-10-10  
**From**: `my-config-v2026.9.24` (Hermes Agent v0.21.5 / upstream `v2026.9.24`)  
**To**: `my-config-v0.21.6` (Hermes Agent v0.21.6)  
**Source tag**: `v0.21.6` (commit `818c13be1dc4fd28987e1e881a9408224afd4535`)  

---

## Scale

- **8,867 non-merge commits** between official releases
- **8,342 files changed** (+772,490 / −225,600)
- **2,106 merged PRs / 3,027 closed issues**

## Strategy

Linear history via `git checkout v0.21.6` as base, followed by a structured **hunk-level port** of our custom Docker / SSH / locale layers onto the upstream PM architecture. Official CI workflows purged, retaining only our lightweight dual-architecture `ghcr-publish.yml`. Branch name: `my-config-v0.21.6`.

## Commits Applied (Linear)

| # | SHA | Subject |
|---|---|---|
| 1 | `97e144194e` | chore(ci): purge official CI workflows; retain only ghcr-publish.yml |
| 2 | `906a8d4101` | fix(docker): restore docker/entrypoint-ssh.sh for Zeabur backward compatibility |
| 3 | `26086778e3` | chore: carry forward my-config docker-compose.yml (uses HERMES_IMAGE env, TZ=Asia/Taipei) |
| 4 | `227c6cbe2d` | chore: re-append Mac host resource constraint rule to AGENTS.md (v0.21.6) |
| 5 | `a7e8db1d69` | fix(docker): re-port SSH server setup and npm cache isolation onto v0.21.6 |
| 6 | `f3d3911ed4` | feat(docker): re-port custom layer (SSH, locales, extras, permissions) onto v0.21.6 |
| 7 | `4a5d31131a` | chore: bump HERMES_IMAGE tag to v0.21.6 |

## Changes & Adaptations in v0.21.6

### 1. Dockerfile & Package Management (PM) Refactor
Upstream restructured `Dockerfile` into a multi-stage layout using the new `pm` package manager:
- `python3 -m pm.build_env` replaces bare `uv sync`.
- Chromium is pre-staged by PM at `/opt/hermes/tools` with its binary path recorded in `/etc/hermes/agent-browser-executable-path`. The old `npx playwright install --with-deps chromium` override was cleanly dropped as PM stages full Chromium by default.
- Added extras (`edge-tts`, `firecrawl`, `dingtalk`, `feishu`, `exa`) to `pm.build_env`.
- Preserved custom system layer: `openssh-server`, `rsync`, `locales` (`C.UTF-8`, `en_US.UTF-8`, `zh_TW.UTF-8`).
- Preserved `/tmp/.npm-cache` sticky-bit directory, `/root/.npm` UID 10000 ownership, and `ENV HOME=/opt/data`.

### 2. Startup Hook (`stage2-hook.sh`)
- SSH daemon setup block ported cleanly before the UID/GID remap block.
- Interactive login shell environment (`.bashrc` / `.profile`) auto-sources `/opt/data/.env`, exports `HERMES_TUI_DIR=/opt/hermes/ui-tui`, and loads s6 container environment variables.
- Verified coexistence with new PM dependency generation recovery (`refresh_dependencies`) and `agent-browser` Chromium discovery.
