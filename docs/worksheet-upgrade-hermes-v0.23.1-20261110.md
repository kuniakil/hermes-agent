# Hermes 升級工作表：v0.23.0 → v0.23.1

- **Fork remote**：`kuniakil`（`kuniakil/hermes-agent`）；**Upstream remote**：`origin`（`NousResearch/hermes-agent`）
- **目前上線**：`v0.23.0`（分支 `my-config-v0.23.0`，HEAD `2572784ccd`）
- **目標**：官方 `v0.23.1`（commit `3b421578588243f920886e6fe79a6faa87ea026e`，2026-11-10 01:42Z 發布，immutable）
- **基線 ref**：`upstream-v0.23.1`（已 fetch；`upstream-v0.23.0` = `2bd378ed1b8d…`）
- **發布模型**：分支建置，不推 tag。`ghcr-publish.yml`（dispatch input **`tag_name`**）→ `ghcr.io/kuniakil/hermes-agent:v0.23.1`
- **狀態**：🚧 **Go-Sign 已取得（Q1 接受 / Q2 不等 v0.24.0 / Q3 OK）→ Phase 0–C 已執行，GHCR build 進行中**
- **日期**：2026-11-10

---

## 0. ⚠️ 最高優先結論

### 0.1 一句話結論

**v0.23.1 名義上是 patch，實際是 2,578 commits / 2,781 檔 / 618 PRs 的大視窗（官方完整 notes 延到 v0.24.0）。與 v0.23.0 不同，這次有「DB schema 32→33」與「config 52→53」兩個單向遷移，備份為 MANDATORY，回退需用備份還原資料。**

### 0.2 不可逆性判定

| 面向 | v0.23.0 | v0.23.1 | 判定 |
|---|---|---|---|
| DB `SCHEMA_VERSION` | 32 | **33** | 🔴 **IRREVERSIBLE** |
| `FTS_STORAGE_VERSION` | 3 | 3 | ✅ 不變 |
| config `_config_version` | 52 | **53**（`agent.clarify_timeout` 3600→90，僅在使用者仍是預設值時改寫） | 🟠 單向，影響小 |
| base image | `debian:trixie-20261020@sha256:4c25275…` | **同一 digest** | ✅ |
| Dockerfile stages | 6 | 6（`frontend_build`/`webapp_build` 改用 **pnpm**） | 🟠 見 §2.3 |

**schema v33 實際做的事（讀 `hermes_state_schema.py` diff）：**
1. 重標 `source='subagent'` 且缺 `_delegate_from` 的 session（`UPDATE sessions … json_set`）— 資料改寫。
2. **移除已淘汰的 `messages_fts_cjk` 索引**（CJK 搜尋改走 trigram 索引）；log 會提示 `~/lib/libfts5_cjk.so` 可刪；`hermes sessions optimize-storage` 可回收空間。我們有中文內容 → **D 階段需驗證中文 session 搜尋**。
3. 新增 `LEGACY_REFUSAL_REPAIR_DONE` 一次性修復（`hermes_state_legacy_refusal.py`）。

> v0.23.0 的程式碼開 v33 DB 的行為**未驗證**（可能拒絕或重建 CJK 索引）。**回退 = 還原升級前備份的 `/opt/data`，不可假設舊版能直接讀新 DB。**

### 0.3 官方 Release Notes（v0.23.1）稽核

- 唯一明列修正：plugin-catalog.json 超過客戶端 2 MiB 上限導致 `hermes plugins install` 退回內建目錄 → 上限調為 16 MiB（#151860）。
- **無 Breaking Changes / Deprecations 章節**：官方明說完整 curated notes 隨 v0.24.0 發布，**本視窗內容「刻意未文件化」**。→ 以下風險全部來自我們自己對 diff 的稽核，不能靠 notes。
- 未文件化但確認存在的變更：TUI/CLI Esc backtrack、`hermes gateway attach`、`hermes clipboard image --json`、新 plugin API（`on_session_open`、`post_curator_run`、`llm.oneshot`…）、Telegram plugin 大改（33 檔 +3775/−1195）。
- 依賴：`pyproject.toml` 新增 `av==18.1.0` pin（修 faster-whisper 1.2.1 與 PyAV 19 的 `metadata_errors` TypeError，#135245）— **對我們的 faster-whisper 自訂層有利**；移除 py3.14 的 `tenacity`；新增 `update-startup-files`、`hermes_agent` package。
- 套件管理：根目錄 **`package-lock.json` 已被 `pnpm-lock.yaml` + `pnpm-workspace.yaml` 取代**。

### 0.4 決策點（Go-Sign 時請回覆）

| # | 決策 | 建議 |
|---|---|---|
| Q1 | 是否接受 DB v33 單向遷移（以備份為回退手段） | ✅ 接受；Phase 0 備份必做且驗證 |
| Q2 | 是否等 v0.24.0（有完整 notes）再升 | 建議**不等**：patch tag 為官方 Docker `stable`，且含 av pin / catalog 修正；風險靠備份控管 |
| Q3 | Telegram plugin 大改 → 是否要求 D 階段使用者實測 Telegram 往返 | ✅ 必須（同 v0.23.0 流程） |

---

## 1. Diff 與衝突面稽核（`upstream-v0.23.0 → upstream-v0.23.1`）

自訂 commits 共 **48 個**（`upstream-v0.23.0..my-config-v0.23.0`，絕大多數是 `docs/` 工作表與升級記錄）。

與上游變動檔案的交集（扣除我們本來就會 purge 的 `.github/workflows/*`）：

| 檔案 | 上游變動 | 處置 |
|---|---|---|
| `Dockerfile` | +56/−… pnpm 化、`setup.py` COPY、TUI 註解改寫 | **以 `upstream-v0.23.1` 為底，重新移植自訂層（見 §2.3）** |
| `AGENTS.md` | 結構調整（`just`、boundary lint、Project Structure 縮減） | 取上游版，**重新 append「Local Resource Constraint (Mac Host Protection)」章節** |
| `.env.example` | 移除 Honcho 區塊 | 取上游版，**重新加入 `HERMES_IMAGE` 註解**（commit `f0f569aedd`） |
| `.github/workflows/*`（~40 檔） | 大量改動，新增 `repo-guards.yml` | **全部 purge，只留我們的 `ghcr-publish.yml`** |

不在交集（可乾淨 cherry-pick）：`docker/entrypoint-ssh.sh`、`docker-compose.yml`、`docs/**`。

### 1.1 自訂 Commit 攜帶計畫

| 類別 | commits | 動作 |
|---|---|---|
| CI purge（`2a529f1e39`） | 1 | 重做（purge + 從 `my-config-v0.23.0` checkout 我們的 `ghcr-publish.yml`） |
| `docker/entrypoint-ssh.sh`（`52a01e46c2`）、`docker-compose.yml`（`ea9b93a6d2`） | 2 | cherry-pick |
| `AGENTS.md` 規則（`82955d4bed`）、`.env.example`（`f0f569aedd`） | 2 | 手動重做（上游已改動） |
| Dockerfile 自訂層（`da94722ce4`、`8004b8a18b`） | 2 | **手動重新移植**到 v0.23.1 Dockerfile |
| `docs/**` | ~41 | cherry-pick（零衝突） |

### 1.2 Dockerfile 自訂層必須保留（目標 14/14 marker）

`en_US.UTF-8` / `zh_TW.UTF-8` locale、`rsync`、`tini`、`faster-whisper`、`edge-tts`、`ffmpeg`、`openssh-server`、`docker/entrypoint-ssh.sh`、`stage2-hook.sh` SSH/npm cache 處理、權限設定。

---

## 2. 風險重點

### 2.1 風險表

| # | 風險 | 嚴重度 | 緩解 / 驗證 |
|---|---|---|---|
| R1 | DB v33 單向遷移 + 移除 CJK 索引 | 🔴 高 | Phase 0 備份 MANDATORY；D 階段驗中文搜尋；回退=還原備份 |
| R2 | pnpm 取代 npm 的 Dockerfile 變動撞到我們的 npm cache 自訂層 | 🟠 中 | Phase A 以上游 Dockerfile 為底重做；對照 `npm cache`/`stage2-hook.sh` 是否仍適用；CI build 為唯一驗證 |
| R3 | 舊工作表中的 npm audit lockfile 修補**不再適用**（無 package-lock.json） | 🟠 中 | 改查 `pnpm-lock.yaml`；不手改 lockfile，改看 CI build 與 `pnpm audit`（CI 內） |
| R4 | Telegram plugin 大改（我們唯一平台） | 🟠 中 | D 階段 gateway log + 使用者 Telegram 往返實測 |
| R5 | config 52→53（`clarify_timeout`） | 🟢 低 | 確認我們 config 是否顯式設過；預期無影響 |
| R6 | 2,781 檔視窗、官方未文件化 | 🟠 中 | 上線後 24h 觀察（RESTARTS、記憶體、ERROR log） |
| R7 | Actions 422 auto-disable（Hard Rule 8） | 🟢 低 | 若 dispatch 422，去 `/actions` 點 re-enable banner |

### 2.2 本次**不需要**做的事

- 不重建 memory/embedding 類索引（Hermes 無此流程）。
- 不推 `v0.23.1` tag、不建「已知良好」快照 tag。
- 本機不跑 pytest / pnpm / docker build（Mac 資源保護規則）。

### 2.3 Dockerfile 上游 hunk 摘要

- `COPY pyproject.toml setup.py uv.lock ./`（新增 `setup.py`）
- 兩個 build stage 以 `pm ensure("pnpm")` 安裝 pnpm；`COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./`
- `COPY scripts/build/node-deps*.mjs … pnpm-lock.mjs`
- `frontend_build` 末尾 `cp -RL node_modules/typescript /opt/products/typescript`；runtime stage 改 `COPY --from=frontend_build /opt/products/typescript …`
- 移除 `ENV npm_config_install_links=false`
- 純註解：`HERMES_TUI_DIR` 說明改寫

---

## 3. 執行步驟 Checklist（**待 Go-Sign 後才執行**）

### Phase 0 — 停機前盤點 + 備份（MANDATORY）

> **2026-11-10 執行結果**：全部完成。備份位於 `~/backups/hermes-20261110/`（**沿用既有慣例**，非工作表原寫的 `~/kubernetes/hermes/backups/` — 該路徑為空目錄；v0.23.0 的備份同樣在 `~/backups/`）。
> 另：**hermes namespace 無 PVC**，資料走 hostPath `/data/services/hermes/data`（Deployment `volumes[0].hostPath`）。

- [x] 0.1 `kubectl --context n100-cf -n hermes get pod,pvc`，記錄目前 pod / image digest
  - Pod `hermes-agent-f9496b576-wcxg8`，`1/1 Running`，`RESTARTS 0`，AGE 4d2h
  - ReplicaSet `hermes-agent-f9496b576`（1/1）；Deployment `hermes-agent` 139d，observedGeneration 93
  - Image：`ghcr.io/kuniakil/hermes-agent:v0.23.0`，`imagePullPolicy: Always`
  - Service `hermes-agent` ClusterIP `10.43.202.253` 2222/TCP
  - **無 PVC** → 資料卷為 hostPath `/data/services/hermes/data` + `/data/services/hermes/data/ssh_host_keys`
- [x] 0.2 備份 `/opt/data` 至 `~/backups/hermes-20261110`
  - 製備：Pod 內 `PRAGMA wal_checkpoint(TRUNCATE)` → `(0, 0, 0)`（wal 歸 0 B），再以 **tar streaming** 傳回（`kubectl exec -- tar -cf - -C /opt/data state.db state.db-wal state.db-shm config.yaml .env .hermes/config.yaml .hermes/skills`）
  - tar 產物 193,454,080 B；解壓後 `state.db` 184,508,416 B / `state.db-wal` 0 B / `state.db-shm` 32,768 B / `config.yaml` 13,234 B / `.env` 997 B / `.hermes/config.yaml` 6,598 B / `.hermes/skills` 11 MB
  - 合計 185 MB（`~/backups/hermes-20261110`）
  - 驗證：`PRAGMA integrity_check = ok`、`messages = 18,067`、`sessions = 134`、`schema_version = 32`、`_config_version = 52` — **與線上基線完全一致**
- [x] 0.3 記錄 config / DB 現況
  - `config.yaml`：`agent.clarify_timeout: 600`（**非預設 3600** → 52→53 遷移不會改寫）、`model.default: MiniMax-M3`、`model.provider: minimax`（皆顯式設定）
  - DB：`schema_version = 32`、`PRAGMA user_version = 0`（Hermes 用自建 `schema_version` 表，非 SQLite user_version）
  - sessions = 134、messages = 18,067
  - **`messages_fts_cjk` 索引已不存在**（`sqlite_master` 查 `%cjk%` → 空）；僅存 `messages_fts` + `messages_fts_trigram` → v33 的 CJK 索引移除對我們為 no-op，trigram 路徑已是現行路徑
- [x] 0.4 確認舊備份狀態
  - `~/backups/hermes-20261106/`（v0.23.0 升級快照，176 MB）**保留**，待 D 全綠後才刪
  - `~/backups/immich-20261016/`（與本專案無關）
  - `~/kubernetes/hermes/backups/` 為**空目錄**（工作表原指定路徑從未使用過）
- [x] 0.5 Ledger / cron / 背景任務盤點
  - `/opt/data/.hermes/cron/output` 為空（無待執行 cron 產出）
  - `~/backups/hermes-20261110` 已含 `state.db` + `config.yaml` + `.env` + `.hermes/config.yaml` + `.hermes/skills`
  - 升級窗口安排在 build 完成後由使用者確認，期間無排程寫入

### Phase A — 建立分支 + Purge + 移植自訂 Commits

> **2026-11-10 執行結果**：全部完成，**零衝突**。分支 `my-config-v0.23.1` 自 `upstream-v0.23.1` 建立，最終 **49 個自訂 commits，0 個 merge commit（歷史完全線性）**。

- [x] A1 `git checkout -b my-config-v0.23.1 upstream-v0.23.1` — ✅ base = `3b42157858`
- [x] A2 purge workflows — ✅ 刪除 46 個上游 workflow（v0.23.1 新增 `repo-guards.yml` 一併刪），由 `my-config-v0.23.0` checkout 我們的 `ghcr-publish.yml`（154 行）；commit `72d61c1e56`
  - 附帶效果：上游 v0.23.1 **沒有** `ghcr-publish.yml`，故此步為純新增，無衝突
- [x] A3 cherry-pick `docker/entrypoint-ssh.sh`（`52a01e46c2`→`0f367b0953`）、`docker-compose.yml`（`ea9b93a6d2`→`8fb55cef85`）— ✅ 零衝突
  - 上游 v0.23.1 **無** `docker/entrypoint-ssh.sh`（純新增）；`docker-compose.yml` 上游 v0.23.0→v0.23.1 **未變動** → 直接套用
- [x] A4 手動重做 `AGENTS.md` Mac 資源限制章節（commit `31299dd341`）與 `.env.example` `HERMES_IMAGE` 註解（commit `d23343f13a`）
  - `.env.example` 差異：上游 v0.23.1 移除了 Honcho 區塊；我們取上游版後**只加回** 13 行 `HERMES_IMAGE` 註解（標籤更新為 `v0.23.1`），Honcho 區塊**不復原**（依上游）
- [x] A5 手動重新移植 Dockerfile 自訂層 — ✅ 以 `git apply -3` 將 v0.23.0 的自訂 patch 套到 v0.23.1 Dockerfile，**乾淨套用無衝突**（上游 v0.23.1 改動區段：python_deps COPY 加 `setup.py`、frontend/webapp 兩 stage 改 pnpm、TypeScript 改由 `/opt/products/typescript` 拷貝 — 均不與自訂 hunks 重疊）
  - `docker/stage2-hook.sh`（`da94722ce4`→`1ee17b3540`）上游 v0.23.0→v0.23.1 **未變動** → 直接 cherry-pick 成功
  - Dockerfile commit `ab78b29e23`（+33/−3）
- [x] A6 cherry-pick 其餘 `docs/**` commits（含本工作表）— ✅ **41 個 docs commits 全部零衝突**（上游 v0.23.1 **無 `docs/` 目錄**，故無路徑碰撞）；本工作表 commit `9527d9b9b9`
- [x] A7 確認無 `package-lock.json` 殘留需求；**不手動改 lockfile**
  - 確認：分支內**無** `package-lock.json`；上游改用 `pnpm-lock.yaml` + `pnpm-workspace.yaml` + `.npmrc`
  - 我們未手動修改任何 lockfile

### Phase B — 本地輕量驗證（嚴禁重型測試 / 本機 docker build）

- [x] B1 `git status` 乾淨、`git log --oneline upstream-v0.23.1..HEAD` 為線性 — ✅ `git status` 乾淨；49 commits、**0 merges**
- [x] B2 `ls .github/workflows` 只剩 `ghcr-publish.yml` — ✅ 確認僅 1 檔
- [x] B3 自訂層 marker 14/14 — ✅ 全部命中：`openssh-server` / `rsync` / `ssh-keygen -A` / `zh_TW.UTF-8` / `en_US.UTF-8` / `useradd -u 10000` / `--extra edge-tts` / `firecrawl` / `dingtalk` / `feishu` / `exa` / `/tmp/.npm-cache` / `entrypoint-ssh.sh` / `ENV HOME=/opt/data`
  - 另：`docker/stage2-hook.sh` SSH 設定 + npm cache 區塊在位；`docker/entrypoint-ssh.sh` 13 行
- [x] B4 `Dockerfile` 語法目視檢查 — ✅ 6 stages 齊全（`sqlite_build` → `runtime_base` → `python_deps` → `icons` → `frontend_build` → `webapp_build` → `runtime`）；`COPY --from=frontend_build /opt/products/typescript` 與 frontend stage 的 `cp -RL node_modules/typescript /opt/products/typescript` 對應正確；base image digest 未變（`debian:trixie-20261020@sha256:4c252754…`）
- [x] B5 `git diff upstream-v0.23.1 -- Dockerfile` 僅含自訂層差異 — ✅ 確認；完整非-docs/非-workflows 差異僅 16 檔：`.env.example`(+13) / `AGENTS.md`(+6) / `Dockerfile`(+36/−3) / `docker-compose.yml` / `docker/entrypoint-ssh.sh` / `docker/stage2-hook.sh` / 7 個 `UPGRADE_LOG_*.md` / 4 個 `scripts/` 輔助腳本

### Phase C — 推送 Fork + 觸發 GHCR Build

- [x] C1 `git push -u kuniakil my-config-v0.23.1` — ✅ 已推送（new branch），tracking 設定完成
- [x] C2 `grep -A6 workflow_dispatch: .github/workflows/ghcr-publish.yml` 確認 input 為 `tag_name` — ✅ inputs = `tag_name` (default `''`) + `platforms` (choice: all/amd64/arm64, default `all`)；trigger 僅 `workflow_dispatch`（無 push/tags）
- [x] C3 `gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v0.23.1 -f tag_name=v0.23.1 -f platforms=all` — ✅ run **42741971255**（2026-11-10T02:19:36Z），無 422
- [x] C4 驗證 run — ✅ `event=workflow_dispatch`、`headBranch=my-config-v0.23.1`、`headSha=9527d9b9b973220055b1e0b3aab8cfaa997290b6`（**我們的 commit**，非上游 `3b42157858`）；`prepare` job success，`build-and-push (linux/arm64)` + `build-and-push (linux/amd64)` 雙架構並行
- [ ] C5 `docker buildx imagetools inspect ghcr.io/kuniakil/hermes-agent:v0.23.1`（multi-arch index）— ⏳ build 進行中，背景子代理 watch
- [ ] C6 若 422 → 去 `https://github.com/kuniakil/hermes-agent/actions` 點 re-enable banner — N/A（未遇 422）

### Phase D — K3s 部署 + 驗證

- [ ] D1 更新 `~/kubernetes/hermes/overlays/*` kustomize `newTag: v0.23.1`（含 digest 比對）
- [ ] D2 `kubectl apply -k` + `rollout status`（交子代理）
- [ ] D3 Pod Running 1/1、RESTARTS 0、image digest 符合
- [ ] D4 開機 log：DB migration 32→33 成功、**`Removed the retired messages_fts_cjk index` 訊息出現且無 ERROR**、config 52→53 migrate 訊息
- [ ] D5 `hermes doctor` 通過；s6 supervision 正常
- [ ] D6 DB 驗證：`PRAGMA integrity_check`、schema=33、sessions 數量與 Phase 0 一致
- [ ] D7 **中文 session 搜尋驗證**（CJK 索引已淘汰，確認 trigram 路徑可用）
- [ ] D8 config 覆核：模型 / provider 為顯式設定（`MiniMax-M3` / `minimax`）未被改動；`clarify_timeout` 狀況
- [ ] D9 自訂層實測：SSH、locale `zh_TW.UTF-8`、`faster-whisper` 轉錄（驗 `av` pin 生效、無 `metadata_errors` TypeError）、`edge-tts`、`ffmpeg`
- [ ] D10 Telegram plugin：gateway 啟動 log 無 ERROR；**使用者實測 Telegram 往返**
- [ ] D11 `hermes plugins install` 可看到最新 catalog（驗 16 MiB 上限修正）
- [ ] D12 24h 觀察：RESTARTS、記憶體、ERROR 數（on-demand 手動檢查即可）

### Phase E — 收尾

- [ ] E1 刪除 `hermes-20261106` 備份（D 全綠後），保留 `hermes-20261110`
- [ ] E2 撰寫 `docs/UPGRADE_LOG_v0.23.0_to_v0.23.1.md`
- [ ] E3 關閉本工作表所有 checkbox，記錄 image stamp 與分支 HEAD 差異
- [ ] E4 （視需要）以 `doc-and-wp-publish` 發佈至 wp.3pm.lol

### 回退計畫

1. kustomize `newTag` 改回 `v0.23.0`，`kubectl apply -k`。
2. **因 DB 已升 v33，必須先停 Pod，還原 Phase 0 備份的 `/opt/data`**，再起舊 image。
3. 驗證 Pod 1/1、Telegram 往返。

---

## 4. Go-Sign 確認區

- [x] 使用者確認 Q1–Q3 — ✅ 2026-11-10：**Q1 接受**（DB v33 單向遷移，以備份為回退手段）／**Q2 不等 v0.24.0**／**Q3 OK**（D 階段使用者實測 Telegram 往返）
- [x] **Go-Sign 日期 / 時間**：2026-11-10 02:0x UTC（+08:00 上午）
