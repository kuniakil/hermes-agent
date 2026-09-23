# Hermes Agent 升級工作表：v2026.9.14 → v2026.9.21

- **目標版本**：`v2026.9.21` (Hermes Agent v0.21.4)
- **當前版本**：`my-config-v2026.9.14` (基於 `v2026.9.14`)
- **工作目標**：對齊官方 release tag `v2026.9.21`，維持線性歷史 (Cherry-pick)，保留所有自定義層（SSH, Playwright Chromium, rsync, locales, faster-whisper 等），套用 Workflow Purge Protection，觸發 GitHub Actions CI/CD (雙架構 amd64 + arm64)，同步升級 Kubernetes 叢集。

---

## 官方 Release (v2026.9.21) 重點摘要與變更分析

### 1. 官方更新亮點 (Release Highlights)
- **架構與連線修復**：
  - Host-wide gateway singleton lock 與 rendezvous record，Desktop 可直接附加至正在運行的 host backend，避免重複生成背景進程。
  - 後端擁有單一 connector operation，並在 Desktop, TUI, CLI 提供 setup card。
  - CLI 新增 `--format stream-json` 結構化 JSONL 輸出。
  - `skills.auto_load` 允許將技能釘選至所有新對話的 system prompt。
  - Gateway 新增 `decline` 未授權 DM 的行為設定。
  - 可配置 MCP 探索連線上限 (`mcp.discovery_concurrency`)。
  - `session_search` 支援 after/before 時間界限與 OR-relaxed recall retry。
  - 新增 `hermes sessions set-journal-mode`。
  - 影片生成工具目錄加入 LTX 2.5 與 Kling O3。
  - 大量 profile / multiplex 隔離、cron、kanban、Desktop 與 state.db 修復。

### 2. 破壞性變更 (Breaking Changes) / 潛在衝突評估
- **`Dockerfile`**：
  - 官方在 `v2026.9.14..v2026.9.21` 之間**完全沒有變更 `Dockerfile`**（`git diff v2026.9.14..v2026.9.21 -- Dockerfile` 為空）。
  - 我們既有的自定義 Dockerfile 可無縫平移。
- **`docker/stage2-hook.sh`**：
  - 官方新增了一段 `sync_routing_overrides`（部署注入 Nous 路由覆蓋至各 profile `.env`，`_ROUTING_MARK='# stage2-managed'`）。
  - 我們在 `stage2-hook.sh` 的自定義改動（SSH 啟動與環境變數注入、faster-whisper PYTHONPATH、開機清理 `$HERMES_HOME/.npm` 並初始化 `/tmp/.npm-cache`）分別位於更前面與末尾，不會有語法或邏輯衝突。
- **`pyproject.toml`**：
  - 官方將版本提升為 `0.21.4`，並調整 `uvicorn[standard]` 改為 `uvicorn` + `httptools` + `watchfiles`，並將 `uvloop` 抽離為 optional extra。
  - 官方 `[all]` extra 包含 `hermes-agent[uvloop]`。我們的 Dockerfile 執行 `uv sync --extra all` 時會自動正確處理。
- **`.github/workflows/`**：
  - 官方更新了測試與 CI workflow。
  - 依據 **Workflow Purge Protection** 原則，我們僅保留自定義的 `ghcr-publish.yml`，其餘官方 workflow 全數清除。

---

## 升級執行檢查清單 (Worksheet Checklist)

### Phase 1: 準備與分支建立 (Pre-Execution & Branch Setup)
- [x] 取得使用者確認 Go-Sign
- [x] 建立備份分支：`git branch backup/my-config-v2026.9.14`
- [x] 從官方 release tag 建立新分支：`git checkout -b my-config-v2026.9.21 v2026.9.21`

### Phase 2: 自定義 Commits Cherry-Pick 與衝突解決 (Cherry-Pick & Patching)
- [x] 套用基礎配置：
  - [x] `8ca9b1d4f7` (原 `39c3651dc2`): chore: add .env with HERMES_IMAGE for docker-compose
  - [x] `476848b97b` (原 `4940969734`): chore: add ghcr-publish workflow for Docker image build
  - [x] `488b1095af` (原 `4bae54c108`): chore: restore docker-compose.yml from my-config-v2026.5.16
- [x] 套用 Docker 核心與工具鏈自定義：
  - [x] `6a2606009c` (原 `da38f364d1`): feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture
  - [x] `53aaf2956e` (原 `761315d38b`): feat(docker): add rsync, locales, and full UTF-8 support
  - [x] `6177971ddd` (原 `b1e33beb17`): feat(docker): install full Playwright Chromium with proper permissions
  - [x] `e7a7df913f` (原 `004cc86bca`): ci: add platform choice to workflow defaulting to amd64
  - [x] `da7593eaa6` (原 `0a47022938`): fix(docker): propagate s6 container_environment to SSH sessions and fix faster-whisper PYTHONPATH
  - [x] `3434ff9cdb` (原 `ef16ec3a4b`): feat(docker): build faster-whisper (voice extra) directly into image
  - [x] `c2c387d98e` (原 `633fced96f`): fix(docker): ensure /root/.npm ownership is granted to hermes user (UID 10000)
  - [x] `859bbee15e` (原 `c55294c28a`): fix(docker): set ENV HOME=/opt/data to prevent non-root processes from accessing /root
  - [x] `6505927ea5` (原 `cfd886859c`): feat(docker): restore dropped extras and install playwright
  - [x] `b6a0809854` (原 `759c14bd8b`): chore: add Mac host resource constraint rule to AGENTS.md
  - [x] `0be373bd1a` (原 `efeb5dcd78`): fix(docker): bake playwright CLI globally and isolate npm cache to /tmp
  - [x] `33dfe55beb` (原 `a383c3d304`): fix(docker): persist fixed package-lock.json and enforce post-copy npm audit fix
- [x] 執行 Workflow Purge Protection：
  - [x] `d58cb7c4af` (原 `eab8c46301`): chore(ci): upgrade to native arm64 runner (ubuntu-24.04-arm) and purge non-essential workflows
  - [x] `3c9d596114` (原 `2337247513`): ci: default platforms to all for dual-arch build (amd64 + arm64) using native runners
- [x] 更新版號與文件：
  - [x] `b26a1ce554` (原 `3a67bb1b7b`): chore: bump HERMES_IMAGE tag to v2026.9.21
  - [x] `c9666c2fee` (原 `0b28e683b8`): docs: restore historical upgrade logs from my-config-v2026.9.14
  - [x] 建立 `UPGRADE_LOG_v2026.9.14_to_v2026.9.21.md` 與工作表更新

### Phase 3: 本地輕量驗證與推送 (Local Verification & Push)
- [x] 驗證工作區狀態乾淨 (`git status`)
- [x] 檢查 Dockerfile 語法與自定義層整合完整性
- [x] 推送新分支到遠端：`git push kuniakil my-config-v2026.9.21`

### Phase 4: GitHub Actions 映像檔建置 (CI/CD Build)
- [x] 觸發 GitHub Actions `ghcr-publish.yml`（Run ID: `35846077567`）：
  ```bash
  gh workflow run ghcr-publish.yml \
    --repo kuniakil/hermes-agent \
    --ref my-config-v2026.9.21 \
    -f tag_name=v2026.9.21 \
    -f platforms=all
  ```
- [ ] 追蹤建置狀態並記錄結果（雙架構原生 runner：amd64 + arm64）

### Phase 5: Kubernetes 叢集部署與驗證 (K8s Deployment & Verification)
- [ ] 更新 Kubernetes `hermes` deployment 映像檔 tag 為 `v2026.9.21`
- [ ] 觀察 Pod rolling update 狀態
- [ ] 進入 Pod 執行 `hermes doctor` 驗證全數通過
- [ ] 驗證 SSH 登入、Playwright Chromium、API 連線及 state.db 運作
- [ ] 標記工作表全部完成並歸檔升級記錄
