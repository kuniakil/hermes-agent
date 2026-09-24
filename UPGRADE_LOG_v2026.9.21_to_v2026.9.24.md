# Upgrade Log: v2026.9.21 → v2026.9.24

**Date**: 2026-09-25
**From**: `my-config-v2026.9.21` (Hermes Agent v0.21.4)
**To**: `my-config-v2026.9.24` (Hermes Agent v0.21.5)
**Source tag**: `v2026.9.24` (commit `f97608f178`)

---

## Scale

- **1,638 non-merge commits** between official tags
- **4,828 files changed** (+164,132 / −149,440)
- **460 merged PRs / 475 closed issues**

## Strategy

Linear history via `git checkout v2026.9.24` as base, then **hunk-level manual port** of our custom Docker layer (because the official Dockerfile changes were too extensive for clean cherry-pick). Workflow Purge Protection applied. Branch name: `my-config-v2026.9.24`.

## Commits Applied (7 total, linear)

| # | SHA | Subject |
|---|---|---|
| 1 | `413663402c` | feat(docker): re-port custom layer (SSH, locales, faster-whisper extras) onto v2026.9.24 |
| 2 | `f03c19dd8d` | fix(docker): re-port SSH server setup and npm cache isolation onto v2026.9.24 |
| 3 | `8ba12f2eb6` | fix(docker): restore docker/entrypoint-ssh.sh for Zeabur backward compatibility |
| 4 | `3ec9f5af79` | chore: carry forward my-config docker-compose.yml (uses HERMES_IMAGE env, TZ=Asia/Taipei) |
| 5 | `0680849e81` | chore: re-append Mac host resource constraint rule to AGENTS.md (v2026.9.24) |
| 6 | `4cad3f0daa` | chore: bump HERMES_IMAGE tag to v2026.9.24 |
| 7 | `4337455dd0` | chore(ci): purge official CI workflows; retain only ghcr-publish.yml |

## Conflicts Resolved

### 🔴 Dockerfile (hunk-level port, 7 hunks)

| Hunk | Action | Detail |
|---|---|---|
| A | Modify `apt-get install` | Add `openssh-server rsync locales`; append ssh-keygen + locale-gen + LC_ALL export |
| B | Modify Playwright install | Override `--only-shell` default back to `--with-deps chromium` (for SSH/agent-browser) |
| C | Add `/tmp/.npm-cache` mkdir | Sticky-bit isolation for global npm cache |
| D | Modify `uv sync` extras | Drop `--extra hindsight`; keep `--extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa` |
| E | Add `COPY --chmod=0755 docker/entrypoint-ssh.sh` | For Zeabur backward compat |
| F | Add `ENV HOME=/opt/data` | Prevent non-root processes from accessing /root |
| G | Add `/root/.npm` chown | Grant hermes UID 10000 ownership for npm cache writes |

### 🔴 stage2-hook.sh (hunk-level port, 2 hunks)

| Hunk | Action | Detail |
|---|---|---|
| A | Insert SSH server setup (82 lines) | Before `# --- Bootstrap HERMES_HOME as root ---`; sshd + authorized_keys + .bashrc + .profile |
| B | Insert `/tmp/.npm-cache` sticky + .npm cleanup | After official XDG_RUNTIME_DIR block |

### 🟡 entrypoint-ssh.sh (file-level restore)

Direct `git checkout my-config-v2026.9.21 -- docker/entrypoint-ssh.sh` — 13-line Zeabur backward-compat shim.

### 🟢 docker-compose.yml

Carry forward our 19-line my-config version (uses `${HERMES_IMAGE}` from `.env`, retains `TZ=Asia/Taipei` and `command: gateway run`). Smaller than official 76-line version but covers our k8s deployment needs.

### 🟢 AGENTS.md

Adopt official version (has new `hermes_platform.host` and `[tool.uv] exclude-newer` sections), append Mac Host Resource Constraint rule at end.

### 🟢 .env

Update `HERMES_IMAGE=ghcr.io/kuniakil/hermes-agent:v2026.9.21` → `:v2026.9.24`.

### 🟢 .github/workflows/

Workflow Purge Protection: deleted 23 official files, retained only `ghcr-publish.yml` from `my-config-v2026.9.21`.

## Key Official v0.21.5 Changes Adapted

1. **`hermes-agent` script entry point**: `run_agent:main` → `agent.legacy_cli:main` (we don't use this CLI, so no action needed)
2. **`--extra hindsight` removed**: We adjusted Dockerfile's `uv sync` command accordingly
3. **`HERMES_BOT_DESKTOP=1` opt-in**: Adopting official gating; we don't enable this build arg so Chromium-Desktop path stays unused
4. **Playwright install behavior**: `--only-shell` is official default; we override to `--with-deps chromium` for SSH/agent-browser compatibility
5. **XDG_RUNTIME_DIR security boundary**: Adopting official implementation; our SSH block doesn't reference this variable

## Verification

- [x] `bash -n docker/stage2-hook.sh` syntax check passed
- [x] `sh -n docker/entrypoint-ssh.sh` syntax check passed
- [x] Dockerfile: 67 RUN/COPY/ENV/ARG, 4 FROM, balanced heredocs
- [x] `git log --oneline my-config-v2026.9.21..my-config-v2026.9.24` shows 7 linear commits, no merges
- [x] `git status` clean (only `docs/` untracked artifacts)

## Custom Assets Carried Forward

- **SSH server**: openssh-server baked into Dockerfile; stage2-hook.sh auto-configures on `SSH_PUBLIC_KEY`
- **Locales**: en_US.UTF-8, zh_TW.UTF-8 (C.UTF-8 default)
- **Playwright Chromium**: full build (override official `--only-shell`)
- **uv sync extras**: edge-tts, firecrawl, dingtalk, feishu, exa
- **/tmp/.npm-cache**: sticky-bit isolation
- **/root/.npm**: chown to hermes UID 10000
- **ENV HOME=/opt/data**: prevent /root access by non-root
- **docker/entrypoint-ssh.sh**: Zeabur legacy compat shim
- **Mac Host Resource Constraint rule**: in AGENTS.md
- **Custom docker-compose.yml**: 19-line, with TZ + HERMES_IMAGE env

## Deferred / Out of Scope

- **Bot Screen (`HERMES_BOT_DESKTOP=1`)**: Adopting official path but not enabling it
- **Desktop plugin SDK wave**: All in main tree, no action needed (we don't run Desktop)
- **Per-profile stop/start/restart under host multiplexer**: New in official; benefits accrue automatically on image update
- **Connectors page replacing MCP tab**: Desktop-only; doesn't affect our k8s deployment
- **GPT-6 / Claude Opus 5.5 catalogs**: New model entries, no Docker/build impact

## Next Steps

1. Push branch: `git push kuniakil my-config-v2026.9.24`
2. Trigger CI: `gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v2026.9.24 -f tag_name=v2026.9.24 -f platforms=all`
3. Record GH Actions Run ID in worksheet
4. Update K8s deployment image tag to `v2026.9.24`
5. `hermes doctor` validation in pod