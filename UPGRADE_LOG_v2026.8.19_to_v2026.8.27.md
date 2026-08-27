# Upgrade Log: v2026.8.19 → v2026.8.27

**Upgrade Date**: 2026-08-27  
**Official Release**: [Hermes Agent v0.20.6 (v2026.8.27)](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.8.27)  

---

## §1 升級前分析（Pre-upgrade Analysis）

| 項目 | 結果 |
|---|---|
| 官方新 Tag | `v2026.8.27`（v0.20.6，release 標籤 2026-08-27） |
| 官方 HEAD commit | `5fc308a707 chore: release v0.20.6 (2026.8.27)` |
| 上游規模 | **~1,376 commits、1558 files changed、+177,117/-21,686**（自 v2026.8.19） |
| 上游 Docker 變更 | **僅 `Dockerfile`（+14/-6）**；`stage2-hook.sh`、`entrypoint-dispatch.sh`、`entrypoint-ssh.sh`、`docker-compose.yml` 皆**零變更** |
| 我們自訂 commit 數 | **24 個**（`HEAD ^v2026.8.19`） |
| 實際套用 commit 數 | **21 個保留 + 1 個 bump tag commit**（跳過 3 個歷史 bump commits） |
| 衝突數 | **0 個手動衝突**（全數自動乾淨合併） |

---

## §2 上游變更摘要（v0.20.6, 2026.8.27）

### §2.1 Docker 架構

**`Dockerfile`（+14/-6）主要變更：**
1. **Fix self-inflicted lockout (`3834e89724`)**：`chmod 0755 /opt/hermes /opt/hermes/bin/hermes`，防止 `secure_parent_dir()` 把 `/opt/hermes` chmod 成 0700 導致非 root 使用者 Permission denied。
2. **Bake authoritative image provenance (`82a702bf67`)**：於 `/etc/hermes/image-provenance.json` 寫入映像檔部署與版本元資料。

### §2.2 重大功能變更

- **Browser**：Extension controller broker、scoped artifact endpoints、schema diet (803→663 tok/call)、Windows locked profile 讀取安全防護。
- **Desktop**：Group-chat rounds 停止按鈕、Managed SSH updates 引擎與 per-connection SSH update、SSH 連線/程序生命週期修復。
- **Cron**：bot-chat delivery target（排程結果直接送至 Bot Chat 並觸發對話回應）、lock-first liveness check、script timeout process tree-kill。
- **Models & Providers**：GLM-5.3-Flash (z.ai/OpenRouter)、Inkling free、Minimax-M3 free、GPT-5.6 family (Bedrock)。
- **Tool Search**：Multi-query search、batched describe、Snowball stemming 支援。
- **Auth & Gateway**：PKCE cookie SameSite=None 支援 HTTPS cross-site 重導向；Gateway empty error string 例外類型保留。

---

## §3 套用 Commits 清單

| # | 原始 Commit | 描述 | 新 Commit Hash (v2026.8.27) | 結果 |
|---|---|---|---|---|
| 1 | `6983379f5c` | chore: add .env with HERMES_IMAGE for docker-compose | `3041370126` | ✅ 自動合併 |
| 2 | `8342af7d43` | chore: add ghcr-publish workflow for Docker image build | `8aaac50eb3` | ✅ 自動合併 |
| 3 | `c50e51b9a8` | chore: restore docker-compose.yml from my-config-v2026.5.16 | `76a9deba15` | ✅ 自動合併 |
| 4 | `4793cb0648` | feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture | `ba5d5e5edb` | ✅ 自動合併 |
| 5 | `de2f378cce` | feat(docker): add rsync, locales, and full UTF-8 support | `9d0f3d4d3c` | ✅ 自動合併 |
| 6 | `9953be9597` | feat(docker): install full Playwright Chromium with proper permissions | `a45026dcc8` | ✅ 自動合併 |
| 7 | `66dfd0dcd3` | docs: add upgrade log v2026.8.3 to v2026.8.13 | `84289660e7` | ✅ 自動合併 |
| 8 | `f9d521e28c` | docs: update upgrade log and GEMINI.md with Playwright Chromium addition | `c262e94a28` | ✅ 自動合併 |
| 9 | `74dc2a7c67` | ci: add platform choice to workflow defaulting to amd64 | `15fce8784d` | ✅ 自動合併 |
| 10 | `fc0d0c52b2` | docs: update workflow trigger example with platforms parameter | `537f0a5a2f` | ✅ 自動合併 |
| 11 | `68472f407b` | fix(docker): propagate s6 container_environment to SSH sessions and fix faster-whisper PYTHONPATH | `d0b5b9634e` | ✅ 自動合併 |
| 12 | `bfcbdcaa60` | feat(docker): build faster-whisper (voice extra) directly into image (rebased onto v2026.8.19) | `22d3589924` | ✅ 自動合併 |
| 13 | `150ec0885e` | docs: add TODO.md for next image build and upgrade checklist | `51192a3320` | ✅ 自動合併 |
| 14 | `a85e19049d` | fix(docker): ensure /root/.npm ownership is granted to hermes user (UID 10000) | `2b8461c40f` | ✅ 自動合併 |
| 15 | `8f662897a9` | fix(docker): set ENV HOME=/opt/data to prevent non-root processes from accessing /root | `762fa639d3` | ✅ 自動合併 |
| 16 | `876c40b855` | docs: add dify-search rule to GEMINI.md for dynamic RAG retrieval | `bf6ab4521e` | ✅ 自動合併 |
| 17 | `ae884353fe` | docs: add upgrade log v2026.8.18 to v2026.8.19 | `a6807f4c2d` | ✅ 自動合併 |
| 18 | `24aedb987f` | docs(upgrade): record v2026.8.19 deployment verification in worksheet | `6a0cafb248` | ✅ 自動合併 |
| 19 | `acfa77e921` | feat(docker): restore dropped extras (edge-tts, firecrawl, dingtalk, feishu, exa) and install playwright | `746ca7dc2a` | ✅ 自動合併 |
| 20 | `869cec18ae` | docs(upgrade): document hotfix acfa77e921 restoring dropped baked extras | `1f8411b2a1` | ✅ 自動合併 |
| 21 | `9b4a8c59fe` | ci: guard upstream scheduled workflows against running on forks | `253b7c0cd2` | ✅ 自動合併 |
| 22 | — | chore: bump HERMES_IMAGE tag to v2026.8.27 | `600736243b` | ✅ 本次新建 |

---

## §4 驗證結果

### §4.1 Dockerfile 結構驗證
- `extra voice`: 1 ✅
- `ENV HOME=/opt/data`: 1 ✅
- `root/.npm`: 4 ✅
- `openssh-server`: 1 ✅
- `rsync`: 1 ✅
- `libatomic1`: 1 ✅
- `NODE_OPTIONS`: 1 ✅
- `chmod 0755 /opt/hermes `: 1 ✅（官方修復）
- `image-provenance.json`: 1 ✅（官方新增）
- `extra wake`: 0 ✅
- `firecrawl-anydoc`: 0 ✅

### §4.2 stage2-hook.sh 結構驗證
- `SSH server setup`: 1 ✅
- `container_environment/*`: 2 ✅
- `HERMES_TUI_DIR`: 4 ✅
- `PYTHONPATH for faster-whisper`: 1 ✅
- `.npm.*.cache.*.config`: 1 ✅

---

## §5 CI/CD 記錄

- **GitHub Actions Run**: [https://github.com/kuniakil/hermes-agent/actions/runs/33083509249](https://github.com/kuniakil/hermes-agent/actions/runs/33083509249)
- **Tag**: `v2026.8.27`
- **Platform**: `amd64`
