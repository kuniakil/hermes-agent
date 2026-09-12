# Hermes Agent 升級工作表：v2026.9.7 → v2026.9.11

**建立日期**：2026-09-12  
**目標官方 Release**：[`v2026.9.11`](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.9.11) (Hermes Agent v0.21.2)  
**前一版本基準**：`v2026.9.7` (Hermes Agent v0.21.1)  
**預計新建分支**：`my-config-v2026.9.11`  
**備份分支**：`backup/my-config-v2026.9.7`  

---

## 📊 升級差異與風險分析

1. **官方 Release 摘要 (`v2026.9.11` / v0.21.2)**：
   - **核心主軸**：`state.db` 穩定性修復活動 (6 個 PR，關閉 44 個 issues)。解決 v0.21.0/v0.21.1 重構 session store connection handling 後產生的多重寫入者鎖定衝突、POSIX lock 取消、OpenZFS / WSL2 WAL 孤立與 FTS 全文索引毀損問題。
   - **Breaking Changes / 遷移提示**：
     - 無破壞性配置變更。
     - 若過去 `state.db` 有毀損，官方建議先執行 `hermes doctor` 檢查結構損壞或透過 `hermes sessions recover --inspect-only` 進行檢查修復。
     - hosted-room 狀態移至 `shared-state.db`，儀表板改為預設唯讀開啟。
   - **Provider / 模型更新**：
     - DeepSeek V4.1 Flash、GPT Image 2.5、Opus 5 / Fable 5.1。
     - Bedrock Claude/Converse/Mantle 模型持久化修復、Bedrock Guardrails 強制生效。
     - Codex 圖片 patch budget 自動收縮與重試、Azure Foundry 推理拒絕修剪。
   - **CLI / Desktop / TUI**：
     - `hermes -z --resume` Session 延續修復。
     - Desktop UI 語言在更新後得以保留、HUD 模式修復。
     - 更新檢查從每 30 分鐘 git-fetch 改為每日輪詢 GitHub API 一次，避免連線阻塞。
   - **依賴套件 (`pyproject.toml`)**：
     - 版本版號升級至 `0.21.2`。其餘核心依賴維持相同。

2. **關鍵 Docker 檔案衝突評估**：
   - `Dockerfile`：官方無任何變更 (`git diff v2026.9.7..v2026.9.11 -- Dockerfile` 為空)。
   - `docker/stage2-hook.sh`：官方無任何變更。
   - `docker/entrypoint-dispatch.sh`：官方無任何變更。
   - **衝突風險評估**：**極低 (NONE/LOW)**，所有自定義層（SSH、Playwright CLI & Chromium 全域快取隔離、locales/UTF-8、faster-whisper、extras 套件等）預期均可順暢 cherry-pick 套用。

3. **Workflows 差異**：
   - 官方在 `v2026.9.11` 新增了 `plugin-catalog-ci.yml` 並調整了部分 CI 腳本。
   - 依據專案規範與 SOP，新分支建立後會執行 workflow purge，保留我們的 `ghcr-publish.yml`（已配置 `ubuntu-24.04-arm` 原生 runner），避免在 fork 上觸發 upstream 大量 E2E/排程測試。

---

## 📋 升級執行檢核清單 (Checklist)

### Phase 1: 升級前準備與分析 (Pre-Upgrade Analysis)
- [x] 1.1 抓取 upstream 官方最新 tags (`git fetch origin --tags`)
- [x] 1.2 確認官方 tag `v2026.9.11` 存在
- [x] 1.3 比對官方核心變更 (`Dockerfile`, `docker/`, `pyproject.toml`, `.github/workflows/`)
- [x] 1.4 建立升級工作表文件 (`docs/worksheet-upgrade-hermes-v2026.9.11-20260912.md`)
- [x] 1.5 向使用者報告計畫並取得「Go-Sign」明確同意授權

### Phase 2: 執行分支建立與 Cherry-pick (Execution Phase)
- [x] 2.1 建立前版備份分支：`git branch backup/my-config-v2026.9.7`
- [x] 2.2 從官方 Tag 建立新分支：`git checkout -b my-config-v2026.9.11 v2026.9.11`
- [x] 2.3 依序 Cherry-pick 自定義 Commits：
  - [x] `022818679e` chore: add .env with HERMES_IMAGE for docker-compose
  - [x] `12afb76b1a` chore: add ghcr-publish workflow for Docker image build
  - [x] `22e92eea77` chore: restore docker-compose.yml from my-config-v2026.5.16
  - [x] `de6f13a8ab` feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture
  - [x] `bb03e822c0` feat(docker): add rsync, locales, and full UTF-8 support
  - [x] `47451a4381` feat(docker): install full Playwright Chromium with proper permissions
  - [x] `edbd6add2d` docs: add upgrade log v2026.8.3 to v2026.8.13
  - [x] `1e7c27af91` docs: update upgrade log and GEMINI.md with Playwright Chromium addition
  - [x] `cab338141e` ci: add platform choice to workflow defaulting to amd64
  - [x] `8ff902efe9` docs: update workflow trigger example with platforms parameter
  - [x] `a3fd97e655` fix(docker): propagate s6 container_environment to SSH sessions and fix faster-whisper PYTHONPATH
  - [x] `db5c0dab0f` feat(docker): build faster-whisper (voice extra) directly into image (rebased onto v2026.8.19)
  - [x] `c28787588d` docs: add TODO.md for next image build and upgrade checklist
  - [x] `cdc0e024cb` fix(docker): ensure /root/.npm ownership is granted to hermes user (UID 10000)
  - [x] `a96b9ae818` fix(docker): set ENV HOME=/opt/data to prevent non-root processes from accessing /root
  - [x] `d12a6715cb` docs: add dify-search rule to GEMINI.md for dynamic RAG retrieval
  - [x] `cf12e1ee5a` docs: add upgrade log v2026.8.18 to v2026.8.19
  - [x] `442388e0c5` docs(upgrade): record v2026.8.19 deployment verification in worksheet
  - [x] `edcf01f35a` feat(docker): restore dropped extras (edge-tts, firecrawl, dingtalk, feishu, exa) and install playwright
  - [x] `4c4e8c1d95` docs(upgrade): document hotfix acfa77e921 restoring dropped baked extras
  - [x] `d61e06bce3` ci: guard upstream scheduled workflows against running on forks
  - [x] `55a4763bda` chore: add Mac host resource constraint rule to AGENTS.md
  - [x] `ba61104d5d` docs: add upgrade log and worksheet v2026.8.31 to v2026.9.7
  - [x] `b0d500b02c` docs: update worksheet Phase 2 completion status
  - [x] `4f661b6d1b` docs: record GitHub Actions run ID in worksheet
  - [x] `f40f0cf88c` docs: mark all upgrade and deployment tasks complete in worksheet
  - [x] `3e2d86ffab` docs: record verification results and npm cache cleanup in TODO
  - [x] `cce7ba5796` fix(docker): bake playwright CLI globally and isolate npm cache to /tmp
  - [x] `d4246b4c0d` docs: document hotfix resolution and update GEMINI.md
  - [x] `0544fff0c9` chore(ci): upgrade to native arm64 runner (ubuntu-24.04-arm) and purge non-essential workflows
- [x] 2.4 更新 `.env` 中 `HERMES_IMAGE` 標籤為 `v2026.9.11` 並 commit (`c10e662e7d`)
- [x] 2.5 補齊歷史升級文件 (`UPGRADE_LOG_*.md`)、`GEMINI.md` 與 `docs/`
- [x] 2.6 建立本次升級記錄檔 `UPGRADE_LOG_v2026.9.7_to_v2026.9.11.md` 並 commit
- [x] 2.7 輕量驗證（檢查 `git status`, `git diff`, `Dockerfile` 語法，嚴禁在 Mac 本機執行大型測試或本機 docker build）
- [ ] 2.8 推送新分支至 GitHub: `git push kuniakil my-config-v2026.9.11`

### Phase 3: CI/CD 建置與叢集部署 (Deployment Phase)
- [ ] 3.1 透過 GitHub Actions 觸發 `ghcr-publish.yml` 建置 `amd64` (或 `all`) Docker image
- [ ] 3.2 監控 GitHub Actions 建置狀態至完成 (約 5-7 分鐘)
- [ ] 3.3 更新 Kubernetes 叢集 `hermes` 服務配置（kustomization image tag 更新至 `v2026.9.11` 並 push 至 main）
- [ ] 3.4 驗證容器啟動、SSH 連線、模型呼叫與基本工具功能
