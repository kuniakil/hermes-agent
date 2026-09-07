# 升級記錄：v2026.8.27 → v2026.8.31

## 官方版本摘要

- **版本 Tag**：`v2026.8.31`
- **官方 Commits**：911 個
- **發布日期**：2026-08-31
- **主要更新**：
  - **Hermes Bots / Hosted Rooms**：全新群組討論與房間協作架構（`gateway/hosted_rooms.py` 等模組）。
  - **WeCom 原生串流**：重構 WeChat Work 訊息串流，支援原生回覆與 dedup 防重機制。
  - **狀態資料庫強化**：支援 `database.journal_mode` 與 `database.synchronous` 平台設定、耐久性屏障與 FTS 損毀自我修復。
  - **任務委派優化**：`delegate_task` 改為純任務介面，單次呼叫 token 消耗降低 36%（1,201 → 773 tokens/call）。
  - **Session-persistent Kernels**：`execute_code` 支援 session 層級 kernel 持久化（`kernel_mode: session`）。
  - **安全修復**：Docker client argv 不再將 secret 以 plain `-e KEY=VAL` 暴露至 `/proc/<pid>/cmdline`。
  - **系統提示詞**：`docker/SOUL.md` 更新為更直接、精準的提示詞風格。

## 套用的 Custom Commits

以下為成功 cherry-pick 至 `my-config-v2026.8.31` 分支的自定義 commits 清單：

| 新 Commit Hash | 原始 Commit Hash | 說明 |
|---|---|---|
| `3a977ec840` | `3041370126` | chore: add .env with HERMES_IMAGE for docker-compose |
| `6ecfe2b87b` | `8aaac50eb3` | chore: add ghcr-publish workflow for Docker image build |
| `0acd633d2b` | `76a9deba15` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| `95983665e2` | `ba5d5e5edb` | feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture |
| `11f2a7462a` | `9d0f3d4d3c` | feat(docker): add rsync, locales, and full UTF-8 support |
| `ab8499f2f1` | `a45026dcc8` | feat(docker): install full Playwright Chromium with proper permissions |
| `ea92c68f2b` | `84289660e7` | docs: add upgrade log v2026.8.3 to v2026.8.13 |
| `8b0427f9b6` | `c262e94a28` | docs: update upgrade log and GEMINI.md with Playwright Chromium addition |
| `9a4332c0cf` | `15fce8784d` | ci: add platform choice to workflow defaulting to amd64 |
| `2ae78b7961` | `537f0a5a2f` | docs: update workflow trigger example with platforms parameter |
| `b3da1b22e9` | `d0b5b9634e` | fix(docker): propagate s6 container_environment to SSH sessions and fix faster-whisper PYTHONPATH |
| `952a791006` | `22d3589924` | feat(docker): build faster-whisper (voice extra) directly into image (rebased onto v2026.8.19) |
| `e4e7d31b4e` | `51192a3320` | docs: add TODO.md for next image build and upgrade checklist |
| `442e02a56f` | `2b8461c40f` | fix(docker): ensure /root/.npm ownership is granted to hermes user (UID 10000) |
| `b01eccadfa` | `762fa639d3` | fix(docker): set ENV HOME=/opt/data to prevent non-root processes from accessing /root |
| `81cfca57fc` | `bf6ab4521e` | docs: add dify-search rule to GEMINI.md for dynamic RAG retrieval |
| `a7767af768` | `a6807f4c2d` | docs: add upgrade log v2026.8.18 to v2026.8.19 |
| `6d98e1a709` | `6a0cafb248` | docs(upgrade): record v2026.8.19 deployment verification in worksheet |
| `65c30f92d0` | `746ca7dc2a` | feat(docker): restore dropped extras (edge-tts, firecrawl, dingtalk, feishu, exa) and install playwright |
| `2e32766f36` | `1f8411b2a1` | docs(upgrade): document hotfix acfa77e921 restoring dropped baked extras |
| `59ec5041b1` | `253b7c0cd2` | ci: guard upstream scheduled workflows against running on forks |
| `32f4ac9497` | `600736243b` | chore: bump HERMES_IMAGE tag to v2026.8.31 |

## 衝突與解決方式

- **衝突數量**：0（所有 commits 皆乾淨無衝突套用）。
- **關鍵檔案對齊確認**：
  - `Dockerfile`：官方無變更，完整保留 SSH、Playwright Chromium、rsync、locales、faster-whisper 與 extras。
  - `docker/stage2-hook.sh`：官方無變更，完整保留 SSH 啟動、s6 env 傳播及 faster-whisper PYTHONPATH 設定。
  - `docker/entrypoint-dispatch.sh` / `docker/entrypoint-ssh.sh`：保持乾淨架構。

## 後續驗證項目

- [ ] GitHub Actions `ghcr-publish.yml` 多平台映像檔建置成功
- [ ] Kubernetes 叢集映像檔更新並確認 Pod 正常啟動
- [ ] 基本對話、工具呼叫、SSH 與語音/Playwright 功能驗證
