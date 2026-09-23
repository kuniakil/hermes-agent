# 升級記錄：v2026.9.14 → v2026.9.21

## 官方版本摘要

- **版本 Tag**：`v2026.9.21` (Hermes Agent v0.21.4)
- **官方 Commits**：5,071 個 non-merge commits（異動 5,169 個檔案，1,812 個 PR，2,116 個 issues）
- **發布日期**：2026-09-21
- **主要更新**：
  - **Host-wide Gateway Singleton Lock**：提供 host-wide gateway 單例鎖與 rendezvous 記錄，Desktop 改為附加至現有 host 後端，避免重疊啟動多個背景行程。
  - **Connector Operation**：後端擁有單一 connector 運作機制，並在 Desktop / TUI / CLI 呈現 setup card。
  - **CLI 結構化輸出**：支援 `--format stream-json` JSONL 輸出。
  - **Skills System Prompt 釘選**：新增 `skills.auto_load`，可將特定 skill 固定注入所有新建 session 的 prompt 中。
  - **MCP 探索連線上限**：可設定 `mcp.discovery_concurrency` 避免高併發卡頓。
  - **其他改善**：Gateway 新增 `decline` 未授權 DM 行為、`session_search` 支援時間邊界與 recall 重試、新增 `hermes sessions set-journal-mode`、影片生成工具目錄加入 LTX 2.5 與 Kling O3、大量 profile/multiplex 隔離修復及 state.db 連線健全度修復。

## 套用的 Custom Commits

以下為套用至 `my-config-v2026.9.21` 分支的自定義 commits 清單：

| 新 Commit Hash | 原始 Commit Hash (9.14 分支) | 說明 |
|---|---|---|
| `8ca9b1d4f7` | `39c3651dc2` | chore: add .env with HERMES_IMAGE for docker-compose |
| `476848b97b` | `4940969734` | chore: add ghcr-publish workflow for Docker image build |
| `488b1095af` | `4bae54c108` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| `6a2606009c` | `da38f364d1` | feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture |
| `53aaf2956e` | `761315d38b` | feat(docker): add rsync, locales, and full UTF-8 support |
| `6177971ddd` | `b1e33beb17` | feat(docker): install full Playwright Chromium with proper permissions |
| `e7a7df913f` | `004cc86bca` | ci: add platform choice to workflow defaulting to amd64 |
| `da7593eaa6` | `0a47022938` | fix(docker): propagate s6 container_environment to SSH sessions and fix faster-whisper PYTHONPATH |
| `3434ff9cdb` | `ef16ec3a4b` | feat(docker): build faster-whisper (voice extra) directly into image (rebased onto v2026.8.19) |
| `c2c387d98e` | `633fced96f` | fix(docker): ensure /root/.npm ownership is granted to hermes user (UID 10000) |
| `859bbee15e` | `c55294c28a` | fix(docker): set ENV HOME=/opt/data to prevent non-root processes from accessing /root |
| `6505927ea5` | `cfd886859c` | feat(docker): restore dropped extras (edge-tts, firecrawl, dingtalk, feishu, exa) and install playwright |
| `b6a0809854` | `759c14bd8b` | chore: add Mac host resource constraint rule to AGENTS.md |
| `0be373bd1a` | `efeb5dcd78` | fix(docker): bake playwright CLI globally and isolate npm cache to /tmp |
| `33dfe55beb` | `a383c3d304` | fix(docker): persist fixed package-lock.json and enforce post-copy npm audit fix |
| `d58cb7c4af` | `eab8c46301` | chore(ci): upgrade to native arm64 runner (ubuntu-24.04-arm) and purge non-essential workflows |
| `3c9d596114` | `2337247513` | ci: default platforms to all for dual-arch build (amd64 + arm64) using native runners |
| `b26a1ce554` | `3a67bb1b7b` | chore: bump HERMES_IMAGE tag to v2026.9.21 |
| `c9666c2fee` | `0b28e683b8` | docs: restore historical upgrade logs from my-config-v2026.9.14 |

## 衝突與解決方式

- **衝突檔案 1**：`package-lock.json`
  - **原因**：官方 upstream 在 `v2026.9.21` 更新了部分 npm 套件依賴，與自定義 commit `a383c3d304` 內的舊版 lockfile 產生行衝突。
  - **解決方式**：保留 upstream `v2026.9.21` 的最新 lockfile（`git checkout --ours package-lock.json`），同時完整保留 Dockerfile 中的 `npm audit fix --workspaces=false` 與 `npm cache clean --force` 命令，順利通過。
- **衝突檔案 2**：`.github/workflows/` (modify/delete conflict)
  - **原因**：官方在 `v2026.9.21` 修改了多個 upstream workflows（如 `ci.yaml`, `skills-index.yml`, `tests.yml` 等），在套用 Workflow Purge Commit 時產生 modify/delete 衝突。
  - **解決方式**：遵循 Workflow Purge Protection 原則，刪除非 `ghcr-publish.yml` 的所有 workflow 檔案，維持純淨矩陣式 CI。
