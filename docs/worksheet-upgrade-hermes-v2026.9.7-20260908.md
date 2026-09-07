# Hermes Agent 升級工作表：v2026.8.31 → v2026.9.7

**建立日期**：2026-09-08  
**目標官方 Release**：[`v2026.9.7`](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.9.7) (Hermes Agent v0.21.1)  
**前一版本基準**：`v2026.8.31`  
**預計新建分支**：`my-config-v2026.9.7`  
**備份分支**：`backup/my-config-v2026.8.31`  

---

## 📊 升級差異與風險分析

1. **官方 Release 摘要 (`v2026.9.7`)**：
   - Patch release rollup (v0.21.1)，累計 5,139 個 commits、4,364 個檔案異動、632 個 PR。
   - 核心更新涵蓋：程式庫模組化重構 (codebase modularization)、檔案操作與啟動效能調優、Provider/Model 更新、Desktop session controls 與 browser annotations、MCP authorization 強化、Cron 排程與 delivery 修正、Delegation 穩定度提升。
   - `pyproject.toml`：版本升級至 `0.21.1`，核心相依套件升級 `nemo-relay>=0.8.3,<0.9`、`brotlicffi==1.2.0.2`；移除靜態 `py-modules` 清單（改由 `setup.py` 動態識別）。
2. **關鍵 Docker 檔案衝突評估**：
   - `Dockerfile`：官方無任何變更 (`git diff v2026.8.31..v2026.9.7 -- Dockerfile` 為空)。
   - `docker/stage2-hook.sh`：官方無任何變更。
   - `docker/entrypoint-dispatch.sh`：官方無任何變更。
   - **衝突風險評估**：**極低 (LOW)**，所有 Docker 相關自定義層（SSH、Playwright Chromium、locales/UTF-8、faster-whisper、extras 套件）預期皆可乾淨套用。
3. **Workflows 差異**：
   - 官方 upstream 排程防護 commit (`59ec5041b1`) 涉及的 `install-e2e.yml` 與 `osv-scanner.yml` 在官方新版本中未被更動，可順暢 cherry-pick。
   - `ghcr-publish.yml` 為自定義獨立 workflow，無衝突。

---

## 📋 升級執行檢核清單 (Checklist)

### Phase 1: 升級前準備與分析 (Pre-Upgrade Analysis)
- [x] 1.1 抓取 upstream 官方最新 tags (`git fetch origin --tags`)
- [x] 1.2 確認官方 tag `v2026.9.7` 存在
- [x] 1.3 比對官方核心變更 (`Dockerfile`, `docker/`, `pyproject.toml`, `.github/workflows/`)
- [x] 1.4 建立升級工作表文件 (`docs/worksheet-upgrade-hermes-v2026.9.7-20260908.md`)
- [x] 1.5 向使用者報告計畫並取得「Go-Sign」明確同意授權

### Phase 2: 執行分支建立與 Cherry-pick (Execution Phase)
- [x] 2.1 建立前版備份分支：`git branch backup/my-config-v2026.8.31`
- [x] 2.2 從官方 Tag 建立新分支：`git checkout -b my-config-v2026.9.7 v2026.9.7`
- [x] 2.3 依序 Cherry-pick 自定義 Commits：
  - [x] `c133496f29` chore: add .env with HERMES_IMAGE for docker-compose
  - [x] `52b627144b` chore: add ghcr-publish workflow for Docker image build
  - [x] `02f5c0facf` chore: restore docker-compose.yml from my-config-v2026.5.16
  - [x] `b181dbba3d` feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture
  - [x] `a8f877cee1` feat(docker): add rsync, locales, and full UTF-8 support
  - [x] `cded774a85` feat(docker): install full Playwright Chromium with proper permissions
  - [x] `c30c2d4ce6` docs: add upgrade log v2026.8.3 to v2026.8.13
  - [x] `8568704275` docs: update upgrade log and GEMINI.md with Playwright Chromium addition
  - [x] `f68f34cf35` ci: add platform choice to workflow defaulting to amd64
  - [x] `5e4c03f5e8` docs: update workflow trigger example with platforms parameter
  - [x] `1994846be0` fix(docker): propagate s6 container_environment to SSH sessions and fix faster-whisper PYTHONPATH
  - [x] `71aca11838` feat(docker): build faster-whisper (voice extra) directly into image (rebased onto v2026.8.19)
  - [x] `343028de7c` docs: add TODO.md for next image build and upgrade checklist
  - [x] `f80f275707` fix(docker): ensure /root/.npm ownership is granted to hermes user (UID 10000)
  - [x] `d48da78a8b` fix(docker): set ENV HOME=/opt/data to prevent non-root processes from accessing /root
  - [x] `c1b9739e25` docs: add dify-search rule to GEMINI.md for dynamic RAG retrieval
  - [x] `9f3ad43cd5` docs: add upgrade log v2026.8.18 to v2026.8.19
  - [x] `e664fedf7c` docs(upgrade): record v2026.8.19 deployment verification in worksheet
  - [x] `278e67cf44` feat(docker): restore dropped extras (edge-tts, firecrawl, dingtalk, feishu, exa) and install playwright
  - [x] `64d5107503` docs(upgrade): document hotfix acfa77e921 restoring dropped baked extras
  - [x] `d480722828` ci: guard upstream scheduled workflows against running on forks
  - [x] `c93016f39e` chore: add Mac host resource constraint rule to AGENTS.md
- [x] 2.4 更新 `.env` 中 `HERMES_IMAGE` 標籤為 `v2026.9.7` 並 commit (`cd9ff61cc4`)
- [x] 2.5 補齊歷史升級文件 (`UPGRADE_LOG_*.md`) 與 `GEMINI.md`
- [x] 2.6 建立本次升級記錄檔 `UPGRADE_LOG_v2026.8.31_to_v2026.9.7.md` 並 commit
- [x] 2.7 輕量驗證（檢查 `git status`, `git diff`, `Dockerfile` 語法，不做重型本機 build/test）
- [x] 2.8 推送新分支至 GitHub: `git push kuniakil my-config-v2026.9.7`

### Phase 3: CI/CD 建置與叢集部署 (Deployment Phase)
- [ ] 3.1 透過 GitHub Actions 觸發 `ghcr-publish.yml` 建置 `amd64` Docker image
- [ ] 3.2 監控 GitHub Actions 建置狀態至完成 (約 5-7 分鐘)
- [ ] 3.3 更新 Kubernetes 叢集 `hermes` 服務配置（若由 gitops/kustomize 管理或重啟 Pod）
- [ ] 3.4 驗證容器啟動、SSH 連線、模型呼叫與基本工具功能
