# Hermes Agent 升級工作表：v0.22.6 → v0.22.7

- **目標版本**：`v0.22.7`（官方 commit `b200f5bc60e31588ba2cb60e288029c4a54ba5fa`，2026-11-03 發佈）
- **升級前版本**：`my-config-v0.22.6`（HEAD `7f32837c65`，基於官方 `v0.22.6` = `f0d94882e89`）
- **新分支**：`my-config-v0.22.7`
- **Remote**：`origin` = 官方（NousResearch）、`kuniakil` = 個人 fork（⚠️ 與 OpenClaw 相反）
- **發布模型**：`my-config-v0.22.7` 分支為 source of truth，由 `ghcr-publish.yml`（dispatch input **`tag_name`**）建置 `ghcr.io/kuniakil/hermes-agent:v0.22.7`
- **目前上線版本**：`v0.22.6`（K3s n100，pod `hermes-agent-5f74db767c-x4d7c`，running，RESTARTS 0）
- **狀態**：⏸️ **規劃完成，等待使用者 Go-Sign**
- **日期**：2026-11-04

---

## 0. ⚠️ 最高優先結論：174 PR 常規收斂窗口、DB 與 Config Schema 雙零變更（完全可逆）、自訂層 100% 零實質衝突

### 0.1 官方 Release Notes 摘要（v0.22.7，2026-11-03）

> Patch release. This tag rolls up the **~174 PRs merged since v0.22.6** into a stable release for the GitHub release (CLI and installers), the Microsoft Store app, Docker and Hermes Cloud. **Full curated notes for this window ship with v0.23.0.**

官方量測（commit `b200f5bc60e`）：

| 指標 | 值 |
|---|---|
| non-merge commits | **581** |
| changed files | **554** |
| 行數 | **+24,012 / −3,144** |
| merged PRs | **174** |
| closed issues | **29** |

> ℹ️ **官方維持把完整 curated notes 延到 v0.23.0**。相較於前一次 `v0.22.5 → v0.22.6` 的 776 PR（4,316 檔），本次是 **174 PR（554 檔）的輕量常規收斂版**。我們已從 git diff 與線上環境完成完整靜態與基線稽核（見 §1 / §2）。

官方「on purpose 列舉」的本窗口重點功能：

- **Desktop Group Chats 強化**：opt-in lead routing（聊天室標頭 Lead 徽章，`gateway/hosted_room_lead.py`）、排程 cron job 投遞至 Group Chats（`cron/scheduler_delivery_room.py`）、聊天室用途與共享筆記、單欄整合顯示成員即時狀態
- **Kanban 快速切換分頁**：釘選的 Kanban 看板可作為 quick-switch tabs
- **`$$TeX$$` 與 Mermaid 圖表渲染切換至 `pele`**：以 `pele 1.13.0` 取代 `mermaid 11.17.2`（`package.json` / `apps/desktop/package.json`）
- **Desktop 更新錯誤面板**：顯示失敗更新的輸出與回報連結
- **Web Access 啟動狀態**：顯示 Start 當前所在的步驟名稱與計時器
- **Telegram on Team Gateway**：透過連結帳號至共享 Bot 完成設定（`gateway/relay/link.py`）
- **Slack `thread_followup_silence`**：opt-in 靜音未點名的討論串回覆
- **Catalog ChatGPT 訂閱模型 Daybreak 開關**（`agent/codex_service_tiers.py`）
- **新增一批 `plugin-catalog` 條目**

### 0.2 核心 runtime vs 外圍變動量拆解

| 比較基準 | 檔案數 | +/− | 意義 |
|---|---|---|---|
| `v0.22.5 → v0.22.6`（上次） | 4,316 | +248,579 / −94,077 | 776 PR 大型收斂窗口 |
| **`v0.22.6 → v0.22.7`（本次）** | **554** | **+24,012 / −3,144** | **174 PR 輕量常規窗口** |
| 其中核心 runtime（`gateway/ agent/ tools/ hermes_cli/ plugins/ cron/ pm/`） | **98** | **+3,992 / −903** | 其餘 ~456 檔為 `apps/desktop/`、`website/`、`plugin-catalog/`、`tests/` |

### 0.3 ✅ DB Schema 與 Config Schema 雙雙完全未變（**100% 無損可逆**）

| 項目 | v0.22.6 | v0.22.7 | 判定 |
|---|---|---|---|
| `hermes_state_common.py: SCHEMA_VERSION` | **32** | **32** | ✅ **未變（DB 完全相容、可逆）** |
| `hermes_state_common.py: FTS_STORAGE_VERSION` | **3** | **3** | ✅ 未變 |
| `hermes_state*.py` 變更 | — | **0 檔變更（完全零 diff）** | ✅ 無任何 SQLite 表結構、索引或觸發器變動 |
| config migration 階梯最高 | **52** | **52** | ✅ **未變（`config_migrations*.py` 與 `left_core_migration.py` 零 diff）** |
| Python `requires-python` | `>=3.11,<3.15` | `>=3.11,<3.15` | ✅ 未變（容器內 `3.14.9+20261021`） |

> 🟢 **可逆性結論：`SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3`、`_config_version = 52` 三者全部零變化！且 `hermes_state*.py` 與 `config_migrations*.py` 完全無修改。若部署後有任何異常，可直接秒級退回 `v0.22.6` image，無任何單向鎖定。依硬性規則，停機前仍執行完整備份（Phase 0）。**

### 0.4 🟢 本次升級的關鍵技術變更與風險評估

| # | 變更 | 對我們的影響 | 處置與驗證方式 |
|---|---|---|---|
| **R1** | **🟢 `Dockerfile`、`docker/stage2-hook.sh`、`docker/entrypoint-dispatch.sh` 在上游零變更** | 我們在 `v0.22.6` 整理好的 7 個 Dockerfile 自訂 hunk 與 `stage2-hook.sh` 自訂區塊，透過 `git merge-tree` 實測 **100% 自動乾淨合併、零代碼衝突**！ | 直接 `git cherry-pick` 攜帶全部自訂 commits，無需手動解衝。 |
| **R2** | **🟢 `nemo-relay` 由 `0.10.3` 升至 `0.11.0`**（`pyproject.toml` + `uv.lock`） | 官方 first-party lifecycle 與 shared-metrics 原生模組例行升版（配合 Team Gateway / Relay link 新功能）。其餘 Python / Node / Chromium / Debian Trixie 基底映像完全未變。 | D3 冒煙測試確認 Python 環境與 Gateway 啟動無異常。 |
| **R3** | **🟢 `tools/mcp_tool_*.py` 強化（#18594）** | `mcp_tool_config.py` 在產生 stdio 子行程時固定傳遞當前 served profile 的 `HERMES_HOME`；`mcp_tool_discovery.py` 改善 parked server 狀態回報；`mcp_tool_agent.py` 保護 prompt prefix 快取不因 `check_fn` 抖動而位移。我們使用的是 HTTP MCP（`mcp_servers.camofox`），完全相容且受益於 prefix 快取穩定性提升。 | D9 驗證 `mcp_servers.camofox` 握手與工具狀態。 |
| **R4** | **🟢 PM（Package Manager）`carried_extras` 與 `workspace` 重構**（`pm/*.py` 17 檔變更） | 改善從舊版 venv 升級時的 optional extras 容錯機制（`pm/carried_extras.py`），不影響容器內 `pm.build_env` 的明確 `--extra` 建置。 | GitHub Actions CI 建置驗證 + D3 冒煙測試驗證 extras。 |

### 0.5 決策點（Go-Sign 時請一併回覆）

| # | 決策 | 建議 | 理由 |
|---|---|---|---|
| **A** | 目標版本 | **`v0.22.7`** | 官方最新 stable；收斂 174 PR，且與我們自訂層 100% 零衝突 |
| **B** | 自訂層攜帶方式 | **原樣 `cherry-pick` 攜帶 `my-config-v0.22.6` 的全部自訂 commits** | 上游未動 `Dockerfile` 與 `docker/stage2-hook.sh`，`git merge-tree` 驗證零代碼衝突 |
| **C** | **npm 漏洞**是否修 | **維持「不修」** | 3 個追蹤 issue（`#133435` / `#132924` / `#79021`）今日（2026-11-04）複查**仍全為 OPEN**；上游移除 `mermaid` 改用 `pele 1.13.0` 減少了 566 行 lockfile 依賴，且 K3s runtime 暴露面 = 0（見 §6） |
| **D** | FTS layout 漂移是否順手 `optimize-storage` | **不做** | 屬 pre-existing 狀態，維持 opt-in，不與版本升級混做 |
| **E** | 既有備份 `~/backups/hermes-20261103/`（昨日 v0.22.6 升級快照，176MB）處置 | **先建立今日 `~/backups/hermes-20261104/` 新備份；待 v0.22.7 驗證通過後再詢問是否刪除 `20261103`** | 嚴格遵守備份生命週期硬性規則（先建新、驗收後請示刪舊） |

---

## 1. 官方 Release Notes 與機器可讀真相稽核

### 1.1 Breaking Changes / 隱含變更盤點

| 檢查項目 | v0.22.6 → v0.22.7 內容 | 對我們的影響與判定 |
|---|---|---|
| **DB Schema (`hermes_state*.py`)** | **零變更**（`SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3`） | 🟢 **無任何 DB 遷移，100% 可逆** |
| **Config Migration (`config_migrations*.py`)** | **零變更**（最高維持 `_config_version = 52`） | 🟢 **無任何 Config 遷移** |
| **Left-Core Migration (`left_core_migration.py`)** | **零變更** | 🟢 **無新增移出 core 的模組** |
| **Docker 建置與啟動腳本 (`Dockerfile`, `docker/*`)** | **零變更** | 🟢 **我們的 7 個 Dockerfile hunk、`stage2-hook.sh`、`entrypoint-ssh.sh` 100% 無縫沿用** |
| **Gateway Adapter 恢復機制 (`gateway/run_adapters_recovery.py`)** | 將 adapter 斷線重連與 backoff 邏輯自 `run_adapters.py` 拆分為獨立 sibling module `run_adapters_recovery.py`，並加入 `relay` 背景 self-provision retry | 🟢 提升平台連線穩定度，對 Telegram adapter 正向無破壞性 |

### 1.2 機器可讀真相（Dependency / Runtime 稽核）

| 項目 | v0.22.6 | v0.22.7 | 判定 |
|---|---|---|---|
| `pyproject.toml` `requires-python` | `>=3.11,<3.15` | `>=3.11,<3.15` | ✅ 不變 |
| Base image (`Dockerfile` 兩個 `FROM`) | `debian:trixie-20261020@sha256:4c252754...` | **`debian:trixie-20261020@sha256:4c252754...`** | ✅ **完全相同（零變動）** |
| `pm/lock.json` Python / Node / npm / uv / ffmpeg / ripgrep / chromium | Python `3.14.9+20261021`、Node `26.12.1`、npm `12.0.2`、uv `0.13.5`、chromium `1208+145.0.7632.6` | **完全相同（`pm/lock.json` 零 diff）** | ✅ 工具鏈版本零變動 |
| `pyproject.toml` / `uv.lock` Python 套件 | `nemo-relay 0.10.3` | **`nemo-relay 0.11.0`**（唯一變更的 Python 套件！） | ✅ 單一套件小幅升版 |
| `package.json` / `apps/desktop/package.json` | `mermaid 11.17.2` | 移除 `mermaid`，改為 **`pele 1.13.0`** | ✅ 僅影響前端/Desktop 圖表渲染 |
| `scripts/write_install_stamp.py` | 存在 | **存在，零 diff** | ✅ `ghcr-publish.yml` 依賴有效 |
| `AGENTS.md` | 存在 | **零 diff** | ✅ Mac host 保護規則直接帶過去 |

### 1.3 Schema / 不可逆性判定

> **判定：本次升級完全無不可逆變更（`SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3`、`_config_version = 52` 全部未變）。**

---

## 2. Diff 與衝突面稽核（`upstream-v0.22.6 → upstream-v0.22.7`）

### 2.1 `git merge-tree` 實測衝突報告

執行指令：
```bash
git merge-tree --write-tree --merge-base=upstream-v0.22.6 upstream-v0.22.7 my-config-v0.22.6
```

| 類別 | 檔案數 | 明細與處置 |
|---|---|---|
| **Modify/Delete 衝突（`.github/workflows/*`）** | **3 檔** | `desktop-bundle-smoke.yml`、`install-e2e-macos-run.yml`、`pm-bundle.yml` → **依 Purge 規則全數刪除，只留 `ghcr-publish.yml`（零人工解衝成本）** |
| **Content 衝突（程式碼 / Dockerfile / 設定）** | **0 檔** | **完全零衝突！** |
| **自動合併無衝突（Auto-merged cleanly）** | **全部自訂檔** | `Dockerfile`、`docker/stage2-hook.sh`、`docker/entrypoint-ssh.sh`、`docker-compose.yml`、`.env.example`、`AGENTS.md`、以及所有 `UPGRADE_LOG_*.md` 與 `docs/` 檔案 |

### 2.2 線上環境唯讀基線預檢（2026-11-04 07:11 實測）

對目前運行中的 K3s n100 Pod（`hermes-agent-5f74db767c-x4d7c`）進行唯讀檢查：

| 指標 | 2026-11-04 07:11 實測值 | 狀態 |
|---|---|---|
| Pod 狀態 | `1/1 Running`, `RESTARTS 0`, age `22h` | 🟢 健康 |
| `sessions` 總數 | **132** | 🟢 與 v0.22.6 升級後一致 |
| `messages` 總數 | **18,031**（24h 內新增 8 則，最後一則為 `2026-11-03 09:46:06`，目前無進行中對話） | 🟢 閒置可安全升級 |
| `state.db` 大小與完整性 | **176.0 MB**，`PRAGMA integrity_check` = **`ok`** | 🟢 完好 |
| `session_admissions` / `worker_executions` / `worker_receipts` | `9` / `0` / `0` | 🟢 無殘留背景任務 |
| `_config_version` | **52** | 🟢 已在最新 v52 |
| 既有備份盤點（`~/backups/`） | `~/backups/hermes-20261103`（昨日備份，176MB） | 🟢 清楚列管 |

---

## 3. 需攜帶的自定義補丁清單

### 3.1 Dockerfile 自訂層（7 個有效 hunk，原樣無縫移植）

| # | 位置 | 內容 | v0.22.7 處置 |
|---|---|---|---|
| 1 | `runtime_base` apt | 在上游 apt 清單加上 `openssh-server` `rsync` `locales`；建立 `/var/run/sshd` + `ssh-keygen -A`；產生 `C.UTF-8` / `en_US.UTF-8` / `zh_TW.UTF-8` locale 並寫入 `/etc/default/locale`、`/etc/profile`、`.bashrc` | ✅ **原樣保留（零衝突）** |
| 2 | `useradd` | `RUN useradd -u 10000 -m -d /opt/data -s /bin/bash hermes` | ✅ **原樣保留（零衝突）** |
| 3 | `python_deps` `pm.build_env` | 在上游 extras 後方加上 `--extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa` | ✅ **原樣保留（零衝突）** |
| 4 | `runtime` `/tmp/.npm-cache` | `RUN mkdir -p /tmp/.npm-cache && chmod 1777 /tmp/.npm-cache` | ✅ **原樣保留（零衝突）** |
| 5 | `runtime` `/root/.npm` | `RUN mkdir -p /root/.npm /root/.cache && chown -R 10000:10000 /root/.npm /root/.cache` | ✅ **原樣保留（零衝突）** |
| 6 | `runtime` `ENV HOME` | `ENV HOME=/opt/data` | ✅ **原樣保留（零衝突）** |
| 7 | `runtime` entrypoint shim | `COPY --chmod=0755 docker/entrypoint-ssh.sh /opt/hermes/docker/entrypoint-ssh.sh` | ✅ **原樣保留（零衝突）** |

### 3.2 自訂 Commits 攜帶計畫（`upstream-v0.22.6..my-config-v0.22.6`，共 30 個 commits）

在 `my-config-v0.22.7`（基於 `upstream-v0.22.7`）上依序處理：

| 順序 | 原 Commit | 類別 | 說明 | 處置方式 |
|---|---|---|---|---|
| 1 | `f866563e22` | CI Purge | `chore(ci): purge official CI workflows; retain only ghcr-publish.yml` | 🔁 **執行 `find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete` 並從 `my-config-v0.22.6` 檢出 `ghcr-publish.yml`** |
| 2 | `c13e99d786` | Docker | `fix(docker): restore docker/entrypoint-ssh.sh for Zeabur backward compatibility` | ✅ `git cherry-pick`（零衝突） |
| 3 | `c2e1b6b57d` | Docker | `chore: carry forward my-config docker-compose.yml (uses HERMES_IMAGE env, TZ=Asia/Taipei)` | ✅ `git cherry-pick`（零衝突） |
| 4 | `10921bc188` | Docs/Rule | `chore: re-append Mac host resource constraint rule to AGENTS.md (v0.21.6)` | ✅ `git cherry-pick`（零衝突） |
| 5 | `1e6a11cc83` | Docker | `feat(docker): restore custom SSH setup and npm cache handling in stage2-hook.sh` | ✅ `git cherry-pick`（零衝突） |
| 6 | `08e46643b5` | Docker | `feat(docker): re-port custom layer (SSH, locales, extras, perms) onto v0.22.6` | ✅ `git cherry-pick`（零衝突） |
| 7 | `5fa1cbc332` | Env | `chore(env): document HERMES_IMAGE in .env.example (k8s pins newTag, not .env)` | ✅ `git cherry-pick`（零衝突） |
| 8 | `a77f3f6ff1` ~ `7f32837c65`（23 個 commits） | Docs | v0.22.2 / v0.22.4 / v0.22.5 / v0.22.6 升級工作表、UPGRADE_LOG、以及 Camofox MCP 測試報告 | ✅ `git cherry-pick`（全為獨立文檔，零衝突）+ 加上本張 `v0.22.7` 工作表 |

---

## 4. 執行步驟 Checklist（待收到 Go-Sign 後依序執行）

### Phase 0 — 停機前盤點 + 備份（MANDATORY）

- [ ] 0.1 確認無使用中：查 24h 內訊息數與最後一則時間（預檢：`msgs_24h = 8`，最後一則為 `2026-11-03 09:46:06`）
- [ ] 0.2 記錄升級前基線（部署後不得下降）：
  - **2026-11-04 預檢基線**：`sessions = 132`、`messages = 18,031`、`state.db = 176.0MB`、`integrity = ok`
  - `session_admissions = 9`、`worker_executions = 0`、`worker_receipts = 0`
- [ ] 0.3 記錄 FTS 現況（維持 opt-in，本次不動）
- [ ] 0.4 記錄 config 基線：`_config_version: 52`、`terminal.backend: local`、`sessions.auto_prune: false`、`security.allow_lazy_installs: true`、`toolsets: [hermes-cli]`、`mcp_servers.camofox` 存在
- [ ] 0.5 **備份 DB（`.db` + `.db-wal` + `.db-shm`，缺一不可）**：建立於 `~/backups/hermes-20261104/`
- [ ] 0.6 驗證備份完整性：`sqlite3 ~/backups/hermes-20261104/state.db "SELECT COUNT(*) FROM messages; PRAGMA integrity_check;"` → 確認 `18031` + `ok`
- [ ] 0.7 盤點既有備份並記錄：
  - 本機 `~/backups/hermes-20261103/`（v0.22.6 升級快照，176MB）— 暫留，待 Phase E 驗證通過後請示使用者是否清理

### Phase A — 建立分支 + Purge Workflows + 移植自訂 Commits

- [ ] A0. **取得使用者 Go-Sign**（確認 §0.5 決策 A/B/C/D/E）
- [ ] A1. `git fetch origin refs/tags/v0.22.7:refs/tags/upstream-v0.22.7 --no-tags`（✅ 已完成，commit `b200f5bc60e`）
- [ ] A2. `git checkout -b my-config-v0.22.7 upstream-v0.22.7`
- [ ] A3. Purge 官方 workflows，僅保留 `ghcr-publish.yml`：
  ```bash
  find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete
  git checkout my-config-v0.22.6 -- .github/workflows/ghcr-publish.yml
  git add .github/workflows
  git commit -m "chore(ci): purge official CI workflows; retain only ghcr-publish.yml"
  ```
- [ ] A4. Cherry-pick 基礎與 Docker 自訂 commits：`c13e99d786`..`5fa1cbc332`（共 6 個核心自訂 commits）
- [ ] A5. 確認 `git diff upstream-v0.22.7 HEAD -- Dockerfile | grep -c '^@@'` = **7**
- [ ] A6. Cherry-pick `a77f3f6ff1`..`7f32837c65`（23 個歷史文檔 commits）並提交本工作表 `docs/worksheet-upgrade-hermes-v0.22.7-20261104.md`
- [ ] A7. **tracked-but-ignored 遺失偵測**：確認 `git diff upstream-v0.22.6..my-config-v0.22.6 --name-only` 與 `git diff upstream-v0.22.7..my-config-v0.22.7 --name-only` 除新增之 v0.22.7 工作表與上游刪減之 workflow 外完全一致
- [ ] A8. 確認 `git log --oneline upstream-v0.22.7..HEAD` 完全線性（無 merge commit）

### Phase B — 本地輕量驗證（嚴禁跑重型測試或本機 docker build）

- [ ] B1. `git status` 乾淨
- [ ] B2. Dockerfile 7 個自訂標記全數存在
- [ ] B3. `.github/workflows/` 僅有 `ghcr-publish.yml`
- [ ] B4. 驗證關鍵檔案完整性：`docker/entrypoint-ssh.sh`、`docker/stage2-hook.sh`、`docker/profile-hermes-path.sh`、`docker-compose.yml`、`AGENTS.md`、`ghcr-publish.yml`
- [ ] B5. 確認 `ghcr-publish.yml` dispatch input 為 **`tag_name`**
- [ ] B6. 確認 `hermes_state_common.py` 的 `SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3`
- [ ] B7. 確認 `hermes_cli/config_migrations.py` 最高版本為 **52**
- [ ] B8. 確認 `.env` 仍在 working tree 且未被 git track

### Phase C — 推送 Fork + 觸發 GHCR Build

- [ ] C1. 推送分支至個人 fork：`git push -u kuniakil my-config-v0.22.7`
- [ ] C2. 手動觸發 workflow：`gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v0.22.7 -f tag_name=v0.22.7 -f platforms=all`
  - ⚠️ 若遇 `HTTP 422 "Actions has been disabled for this repository"`，立即停止並請使用者至 `https://github.com/kuniakil/hermes-agent/actions` 點擊橫幅重新啟用（Hard Rule 8）
- [ ] C3. 驗證觸發的 run：`event=workflow_dispatch`、`headBranch=my-config-v0.22.7`、`headSha=<our_head_sha>`
- [ ] C4. **派背景子代理監控 `gh run watch <run_id> --repo kuniakil/hermes-agent`**（遵守 Hard Rule 9 / `delegate-long-tasks`）
- [ ] C5. 驗證 multi-arch image tags 產出：`ghcr.io/kuniakil/hermes-agent:v0.22.7` 與 `latest`（雙架構 manifest OK）

### Phase D — K3s 部署 + 全方位驗證

- [ ] D1. 更新 `~/kubernetes/hermes/overlays/n100/kustomization.yaml`：`newTag: "v0.22.7"`
- [ ] D2. 執行 `kubectl apply -k ~/kubernetes/hermes/overlays/n100`，監控 rollout 成功
- [ ] D3. 冒煙測試（對照 v0.22.6 基線）：
  - Python `3.14.9` + `openai 2.54.0` + `pydantic 2.14.1` + `nemo-relay 0.11.0`
  - Node.js `v26.12.1` + npm `12.0.2`
  - Debian base = `trixie`
  - 3 種 locale（`C.utf8` / `en_US.utf8` / `zh_TW.utf8`）全在
  - `sshd` + `rsync` + `tini` + `tmux` + `ffmpeg` 全在
  - Chromium binary 存在且可執行（`Google Chrome for Testing 145.0.7632.6`）
  - Telegram connected、**0 ERROR**
- [ ] D4. **版本確認**：`hermes --version` 顯示 `Hermes Agent vv0.22.7 · upstream <our_short_sha>`
- [ ] D5. **DB Schema 檢查**：`SCHEMA_VERSION = 32` 未變；`PRAGMA integrity_check` = `ok`
- [ ] D6. **資料完整性**：`sessions >= 132`、`messages >= 18,031`（零損失）
- [ ] D7. **Config 驗證**：`/opt/data/config.yaml` 的 `_config_version` 維持 **52**；`mcp_servers.camofox` 原封不動
- [ ] D8. **開機與穩定性驗證**：gateway 開機 log 無異常；`RESTARTS = 0`
- [ ] D9. **Camofox MCP 驗證**：`mcp_servers.camofox` 端口 8080 正常通訊
- [ ] D10. 真實 Telegram 訊息往返驗證

### Phase E — 收尾與文件歸檔

- [ ] E1. 更新本工作表所有 checkbox 與實測數據
- [ ] E2. Commit 並推送 `~/kubernetes/hermes/overlays/n100/kustomization.yaml`
- [ ] E3. 產出 `UPGRADE_LOG_v0.22.6_to_v0.22.7.md`，並向使用者彙整驗證證據、請示是否刪除舊備份 `~/backups/hermes-20261103/`（保留 `hermes-20261104/`）

---

## 5. 風險總結表

| 風險項目 | 等級 | 緩解與驗證措施 |
|---|---|---|
| **Dockerfile / 自訂層合併衝突**（R1） | 🟢 **零風險** | 上游在 `v0.22.6..v0.22.7` 未動 `Dockerfile` 與 `docker/*`；`git merge-tree` 已證實 100% 零衝突 |
| **`nemo-relay 0.10.3 → 0.11.0` 升版**（R2） | 🟢 低 | 唯一變更的 Python 套件；D3 冒煙測試驗證載入與 Gateway 運作 |
| **MCP 工具發現與 prefix 保護變更**（R3） | 🟢 低 | 僅針對 stdio 補齊 `HERMES_HOME` 並強化 prefix 穩定度；D9 驗證 `mcp_servers.camofox` |
| **DB Schema / Config Schema 不可逆遷移** | 🟢 **無** | `SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3`、`_config_version = 52` 全部零變化，可秒級無損退回 `v0.22.6` |
| **GitHub Actions Fork 自動停用（HTTP 422）** | 🟡 中（外部啟發式） | 若觸發時回 422，直接請使用者在 `/actions` 點擊 re-enable 橫幅（Hard Rule 8） |
| **npm 漏洞** | 🟢 無（既有決策） | 3 個官方 issue 仍為 OPEN；容器 runtime 暴露面 = 0，維持「不修」 |

---

## 6. npm 漏洞決策複查（2026-11-04）

| 檢查項目 | 2026-11-04 實測結果 |
|---|---|
| ① 觸發條件 Issue 狀態 | `#133435` **OPEN**、`#132924` **OPEN**、`#79021` **OPEN** → 條件未成立，**維持「不修」** |
| ② 上游 `package.json` 變化 | 上游將圖表渲染由 `mermaid 11.17.2` 替換為 `pele 1.13.0`，`package-lock.json` 淨減少 551 行依賴 |
| ③ 實際 K3s runtime 暴露面 | Photon sidecar 未啟用、Electron desktop 不部署 → **暴露面 = 0** |

---

## 7. Go-Sign 確認區

- [ ] §0.5 決策 **A**：目標版本 = **`v0.22.7`**
- [ ] §0.5 決策 **B**：原樣 `cherry-pick` 攜帶 `my-config-v0.22.6` 全部自訂 commits（零衝突）
- [ ] §0.5 決策 **C**：npm 漏洞 = **維持不修**
- [ ] §0.5 決策 **D**：FTS layout = **維持不動**
- [ ] §0.5 決策 **E**：先建 `20261104` 新備份，待驗證完成後再請示清理 `20261103` 舊備份
- [ ] 使用者回覆「**Go**」後啟動 Phase 0 → A → B → C → D → E
