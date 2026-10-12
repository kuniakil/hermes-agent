# Upgrade Log: v0.21.6 → v0.21.7

**Date**: 2026-10-12  
**From**: `my-config-v0.21.6` (Hermes Agent v0.21.6 / upstream `v0.21.6`)  
**To**: `my-config-v0.21.7` (Hermes Agent v0.21.7)  
**Source tag**: `v0.21.7` (commit `00f69310e29c24dfd7c6bb258b0a2337d3455d79`, tree commit `71d34bad1045610252eda02ee79549436896e784`)  

---

## Scale

- **740 non-merge commits** between official releases
- **4,156 files changed** (+86,775 / −26,980)
- **204 merged PRs / 69 closed issues**

## Strategy

Linear history via `git checkout v0.21.7` as base, followed by a structured port of our custom Docker / SSH / locale layers onto the upstream PM architecture. Official CI workflows purged, retaining only our lightweight dual-architecture `ghcr-publish.yml`. Branch name: `my-config-v0.21.7`.

## Commits Applied (Linear)

| # | Subject |
|---|---|
| 1 | chore(ci): purge official CI workflows; retain only ghcr-publish.yml |
| 2 | fix(docker): restore docker/entrypoint-ssh.sh for Zeabur backward compatibility |
| 3 | chore: carry forward my-config docker-compose.yml (uses HERMES_IMAGE env, TZ=Asia/Taipei) |
| 4 | chore: re-append Mac host resource constraint rule to AGENTS.md (v0.21.6) |
| 5 | feat(docker): restore custom SSH setup and npm cache handling in stage2-hook.sh |
| 6 | feat(docker): re-port custom layer (SSH, locales, extras, permissions) onto v0.21.7 |
| 7 | fix(npm): apply security audit overrides to package.json |
| 8 | chore: bump HERMES_IMAGE tag to v0.21.7 |

## Changes & Adaptations in v0.21.7

### 1. Dockerfile & PM Selection Recording
- Upstream introduced `--record-selection` in `python3 -m pm.build_env` to record baked extras into the PM store `facts.json`. Our custom extras (`edge-tts`, `firecrawl`, `dingtalk`, `feishu`, `exa`) were preserved alongside `--record-selection`, ensuring runtime opt-in packages do not drop baked extras on reboot.
- Preserved `agent-browser` pre-staging via `pm.ensure` and symlink into `/usr/local/bin/agent-browser`.
- Preserved custom system layer: `openssh-server`, `rsync`, locales (`C.UTF-8`, `en_US.UTF-8`, `zh_TW.UTF-8`), `/bin/bash` default shell for hermes user.
- Preserved `/tmp/.npm-cache` sticky-bit directory, `/root/.npm` UID 10000 ownership, and `ENV HOME=/opt/data`.

### 2. Upstream Runtime & Dependency Bumps
- `nemo-relay` bumped from `>=0.9,<0.10` to `>=0.10,<0.11` for Python >=3.14.
- Root `package.json` devDependencies added `eslint 10.12.0`, `typescript 6.0.3`, `lefthook 2.1.14` and a `prepare` script. Security audit overrides (`js-yaml 4.3.2`, `undici 7.30.0`, `vitest 4.1.11`) preserved.
