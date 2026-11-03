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

- [x] 0.1 確認無使用中：查 24h 內訊息數與最後一則時間（**實測：`msgs_24h = 8`，最後一則為 `2026-11-03 09:46:06`（台北）／`01:46:06 UTC`**，與預檢一致）
- [x] 0.2 記錄升級前基線（部署後不得下降）：
  - **2026-11-04 實測基線**：`sessions = 132`、`messages = 18,031`、`state.db = 184,508,416 B (176.0MB)`、`integrity = ok`
  - `session_admissions = 9`、`worker_executions = 0`、`worker_receipts = 0`
  - Pod：`hermes-agent-5f74db767c-x4d7c`，`Running`，`RESTARTS 0`，`age 22h`，建立於 `2026-11-03T01:04:22Z`
- [x] 0.3 記錄 FTS 現況（維持 opt-in，本次不動）— `FTS_STORAGE_VERSION = 3` 於 v0.22.6 / v0.22.7 皆相同
- [x] 0.4 記錄 config 基線：**實測 `_config_version: 52`**、`terminal.backend: local`、`sessions.auto_prune: false`、`security.allow_lazy_installs: true`、`toolsets: [hermes-cli]`、`mcp_servers.camofox`（`http://camofox-mcp.camofox.svc.cluster.local:8080/mcp`）存在
- [x] 0.5 **備份 DB（`.db` + `.db-wal` + `.db-shm`，缺一不可）**：建立於 `~/backups/hermes-20261104/`
  - 前置：於 Pod 內執行 `PRAGMA wal_checkpoint(TRUNCATE)` → `(0,0,0)`，將 WAL 併入主檔並清空 `-wal`（與 20261103 備份格式一致）
  - 傳輸：`kubectl cp` 傳 176MB 時 websocket 中斷（`close 1006 / unexpected EOF`），改用 **tar streaming**（`kubectl exec -- tar -cf - -C /opt/data …`）成功
  - 產物：`state.db`（184,508,416 B）、`state.db-wal`（0 B）、`state.db-shm`（32,768 B）、`config.yaml`（額外保留）
- [x] 0.6 驗證備份完整性：`sqlite3 ~/backups/hermes-20261104/state.db "SELECT COUNT(*) FROM messages; PRAGMA integrity_check;"` → **實測 `18031` + `132`（sessions）+ `ok`** ✅
- [x] 0.7 盤點既有備份並記錄：
  - 本機 `~/backups/hermes-20261103/`（v0.22.6 升級快照，176MB）— 暫留，待 Phase E 驗證通過後請示使用者是否清理
  - 另見 `~/backups/immich-20261016/`（與本次無關）

### Phase A — 建立分支 + Purge Workflows + 移植自訂 Commits

- [x] A0. **取得使用者 Go-Sign**（確認 §0.5 決策 A/B/C/D/E）— ✅ 2026-11-04 收到「go」，A–E 全部採納建議方案
- [x] A1. `git fetch origin refs/tags/v0.22.7:refs/tags/upstream-v0.22.7 --no-tags`（✅ 已完成，commit `b200f5bc60e31588ba2cb60e288029c4a54ba5fa` — 實測 `git rev-parse upstream-v0.22.7^{commit}` 一致）
- [x] A2. `git checkout -b my-config-v0.22.7 upstream-v0.22.7` — ✅ 分支建立於 `b200f5bc60`
- [x] A3. Purge 官方 workflows，僅保留 `ghcr-publish.yml`：
  ```bash
  find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete
  git checkout my-config-v0.22.6 -- .github/workflows/ghcr-publish.yml
  git add .github/workflows
  git commit -m "chore(ci): purge official CI workflows; retain only ghcr-publish.yml"
  ```
  - 實測：上游 **58 個** workflow → 保留 **1 個**（`ghcr-publish.yml`）。commit `04138723b9`（59 files changed, +154 / −13,567）
  - 📌 **額外移除 `.github/workflows/README.md`**：v0.22.7 新增的 611 行官方 CI 說明文件，內容描述 57 個已被 purge 的 workflow，對本分支已失真 → 隨 purge 一併刪除
- [x] A4. Cherry-pick 基礎與 Docker 自訂 commits：`c13e99d786`..`5fa1cbc332`（6 個核心自訂 commits）— ✅ **全部零衝突**
- [x] A5. 確認 `git diff upstream-v0.22.7 HEAD -- Dockerfile | grep -c '^@@'` = **7** — ✅ 實測 **7**；自訂標記全數存在（`openssh-server` / `rsync` / `useradd -u 10000` / `--extra edge-tts` / `firecrawl` / `dingtalk` / `feishu` / `exa` / `/tmp/.npm-cache` / `ENV HOME=/opt/data` / `entrypoint-ssh.sh`）
- [x] A6. Cherry-pick `a77f3f6ff1`..`7f32837c65`（23 個歷史文檔 commits）並提交本工作表 — ✅ 零衝突；本工作表 commit `caa90cb95e`
- [x] A7. **tracked-but-ignored 遺失偵測**：✅ 實測 `old=89 / new=91` 檔，**LOST = 0 檔**；差異僅為新增的 v0.22.7 工作表與上游新增但隨 purge 移除的 `README.md`
- [x] A8. 確認 `git log --oneline upstream-v0.22.7..HEAD` 完全線性（無 merge commit）— ✅ **merge commits = 0**，自訂 commits 合計 **31**（1 purge + 6 core + 23 docs + 1 worksheet）

### Phase B — 本地輕量驗證（嚴禁跑重型測試或本機 docker build）

- [x] B1. `git status` 乾淨 — ✅ 工作區無未提交變更
- [x] B2. Dockerfile 7 個自訂標記全數存在 — ✅ 見 A5
- [x] B3. `.github/workflows/` 僅有 `ghcr-publish.yml` — ✅
- [x] B4. 驗證關鍵檔案完整性：✅ 全數存在 — `docker/entrypoint-ssh.sh` (13) / `docker/stage2-hook.sh` (874) / `docker/profile-hermes-path.sh` (14) / `docker-compose.yml` (19) / `AGENTS.md` (175) / `.github/workflows/ghcr-publish.yml` (154) / `.env.example` (559)
- [x] B5. 確認 `ghcr-publish.yml` dispatch input 為 **`tag_name`** — ✅ 實測 `tag_name`（description: `Image tag name (e.g. v2026.8.13)`）+ `platforms`（choice: all/amd64/arm64）
- [x] B6. 確認 `hermes_state_common.py` 的 `SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3` — ✅ 實測 `hermes_state_common.py:289` = 32、`:312` = 3
- [x] B7. 確認 `hermes_cli/config_migrations.py` 最高版本為 **52** — ✅ 實測 `MIGRATIONS` 註冊表末項為 `(52, migrate_to_52)`
- [x] B8. 確認 `.env` 仍在 working tree 且未被 git track — ✅ 本機 `.env`（51 B）存在、`git ls-files` 不含 `.env`、`.gitignore:17` 規則命中；Pod 內 `/opt/data/.env`（997 B / 14 行）由 PVC 管理

### B9 — 補充驗證（worksheet §1.2 機器可讀斷言覆核）

- [x] B9.1 `nemo-relay` → ✅ `pyproject.toml` 為 `nemo-relay>=0.11,<0.12`；`uv.lock` 解析為 **`0.11.0`**
- [x] B9.2 Base image → ✅ `Dockerfile` 兩個 `FROM` 皆為 `debian:trixie-20261020@sha256:4c25275446ca371766b8b093c696782eabce06263fccacb8d5d813b3dc44b308`（與 v0.22.6 相同）
- [x] B9.3 `requires-python` → ✅ `>=3.11,<3.15`（未變）
- [x] B9.4 前端圖表渲染 → ✅ `apps/desktop/package.json` 為 `"pele": "1.13.0"`；`package.json` 已無 `mermaid`
- [x] B9.5 **上游零 Docker 變更** → ✅ `git diff upstream-v0.22.6 upstream-v0.22.7 -- Dockerfile docker/` = **0 行**（實錘 R1：自訂層 100% 零衝突）

### Phase C — 推送 Fork + 觸發 GHCR Build

- [x] C1. 推送分支至個人 fork：`git push -u kuniakil my-config-v0.22.7` — ✅ `[new branch] my-config-v0.22.7 -> my-config-v0.22.7`
- [x] C2. 手動觸發 workflow：`gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v0.22.7 -f tag_name=v0.22.7 -f platforms=all`
  - ✅ **無 422**（Hard Rule 8 未觸發）；run URL → `https://github.com/kuniakil/hermes-agent/actions/runs/41738542075`
  - `gh auth status`：`kuniakil`（GH_TOKEN），scopes 含 `workflow` ✅
- [x] C3. 驗證觸發的 run：✅ 實測 `event=workflow_dispatch`、`headBranch=my-config-v0.22.7`、`headSha=caa90cb95e83dd28ac9bb7da87419b8f9e8652e0`（= 本地 HEAD，**非**上游 `b200f5bc60`）、`createdAt=2026-11-03T23:21:47Z`
- [x] C4. **派背景子代理監控 `gh run watch <run_id> --repo kuniakil/hermes-agent`**（遵守 Hard Rule 9 / `delegate-long-tasks`）— ✅ 已派唯讀監控子代理，45 分鐘逾時上限，主迴圈不阻塞
- [x] C5. 驗證 multi-arch image tags 產出：✅ `ghcr.io/kuniakil/hermes-agent:v0.22.7` 與 `latest` 皆為 **multi-arch index**（`application/vnd.oci.image.index.v1+json`）
  - `linux/amd64` → `sha256:be4d40c45528cdef83cd35fa526cbe351edf6358fb24c12818462476e947894a`
  - `linux/arm64` → `sha256:ca2e2d1d8f694d7ab1cba83d3ff11c1f7d814ec61c4c82e4df31c7747051308e`
  - 另有 `unknown/unknown` = buildx 的 attestation/provenance manifest（正常附屬項）
  - Build 耗時 **~10m51s**（`23:21:47Z → 23:32:38Z`）；jobs：prepare / amd64 / arm64 / merge 全部 success
  - **建置日誌實錘 7 個自訂層全部進入 image**：apt + `openssh-server`/`rsync`/`locales` + `ssh-keygen -A` + `C.UTF-8`/`en_US.UTF-8`/`zh_TW.UTF-8` locale-gen、`useradd -u 10000 -m -d /opt/data`、`pm.build_env --extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa`、`install-stamp` 寫入 `caa90cb95e83 (my-config-v0.22.7)`— ⏳ 由監控子代理驗證中

### Phase D — K3s 部署 + 全方位驗證

- [x] D1. 更新 `~/kubernetes/hermes/overlays/n100/kustomization.yaml`：`newTag: "v0.22.6"` → **`"v0.22.7"`** ✅
  - 已 commit + push 至 `~/kubernetes`（Mac 為唯一編輯來源）：commit `d703648`，`9b55908..d703648 main -> main`
- [x] D2. 執行 `kubectl apply -k ~/kubernetes/hermes/overlays/n100`，監控 rollout 成功
  - ✅ apply 結果：`namespace/hermes unchanged`、`secret/secrets-env unchanged`、`service/hermes-agent unchanged`、**`deployment.apps/hermes-agent configured`**、`ingressroutetcp.traefik.io/hermes-ssh-ingress unchanged`
  - ⏳ rollout 由背景子代理監控中
  - ✅ **rollout 成功**：新 pod `hermes-agent-58b98d987d-5nhh7`，`Running` / `ready=true` / `RESTARTS 0`
    - 實際 image：`ghcr.io/kuniakil/hermes-agent:v0.22.7`（digest `sha256:4ae8d02db0670f87fa9fcb3d06214e77c1a394405093f36d1755d27024172309`）
    - Deployment：`updated=1/1 ready=1 avail=1`（conditions: `Available=True` / `Progressing=True`）
    - Image pull 耗時 1m42.9s（image ~1.16GB）；舊 pod `hermes-agent-5f74db767c-x4d7c` 已 Terminating 並移除
    - hostPath PVC `/data/services/hermes/data` 持續掛載於 `/opt/data`（DB 未遺失）
- [x] D3. 冒煙測試（對照 v0.22.6 基線）：**全部通過**
  - Python `3.14.9` ✅、`openai 2.54.0` ✅、`pydantic 2.14.1` ✅、**`nemo_relay 0.11.0` ✅（本次唯一升版的套件）**
  - Node.js `v26.12.1` ✅、npm `12.0.2` ✅
  - Debian base = `13.7 (trixie)` ✅
  - 3 種 locale（`C.utf8` / `en_US.utf8` / `zh_TW.utf8`）全在 ✅
  - `sshd` `/usr/sbin/sshd` ✅、`rsync` ✅、`tini` ✅、`tmux` ✅、`ffmpeg` ✅
  - Chromium binary 存在：`/opt/hermes/tools/chromium-1208/chrome-linux64/chrome` ✅
  - Telegram connected ✅、**0 ERROR / 0 CRITICAL** ✅
- [x] D4. **版本確認**：✅ 實測 **`Hermes Agent vv0.22.7 (2026.9.24) · upstream caa90cb9`**（`upstream` 後綴為我們的 commit `caa90cb95e83`，非上游 `b200f5bc60`）
- [x] D5. **DB Schema 檢查**：✅ `PRAGMA integrity_check` = **`ok`**；`SCHEMA_VERSION = 32` / `FTS_STORAGE_VERSION = 3` 零變更（`hermes_state*.py` 與 `config_migrations*.py` 對上游 diff = **0 行**）
- [x] D6. **資料完整性**：✅ `sessions = 132`（= 基線）、`messages = 18,031`（= 基線）、`session_admissions = 9`、`worker_executions = 0`、`worker_receipts = 0` —— **零損失**
- [x] D7. **Config 驗證**：✅ `/opt/data/config.yaml` 的 `_config_version` 維持 **52**（無遷移）；`terminal.backend: local`、`toolsets: [hermes-cli]`、`security.allow_lazy_installs: true`、`sessions.auto_prune: false` 皆原樣；`mcp_servers.camofox` 原封不動（`url: http://camofox-mcp.camofox.svc.cluster.local:8080/mcp`）
  - `_left_core_used` 未出現於 config（與 v0.22.6 一致；`left_core_migration.py` 對上游零 diff）
- [x] D8. **開機與穩定性驗證**：✅ `RESTARTS = 0`（`startedAt=2026-11-03T23:35:33Z`）
  - Gateway 開機 log（`/opt/data/logs/gateway.log`）自 `07:35:47` 起共 **2,430 行**
  - ✅ `✓ telegram connected`（`Telegram polling confirmed healthy: getUpdates progressing`）、`✓ api_server connected`、`Gateway running with 2 platform(s)`、`Channel directory built: 1 target(s)`
  - ✅ `kanban dispatcher: embedded in gateway`、`Cron scheduler will tick 1 profile(s): ['default']`、`Model context warmed: MiniMax-M3 -> 1000000 tokens`
  - ✅ **ERROR = 0、CRITICAL = 0**；WARNING = 3，皆為 Telegram adapter 的良性訊息（DNS-over-HTTPS fallback 探索 ×1、`Connecting to Telegram (attempt 1/8)` ×1、`Connected to Telegram (polling mode)` ×1）
  - 舊 Pod 關閉為 graceful：`Shutdown phase: all adapters disconnected at +1.94s` → `Previous gateway exited cleanly — skipping session suspension`
- [x] D9. **Camofox MCP 驗證**：✅ `mcp_servers.camofox` 端口 8080 正常通訊
  - DNS 解析正常 → `10.43.250.235`
  - 未帶 token 的 GET → `HTTP 401`（端點存活，正確要求 Authorization）
  - 帶 `Authorization: Bearer …` 的 MCP `initialize` JSON-RPC → **`HTTP 200`**，`serverInfo: {"name":"camofox-mcp","version":"1.16.0"}`，capabilities 含 `tools` + `prompts`
- [ ] D10. 真實 Telegram 訊息往返驗證 — ⏳ **待使用者實測**（與 v0.22.6 升級同樣由使用者於 Telegram 端發訊並回報；升級後目前 `messages` 仍為 18,031，尚無新流量）
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
