# 升級記錄：v2026.8.31 → v2026.9.7

## 官方版本摘要

- **版本 Tag**：`v2026.9.7` (Hermes Agent v0.21.1)
- **官方 Commits**：5,139 個（異動 4,364 個檔案，632 個 PR）
- **發布日期**：2026-09-07
- **主要更新**：
  - **程式庫模組化重構**：持續推進核心模組拆解 (Codebase modularization)，優化開機啟動速度與檔案操作 I/O 效能。
  - **Desktop Session Controls & Browser Annotations**：強化桌面端工作階段生命週期管理與瀏覽器動作註解。
  - **MCP Authorization & Tooling**：增強 MCP 授權流與遠端/本機工具連線穩定性。
  - **Cron 排程與 Delivery 修復**：針對排程任務執行、積壓遞送 (completion backlog delivery) 與時區處理進行修復。
  - **Delegation 穩定度調優**：持續調優 subagent 任務委派協議與跨任務通訊。
  - **相依套件升級**：`pyproject.toml` 升級版本至 `0.21.1`，核心模組 `nemo-relay>=0.8.3,<0.9`、`brotlicffi==1.2.0.2`；移除靜態 `py-modules` 清單，改由 `setup.py` 動態識別單檔模組。

## 套用的 Custom Commits

以下為套用至 `my-config-v2026.9.7` 分支的自定義 commits 清單：

| 新 Commit Hash | 原始 Commit Hash | 說明 |
|---|---|---|
| `c133496f29` | `3a977ec840` | chore: add .env with HERMES_IMAGE for docker-compose |
| `52b627144b` | `6ecfe2b87b` | chore: add ghcr-publish workflow for Docker image build |
| `02f5c0facf` | `0acd633d2b` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| `b181dbba3d` | `95983665e2` | feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture |
| `a8f877cee1` | `11f2a7462a` | feat(docker): add rsync, locales, and full UTF-8 support |
| `cded774a85` | `ab8499f2f1` | feat(docker): install full Playwright Chromium with proper permissions |
| `c30c2d4ce6` | `ea92c68f2b` | docs: add upgrade log v2026.8.3 to v2026.8.13 |
| `8568704275` | `8b0427f9b6` | docs: update upgrade log and GEMINI.md with Playwright Chromium addition |
| `f68f34cf35` | `9a4332c0cf` | ci: add platform choice to workflow defaulting to amd64 |
| `5e4c03f5e8` | `2ae78b7961` | docs: update workflow trigger example with platforms parameter |
| `1994846be0` | `b3da1b22e9` | fix(docker): propagate s6 container_environment to SSH sessions and fix faster-whisper PYTHONPATH |
| `71aca11838` | `952a791006` | feat(docker): build faster-whisper (voice extra) directly into image (rebased onto v2026.8.19) |
| `343028de7c` | `e4e7d31b4e` | docs: add TODO.md for next image build and upgrade checklist |
| `f80f275707` | `442e02a56f` | fix(docker): ensure /root/.npm ownership is granted to hermes user (UID 10000) |
| `d48da78a8b` | `b01eccadfa` | fix(docker): set ENV HOME=/opt/data to prevent non-root processes from accessing /root |
| `c1b9739e25` | `81cfca57fc` | docs: add dify-search rule to GEMINI.md for dynamic RAG retrieval |
| `9f3ad43cd5` | `a7767af768` | docs: add upgrade log v2026.8.18 to v2026.8.19 |
| `e664fedf7c` | `6d98e1a709` | docs(upgrade): record v2026.8.19 deployment verification in worksheet |
| `278e67cf44` | `65c30f92d0` | feat(docker): restore dropped extras (edge-tts, firecrawl, dingtalk, feishu, exa) and install playwright |
| `64d5107503` | `2e32766f36` | docs(upgrade): document hotfix acfa77e921 restoring dropped baked extras |
| `d480722828` | `59ec5041b1` | ci: guard upstream scheduled workflows against running on forks |
| `c93016f39e` | `1d8ef8ba59` | chore: add Mac host resource constraint rule to AGENTS.md |
| `cd9ff61cc4` | `32f4ac9497` | chore: bump HERMES_IMAGE tag to v2026.9.7 |

## 衝突與解決方式

- **衝突檔案**：`AGENTS.md`
  - **原因**：官方 upstream 在檔案末尾重構為 `Routing Table`，與我們原本附加在末尾的 `Local Resource Constraint (Mac Host Protection)` 發生上下文位置衝突。
  - **解決方式**：遵循兩側保留原則，完整保留官方新增的 `Routing Table` 區塊，並將我們的 Mac 本機資源保護限制（禁止本機跑重型測試/編譯）接續置於章節末尾。
- **關鍵 Docker 與腳本檔案**：
  - `Dockerfile`、`docker/stage2-hook.sh`、`docker/entrypoint-dispatch.sh`、`docker/entrypoint-ssh.sh`：官方無修改，所有自定義層 100% 乾淨套用。
  - `.github/workflows/`：守衛排程與 ghcr-publish 均正常運作。

## 後續驗證項目

- [ ] GitHub Actions `ghcr-publish.yml` 多平台映像檔建置成功 (amd64)
- [ ] Kubernetes 叢集映像檔更新並確認 Pod 正常啟動
- [ ] 基本對話、工具呼叫、SSH 與語音/Playwright 功能驗證
