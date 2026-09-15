# Hermes Agent 升級工作表：v2026.9.11 → v2026.9.14

- **目標版本**：`v2026.9.14` (Hermes Agent v0.21.3)
- **當前版本**：`my-config-v2026.9.11` (基於 `v2026.9.11`)
- **工作目標**：對齊官方 release tag `v2026.9.14`，維持線性歷史 (Cherry-pick)，保留所有個人自定義層，觸發 GitHub Actions CI/CD (雙架構 amd64 + arm64)，同步升級 Kubernetes 叢集。

---

## 官方 Release (v2026.9.14) 重點摘要與變更分析

### 1. 官方更新亮點
- **Remote Gateway / Desktop / Cloud 登入修復** (#110061, fixes #55712)：
  - Gateway 的 cookie gate 與 desktop 原生 bearer route 針對相同的 refresh token 併發請求進行合併 (coalescing)，避免 wake burst 重送已被 rotated 的 token 觸發 Portal 的 reuse detection 導致整個工作階段被撤銷。
  - Token refresh 改至 event loop 外部執行，避免 slow IdP 卡死 `/api/status`。
- **防止長時間運行程序洩漏重複的 state.db writer handle** (#110934, fixes #100896 #103339)：
  - gateway、dashboard/Desktop backend、ACP 與 CLI readers 預設以唯讀模式掛載。
  - 行程內多個 writers 共享同一個 registry handle，不再觸發 `N live SessionDB handles` 警告。
- **其他更新**：
  - Server→client JSON-RPC 請求與 Pydantic wire-contract registry (#110521, #110522)。
  - Model picker 增加 reasoning-effort 選擇。
  - OpenRouter OAuth PKCE 登入、HEIF/HEIC/AVIF 圖像解碼 (`pillow-heif>=1.4.0,<2`)。
  - MCP OAuth refresh token 綁定發行者。
  - 官方 `Dockerfile` 新增 `--extra google-chat`。

### 2. 破壞性變更 (Breaking Changes) / 潛在衝突評估
- **`Dockerfile`**：
  - 官方僅在 `RUN uv sync ...` 行尾新增 `--extra google-chat`。
  - 我們的自定義 Dockerfile（含 SSH, Chromium, Playwright CLI 全域安裝, npm cache 隔離至 `/tmp`, locales, faster-whisper, extra plugins 等）與官方改動重疊度極低，只需注意合併 `--extra google-chat`。
- **`docker/` 目錄**：
  - 官方在 `docker/` 目錄完全沒有更動（`git diff v2026.9.11..v2026.9.14 -- docker/` 為空）。
  - 我們的 `stage2-hook.sh`、`entrypoint-ssh.sh` 不受任何官方檔案變更衝擊。
- **`.github/workflows/`**：
  - 官方修改了 `skills-index.yml`、`tests-os.yml`、`package-lint.yml`。
  - 依照 **Workflow Purge Protection** 原則，我們只保留 `ghcr-publish.yml`，因此在套用 purge commit 或 cherry-pick 時可能會有 modify/delete 衝突，直接清除官方 workflow 即可。

---

## 升級執行檢查清單 (Worksheet Checklist)

### Phase 1: 準備與分支建立 (Pre-Execution & Branch Setup)
- [x] 取得使用者確認 Go-Sign
- [x] 建立備份分支：`git branch backup/my-config-v2026.9.11`
- [x] 從官方 release tag 建立新分支：`git checkout -b my-config-v2026.9.14 v2026.9.14`

### Phase 2: 自定義 Commits Cherry-Pick 與衝突解決 (Cherry-Pick & Patching)
- [x] 套用基礎配置：
  - [x] `39c3651dc2`: chore: add .env with HERMES_IMAGE for docker-compose
  - [x] `4940969734`: chore: add ghcr-publish workflow for Docker image build
  - [x] `4bae54c108`: chore: restore docker-compose.yml from my-config-v2026.5.16
- [x] 套用 Docker 核心與工具鏈自定義：
  - [x] `da38f364d1`: feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture
  - [x] `761315d38b`: feat(docker): add rsync, locales, and full UTF-8 support
  - [x] `b1e33beb17`: feat(docker): install full Playwright Chromium with proper permissions
  - [x] `004cc86bca`: ci: add platform choice to workflow defaulting to amd64
  - [x] `0a47022938`: fix(docker): propagate s6 container_environment to SSH sessions and fix faster-whisper PYTHONPATH
  - [x] `ef16ec3a4b`: feat(docker): build faster-whisper (voice extra) directly into image
  - [x] `633fced96f`: fix(docker): ensure /root/.npm ownership is granted to hermes user (UID 10000)
  - [x] `c55294c28a`: fix(docker): set ENV HOME=/opt/data to prevent non-root processes from accessing /root
  - [x] `cfd886859c`: feat(docker): restore dropped extras and install playwright (合併官方 `--extra google-chat`)
  - [x] `759c14bd8b`: chore: add Mac host resource constraint rule to AGENTS.md
  - [x] `efeb5dcd78`: fix(docker): bake playwright CLI globally and isolate npm cache to /tmp
  - [x] `a383c3d304`: fix(docker): persist fixed package-lock.json and enforce post-copy npm audit fix
- [x] 執行 Workflow Purge Protection：
  - [x] `eab8c46301`: chore(ci): upgrade to native arm64 runner (ubuntu-24.04-arm) and purge non-essential workflows
  - [x] `2337247513`: ci: default platforms to all for dual-arch build (amd64 + arm64) using native runners
- [x] 更新版號與文件：
  - [x] `3a67bb1b7b`: chore: bump HERMES_IMAGE tag to v2026.9.14
  - [x] `0b28e683b8`: 補回歷史升級文件 (`UPGRADE_LOG_*.md`)
  - [x] `e9971dfcb7`: 建立 `UPGRADE_LOG_v2026.9.11_to_v2026.9.14.md` 與工作表

### Phase 3: 本地輕量驗證與推送 (Local Verification & Push)
- [x] 驗證工作區狀態乾淨 (`git status`)
- [x] 檢查 Dockerfile 語法與自定義層整合完整性
- [x] 推送新分支到遠端：`git push kuniakil my-config-v2026.9.14`

### Phase 4: GitHub Actions 映像檔建置 (CI/CD Build)
- [x] 觸發 GitHub Actions `ghcr-publish.yml`（Run ID: `34913550568`）：
  ```bash
  gh workflow run ghcr-publish.yml \
    --repo kuniakil/hermes-agent \
    --ref my-config-v2026.9.14 \
    -f tag_name=v2026.9.14 \
    -f platforms=all
  ```
- [ ] 追蹤建置狀態並記錄結果（雙架構原生 runner：amd64 + arm64）

### Phase 5: Kubernetes 叢集部署與驗證 (K8s Deployment & Verification)
- [ ] 更新 Kubernetes `hermes` deployment 映像檔 tag 為 `v2026.9.14`
- [ ] 觀察 Pod rolling update 狀態
- [ ] 進入 Pod 執行 `hermes doctor` 驗證全數通過
- [ ] 驗證 SSH 登入、Playwright Chromium、API 連線及 state.db 運作
- [ ] 標記工作表全部完成並歸檔升級記錄
