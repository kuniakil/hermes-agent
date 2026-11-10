# Hermes 升級工作表：v0.23.0 → v0.23.1

- **Fork remote**：`kuniakil`（`kuniakil/hermes-agent`）；**Upstream remote**：`origin`（`NousResearch/hermes-agent`）
- **目前上線**：`v0.23.0`（分支 `my-config-v0.23.0`，HEAD `2572784ccd`）
- **目標**：官方 `v0.23.1`（commit `3b421578588243f920886e6fe79a6faa87ea026e`，2026-11-10 01:42Z 發布，immutable）
- **基線 ref**：`upstream-v0.23.1`（已 fetch；`upstream-v0.23.0` = `2bd378ed1b8d…`）
- **發布模型**：分支建置，不推 tag。`ghcr-publish.yml`（dispatch input **`tag_name`**）→ `ghcr.io/kuniakil/hermes-agent:v0.23.1`
- **狀態**：⏳ **規劃完成，等待 Go-Sign（尚未動任何程式碼 / 分支）**
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

- [ ] 0.1 `kubectl --context n100-cf -n hermes get pod,pvc`，記錄目前 pod / image digest
- [ ] 0.2 備份 PVC `/opt/data`（含 `state.db`、`config.yaml`、`.env`、skills）至 `~/kubernetes/hermes/backups/hermes-20261110`，驗證檔案大小與 `sqlite3 state.db "PRAGMA integrity_check"`
- [ ] 0.3 記錄 config 目前 `_config_version`（預期 52）與 `agent.clarify_timeout`、DB `PRAGMA user_version`/schema meta（預期 32）
- [ ] 0.4 確認舊備份狀態（`hermes-20261106` 保留至本次驗證完成才刪）
- [ ] 0.5 Ledger / cron / 背景任務盤點（避免升級中途寫入）

### Phase A — 建立分支 + Purge + 移植自訂 Commits

- [ ] A1 `git checkout -b my-config-v0.23.1 upstream-v0.23.1`
- [ ] A2 purge workflows：`find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete`；`git checkout my-config-v0.23.0 -- .github/workflows/ghcr-publish.yml`；commit `chore(ci): purge official CI workflows; retain only ghcr-publish.yml`
- [ ] A3 cherry-pick `docker/entrypoint-ssh.sh`（`52a01e46c2`）、`docker-compose.yml`（`ea9b93a6d2`）
- [ ] A4 手動重做 `AGENTS.md` Mac 資源限制章節（`82955d4bed`）與 `.env.example` `HERMES_IMAGE` 註解（`f0f569aedd`）
- [ ] A5 手動重新移植 Dockerfile 自訂層（`da94722ce4`、`8004b8a18b`）到 v0.23.1 Dockerfile（注意 pnpm 變動）
- [ ] A6 cherry-pick 其餘 `docs/**` commits（含本工作表）
- [ ] A7 確認無 `package-lock.json` 殘留需求；**不手動改 lockfile**

### Phase B — 本地輕量驗證（嚴禁重型測試 / 本機 docker build）

- [ ] B1 `git status` 乾淨、`git log --oneline upstream-v0.23.1..HEAD` 為線性
- [ ] B2 `ls .github/workflows` 只剩 `ghcr-publish.yml`
- [ ] B3 自訂層 marker：`git grep` 14/14（locale、rsync、tini、faster-whisper、edge-tts、ffmpeg、openssh-server、entrypoint-ssh…）
- [ ] B4 `Dockerfile` 語法目視檢查（stage 順序、`COPY --from` 路徑與 `/opt/products/typescript` 對應）
- [ ] B5 `git diff upstream-v0.23.1 -- Dockerfile` 僅含自訂層差異

### Phase C — 推送 Fork + 觸發 GHCR Build

- [ ] C1 `git push -u kuniakil my-config-v0.23.1`
- [ ] C2 `grep -A6 workflow_dispatch: .github/workflows/ghcr-publish.yml` 確認 input 為 `tag_name`
- [ ] C3 （使用者確認後）`gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v0.23.1 -f tag_name=v0.23.1 -f platforms=all`
- [ ] C4 驗證 run：`event=workflow_dispatch`、`headBranch=my-config-v0.23.1`、`headSha` 為我們的 commit（**背景子代理 watch，不阻塞主迴圈**）
- [ ] C5 `docker buildx imagetools inspect ghcr.io/kuniakil/hermes-agent:v0.23.1`（multi-arch index）
- [ ] C6 若 422 → 去 `https://github.com/kuniakil/hermes-agent/actions` 點 re-enable banner（不要清 cache、不要改 settings）

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

- [ ] 使用者確認 Q1–Q3
- [ ] **Go-Sign 日期 / 時間**：＿＿＿＿＿＿
