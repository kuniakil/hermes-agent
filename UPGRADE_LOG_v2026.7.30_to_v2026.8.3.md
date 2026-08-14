# Upgrade Log: v2026.7.30 → v2026.8.3 (v0.20.0)

**Upgrade Date**: 2026-08-06
**Official Release**: [Hermes Agent v0.20.0 (2026.8.3)](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.8.3)

## Summary

- **945 commits** between v2026.7.30 and v2026.8.3
- **1,162 files changed**, +117,948 / -13,624 lines
- Major Docker architecture change: new `entrypoint-dispatch.sh` replaces direct `/init` ENTRYPOINT
- Node upgraded from 22 to 26 (corepack dropped upstream)

## Custom Commits Applied (15 total)

### Direct Cherry-picks (12 commits, zero conflicts)

| New Hash | Original Hash | Description |
|----------|--------------|-------------|
| `e74395e3c2` | `eb7e5dcb8c` | chore: add .env with HERMES_IMAGE for docker-compose |
| `58e24e08ef` | `8c65f00afa` | chore: add ghcr-publish workflow for Docker image build |
| `8399612bcf` | `e3252b8daf` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| `df849a1e16` | `ce755fce20` | docs: update GEMINI.md upgrade SOP |
| `de129c93cb` | `937035d9a3` | docs: update upgrade log hotfixes + C/C++ toolchain |
| `52253ea3bf` | `dc493fa364` | docs: upgrade log v2026.6.5→v2026.6.19 |
| `04534510ec` | `83edc7ecef` | docs: SSH hermes --tui EACCES hotfix |
| `e0bc10fd56` | `17fe215637` | chore: bump HERMES_IMAGE tag to v2026.7.7.2 |
| `1dc9cb955f` | `e55c516a19` | docs: upgrade log v2026.6.19→v2026.7.7.2 |
| `c2833eca8e` | `90e3912286` | chore: bump HERMES_IMAGE tag to v2026.7.20 |
| `6ebd719d36` | `31a7804f9b` | docs: upgrade log v2026.7.7.2→v2026.7.20 |
| `046db64138` | `3eeaabc0c2` | docs: upgrade log v2026.7.20→v2026.7.30 |
| `00bbd1878c` | `172203f336` | docs: add wordpress article |

### Consolidated Docker Commit (1 new commit replacing 6 originals)

| New Hash | Replaces | Description |
|----------|----------|-------------|
| `5fbbe38051` | `bc325133ac` + `adb7f5713e` + `f255af53c3` + `5152c99a5e` + `75e0c5f5fc` + `fc9de73ed7` | feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture |

### Version Bump (1 new commit)

| New Hash | Description |
|----------|-------------|
| `579f81d5d4` | chore: bump HERMES_IMAGE tag to v2026.8.3 |

## Dropped Commits (4 — functionality superseded by official)

| Original Hash | Description | Reason |
|--------------|-------------|--------|
| `f255af53c3` | fix: handle non-PID 1 environment (Zeabur) | Official `entrypoint-dispatch.sh` natively handles non-PID 1 |
| `5152c99a5e` | fix: use su-exec instead of main-wrapper.sh for Zeabur | Official `main-wrapper.sh` with-contenv re-exec handles this |
| `75e0c5f5fc` | fix: use su instead of su-exec for Zeabur | Same as above |
| `adb7f5713e` | feat: add entrypoint-ssh.sh for Zeabur compatibility | SSH setup in stage2-hook.sh; dispatch handled by official entrypoint |

## Conflicts Encountered

**Zero cherry-pick conflicts.** All docs commits applied cleanly.

The Docker customization was handled by creating a fresh consolidated commit
against the v2026.8.3 base rather than cherry-picking the original 6 commits,
which would have produced conflicts in Dockerfile (apt-get line, ENTRYPOINT
change, Node 22→26 upgrade) and docker/stage2-hook.sh (chown logic refactor
with `tree_has_non_hermes_owner()`).

## Key Official Changes in This Release

### Docker Architecture
- **entrypoint-dispatch.sh**: New PID 1 dispatcher (replaces direct `/init` ENTRYPOINT)
- **main-wrapper.sh**: Shebang changed from `#!/command/with-contenv sh` to `#!/bin/sh` with dynamic `with-contenv` re-exec
- **stage2-hook.sh**: New `tree_has_non_hermes_owner()` function for warm-boot chown optimization
- **Node 22 → 26**: corepack dropped (unbundled upstream)
- **libatomic1**: New system dependency added

### Core Engine
- MCP tool-schema on-disk cache + lazy server startup
- Reset-aware primary restore for rate-limited providers
- SQLite batched turn flush (one transaction per turn)
- Cold-start ~14s GIL stall mitigation
- Terminal recoverable truncation
- write_file on-disk verification

### Platforms
- A2A (Agent-to-Agent) platform plugin (new)
- SimplEX platform support (new)
- Discord tool-progress routing fix
- Matrix platform improvements

## Verification

```
✅ Custom commits count: 15
✅ Dockerfile contains openssh-server
✅ Dockerfile contains libatomic1
✅ Dockerfile contains NODE_OPTIONS
✅ Dockerfile does NOT contain corepack (Node 26)
✅ ENTRYPOINT uses entrypoint-dispatch.sh
✅ Node version: 26
✅ stage2-hook.sh contains SSH setup
✅ stage2-hook.sh contains HERMES_TUI_DIR
✅ stage2-hook.sh contains faster-whisper PYTHONPATH
✅ entrypoint-dispatch.sh unmodified from official
✅ .env version: v2026.8.3
```
