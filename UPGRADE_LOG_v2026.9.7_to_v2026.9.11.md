# 升級記錄：v2026.9.7 → v2026.9.11

## 官方版本摘要

- **版本 Tag**：`v2026.9.11` (Hermes Agent v0.21.2)
- **官方 Commits**：947 個 non-merge commits（異動 1,869 個檔案，312 個 PR，140 位貢獻者）
- **發布日期**：2026-09-11
- **主要更新**：
  - **state.db 穩定性修復活動 (The state.db Reliability Campaign)**：
    - 解決 v0.21.0/v0.21.1 改寫連線處理後引發的資料庫鎖定問題（44 個 issues 關閉）。
    - 移除第二寫入者：hosted-room 狀態移往 `shared-state.db`，儀表板改為預設唯讀開啟，cron lifecycle guard 走 tracked connection registry。
    - 解決 OpenZFS / WSL2 上 WAL generation error 與 transient disk I/O 錯誤重試機制。
    - FTS 全文索引損毀時隔離降級，對話不再 fail-closed，避免誤將 index 損毀判定為整檔損壞。
    - 加入 `coerce_epoch()` 與 JSON 格式防護，防止單一損毀資料列卡死 `sessions list`、導出或 insights。
  - **Provider / 模型更新**：
    - DeepSeek V4.1 Flash、GPT Image 2.5、Opus 5 / Fable 5.1 等新模型支援。
    - Bedrock Claude/Converse/Mantle 模型持久化修復、Bedrock Guardrails 生效。
    - Codex 圖片 patch budget 自動收縮與重試、Azure Foundry 推理拒絕修剪。
  - **CLI / Desktop / TUI**：
    - `hermes -z --resume` 延續工作階段修復。
    - Desktop UI 語言在更新重啟後維持原設定。
    - 更新檢查改為每日輪詢 GitHub API 一次，不再每 30 分鐘執行 git-fetch。
  - **依賴套件**：`pyproject.toml` 版號更新至 `0.21.2`。

## 套用的 Custom Commits

以下為套用至 `my-config-v2026.9.11` 分支的自定義 commits 清單：

| 新 Commit Hash | 原始 Commit Hash | 說明 |
|---|---|---|
| `022818679e` | `c133496f29` | chore: add .env with HERMES_IMAGE for docker-compose |
| `12afb76b1a` | `52b627144b` | chore: add ghcr-publish workflow for Docker image build |
| `22e92eea77` | `02f5c0facf` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| `de6f13a8ab` | `b181dbba3d` | feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture |
| `bb03e822c0` | `a8f877cee1` | feat(docker): add rsync, locales, and full UTF-8 support |
| `47451a4381` | `cded774a85` | feat(docker): install full Playwright Chromium with proper permissions |
| `edbd6add2d` | `c30c2d4ce6` | docs: add upgrade log v2026.8.3 to v2026.8.13 |
| `1e7c27af91` | `8568704275` | docs: update upgrade log and GEMINI.md with Playwright Chromium addition |
| `cab338141e` | `f68f34cf35` | ci: add platform choice to workflow defaulting to amd64 |
| `8ff902efe9` | `5e4c03f5e8` | docs: update workflow trigger example with platforms parameter |
| `a3fd97e655` | `1994846be0` | fix(docker): propagate s6 container_environment to SSH sessions and fix faster-whisper PYTHONPATH |
| `db5c0dab0f` | `71aca11838` | feat(docker): build faster-whisper (voice extra) directly into image (rebased onto v2026.8.19) |
| `c28787588d` | `343028de7c` | docs: add TODO.md for next image build and upgrade checklist |
| `cdc0e024cb` | `f80f275707` | fix(docker): ensure /root/.npm ownership is granted to hermes user (UID 10000) |
| `a96b9ae818` | `d48da78a8b` | fix(docker): set ENV HOME=/opt/data to prevent non-root processes from accessing /root |
| `d12a6715cb` | `c1b9739e25` | docs: add dify-search rule to GEMINI.md for dynamic RAG retrieval |
| `cf12e1ee5a` | `9f3ad43cd5` | docs: add upgrade log v2026.8.18 to v2026.8.19 |
| `442388e0c5` | `e664fedf7c` | docs(upgrade): record v2026.8.19 deployment verification in worksheet |
| `edcf01f35a` | `278e67cf44` | feat(docker): restore dropped extras (edge-tts, firecrawl, dingtalk, feishu, exa) and install playwright |
| `4c4e8c1d95` | `64d5107503` | docs(upgrade): document hotfix acfa77e921 restoring dropped baked extras |
| `d61e06bce3` | `d480722828` | ci: guard upstream scheduled workflows against running on forks |
| `55a4763bda` | `c93016f39e` | chore: add Mac host resource constraint rule to AGENTS.md |
| `ba61104d5d` | `1e45756c9a` | docs: add upgrade log and worksheet v2026.8.31 to v2026.9.7 |
| `b0d500b02c` | `9c27d983a5` | docs: update worksheet Phase 2 completion status |
| `4f661b6d1b` | `0de4ebc951` | docs: record GitHub Actions run ID in worksheet |
| `f40f0cf88c` | `765655eeef` | docs: mark all upgrade and deployment tasks complete in worksheet |
| `3e2d86ffab` | `40ec0bdd74` | docs: record verification results and npm cache cleanup in TODO |
| `cce7ba5796` | `a56d8aab0c` | fix(docker): bake playwright CLI globally and isolate npm cache to /tmp |
| `d4246b4c0d` | `0cc221582a` | docs: document hotfix resolution and update GEMINI.md |
| `0544fff0c9` | `be14a23498` | chore(ci): upgrade to native arm64 runner (ubuntu-24.04-arm) and purge non-essential workflows |
| `c10e662e7d` | `cd9ff61cc4` (updated) | chore: bump HERMES_IMAGE tag to v2026.9.11 |

## 衝突與解決方式

- **衝突檔案**：`.github/workflows/deploy-site.yml`, `install-e2e-run.yml`, `install-e2e.yml`, `lint.yml` (modify/delete conflict)
  - **原因**：官方 upstream 在 `v2026.9.11` 修改了這 4 個 workflow 檔案，而在我們套用 `be14a23498`（Purge 非必要 workflows）時產生衝突。
  - **解決方式**：依照升級 SOP 的「Workflow Purge Protection」規範，fork 倉庫僅保留 `ghcr-publish.yml`，清除所有 upstream CI/E2E 檔案（`find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete`），順利解決衝突並完成 commit。
- **關鍵 Docker 檔案**：
  - `Dockerfile`、`docker/stage2-hook.sh`、`docker/entrypoint-dispatch.sh`、`docker/entrypoint-ssh.sh`：官方與前版無差異，所有自定義層（SSH、Playwright CLI 與 Chromium 全域快取隔離、locales/UTF-8、faster-whisper、extras 套件等）皆 100% 乾淨套用。

## 驗證結果與系統檢查 (Verification)

- [ ] GitHub Actions `ghcr-publish.yml` Docker 映像檔建置
- [ ] Kubernetes 叢集映像檔更新至 `v2026.9.11`
- [ ] Pod 正常啟動與基本功能驗證
