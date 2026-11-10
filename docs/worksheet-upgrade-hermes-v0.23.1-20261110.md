# Hermes 升級工作表：v0.23.0 → v0.23.1

- **Fork remote**：`kuniakil`（`kuniakil/hermes-agent`）；**Upstream remote**：`origin`（`NousResearch/hermes-agent`）
- **目前上線**：`v0.23.0`（分支 `my-config-v0.23.0`，HEAD `2572784ccd`）
- **目標**：官方 `v0.23.1`（commit `3b421578588243f920886e6fe79a6faa87ea026e`，2026-11-10 01:42Z 發布，immutable）
- **基線 ref**：`upstream-v0.23.1`（已 fetch；`upstream-v0.23.0` = `2bd378ed1b8d…`）
- **發布模型**：分支建置，不推 tag。`ghcr-publish.yml`（dispatch input **`tag_name`**）→ `ghcr.io/kuniakil/hermes-agent:v0.23.1`
- **狀態**：🚧 **Go-Sign 已取得（Q1 接受 / Q2 不等 v0.24.0 / Q3 OK）→ Phase 0–C 已完成（GHCR run 42741971255 success）；Phase D 已部署 v0.23.1，D3–D9 / D11 已驗證通過，待使用者實測 Telegram 往返（D10）與 24h 觀察（D12）**
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
- [x] C5 `docker buildx imagetools inspect ghcr.io/kuniakil/hermes-agent:v0.23.1`（multi-arch index）— ✅
  - **multi-arch index digest：`sha256:6546fcb872d6f6b75031b0d153e8556a906556b9ed6dc8fe108917ed8e56c055`**（media type `application/vnd.oci.image.index.v1+json`，含 amd64 + arm64 + 2 個 attestation manifest）
  - amd64 manifest：`sha256:b57aacbdd575c5ef48db363b0d49472505b93abb839f25370e4e72cf493f1cf9`
  - arm64 manifest：`sha256:c0eb6e361cf415cac16026ea9331367fd92d8673ddb49879a6a5f4999f5d36c5`
  - Tags：`v0.23.1` ✅ OK、`latest` ✅ OK（同一 index）
  - Build run 42741971255 **success**，耗時 10m03s（prepare 3s / amd64 7m54s / arm64 9m36s / merge 11s）
  - 自訂層驗證（image config，非 pull）：amd64 與 arm64 的 Env 皆含 **`HOME=/opt/data`** ✅；`Entrypoint=/opt/hermes/docker/entrypoint-dispatch.sh`、`WorkingDir=/opt/hermes`、`Volumes:{/opt/data:{}}`
    - 其餘 13 個 marker 屬檔案系統層，registry metadata 看不到；已於 B3 於原始碼確認，實際落地留待 D9 於容器內實測
- [ ] C6 若 422 → 去 `https://github.com/kuniakil/hermes-agent/actions` 點 re-enable banner — N/A（未遇 422）

### Phase D — K3s 部署 + 驗證

> **D4 檢查條件修正（Phase 0 實測後）**：我們的 v32 DB **本來就沒有** `messages_fts_cjk` 索引（`sqlite_master` 查 `%cjk%` → 空，僅存 `messages_fts` + `messages_fts_trigram`）。上游 `drop_retired_cjk_index()` 在索引不存在時回傳 `False` → **log 不會**出現「Removed the retired messages_fts_cjk index」訊息。該訊息缺席是**正確**行為，不是遷移失敗。
> D4 改為：確認開機 log 中 **無任何 CJK / fts 相關 ERROR**，且 trigram 索引正常。
> **D7 定位修正**：我們的 CJK 搜尋**當下**就走 trigram 索引 → D7 驗的是「trigram 路徑本來就正常」，不是「遷移後才正常」。

- [x] D1 更新 `~/kubernetes/hermes/overlays/*` kustomize `newTag: v0.23.1`（含 digest 比對）
  - ✅ `~/kubernetes/hermes/overlays/n100/kustomization.yaml`：`newTag: "v0.23.0"` → `"v0.23.1"`（commit `31ede98`，已 push）
  - ✅ digest 比對：Pod 實際 `imageID` = `ghcr.io/kuniakil/hermes-agent@sha256:6546fcb872d6f6b75031b0d153e8556a906556b9ed6dc8fe108917ed8e56c055` ≡ C5 記錄的 multi-arch index digest ✅
  - `overlays/mac` 維持 `v2026.8.3` 不動（Mac 本機不跑此容器；v0.23.0 先例亦只改 n100）
- [x] D2 `kubectl apply -k` + `rollout status`（交子代理）
  - ✅ `kubectl apply -k ~/kubernetes/hermes/overlays/n100` 成功；Deployment `observedGeneration=94`、`updatedReplicas=1 / readyReplicas=1 / availableReplicas=1`
- [x] D3 Pod Running 1/1、RESTARTS 0、image digest 符合
  - ✅ Pod `hermes-agent-6587cc854c-464mf`，`1/1 Running`，`RESTARTS=0`，`imageID` 與 C5 index digest 完全一致
- [x] D4 開機 log：DB migration 32→33 成功、**無 CJK/fts ERROR**（CJK 移除訊息**預期缺席**，見上方修正）、config 52→53 遷移結果
  - ✅ 開機段（`/opt/data/logs/gateway.log`，10:32:23 起）**無任何 CJK / fts 相關 ERROR**；CJK 移除訊息依上方修正**預期缺席**（索引本來就沒建過）
  - ✅ config `_config_version` 已由 52 → **53**；`clarify_timeout` 維持 **600**（上游 `52->53` 遷移只改 `old=3600`，我們非預設值故未被改寫）
- [x] D5 `hermes doctor` 通過；s6 supervision 正常
  - ✅ `hermes doctor` 輸出與升前基線**完全一致**：21 項 ✓、7 項 ⚠（a2a / browser-cdp / computer_use / hermes-yuanbao / image_gen 為 system dependency；discord / discord_admin / x_search 為缺 key）、`Found 1 issue(s)`（缺 API keys，屬既有狀態非升級造成）
  - ✅ s6 supervision 樹完整：`s6-svscan → rc.init top → main-wrapper.sh → profile-gateways → s6-svscan /run/hermes-service → gateway-default → gateway python`
- [x] D6 DB 驗證：`PRAGMA integrity_check`、schema=33、sessions 數量與 Phase 0 一致（基線 sessions=134 / messages=18,067）
  - ✅ `schema_version = 33`、`PRAGMA integrity_check = ok`
  - ✅ `sessions = 134`（= 基線）、`messages = 18,067`（= 基線）；`messages_fts = 18,067`、`messages_fts_trigram = 18,067`，`sqlite_master` 查 `%cjk%` → 空（與升前一致）
- [x] D7 **中文 session 搜尋驗證**（trigram 路徑）
  - ✅ 原始 trigram `MATCH '繁體中文'` → **21** hits；base `messages_fts` 同詞僅 5 hits → trigram 索引確實生效
  - ✅ `SessionDB.search_messages('繁體中文')` → 5 rows，高亮標記 `>>>繁體中文<<<` 正確
  - ✅ `'升級'`、`'記憶'` 各回 5 rows
- [x] D8 config 覆核：模型 / provider 為顯式設定（`MiniMax-M3` / `minimax`）未被改動；`clarify_timeout` 應維持 `600`
  - ✅ `agent.model.default = MiniMax-M3`、`agent.provider = minimax` 皆未被改動；`clarify_timeout = 600` 維持
  - ✅ `hermes --version` → `Hermes Agent vv0.23.1 (2026.9.24) · upstream 9527d9b9`
- [x] D9 自訂層實測：SSH、locale `zh_TW.UTF-8`、`faster-whisper` 轉錄（驗 `av` pin 生效、無 `metadata_errors` TypeError）、`edge-tts`、`ffmpeg`
  - ✅ locale `C.utf8` / `en_US.utf8` / `zh_TW.utf8` 全在（升前基線一致）
  - ✅ `sshd` `/usr/sbin/sshd`、`rsync` `/usr/bin/rsync`、`tini` `/usr/bin/tini`、`tmux` `/usr/bin/tmux`、`ffmpeg` `/usr/local/bin/ffmpeg`、`ffprobe` `/usr/local/bin/ffprobe` 全在
  - ✅ ssh host keys 已產生、`/opt/hermes/docker/entrypoint-ssh.sh` 存在、`HOME=/opt/data`、`/root/.npm` 屬主 `hermes(10000)`、`/tmp/.npm-cache` 權限 `1777`
  - ✅ 額外套件：`edge_tts` / `firecrawl` / `lark_oapi` / `exa_py` / `dingtalk_stream` 皆可 import
  - ⚠️ **`faster-whisper` / `av` 未在 image 內**：`voice` extra 為**惰性安裝**（lazy-install），與 v0.23.0 相同，非本次升級退化。`av==18.1.0` pin 已在 image 內的 `pyproject.toml` 確認存在（`[voice]` 與 `[stt-whisper]` 兩處皆有），但**只有實際 lazy-install 時才會生效**，因此無法在 baked image 內驗證。轉錄功能需在使用者首次觸發語音輸入後，才會在 `/opt/data/installs/<generation>/` 落地並可驗 `metadata_errors` TypeError 是否消失。**本項標記為「待實測觸發」，非阻擋項。**
- [ ] D10 Telegram plugin：gateway 啟動 log 無 ERROR；**使用者實測 Telegram 往返**
  - ✅ **log 部分已驗**：開機後 `errors.log` 第 16713 行之後（10:32:23 起）**ERROR / CRITICAL 計數 = 0**
  - ✅ Telegram adapter 開機後 `10:32:52 Connecting to Telegram (attempt 1/8)` → `10:32:52 Connected to Telegram (polling mode)` ✅
  - ℹ️ 舊 Pod（v0.23.0）於 `07:11:49` 曾出現 `telegram.error.TimedOut` + `Fatal telegram adapter error (telegram_network_error)`（Telegram 網路中斷後重建 adapter）；`10:32:23` 收到 SIGTERM 前**未再復現** → 屬**升級前**事件，非 v0.23.1 迴歸
  - ⏳ **待使用者實測**：實際 Telegram 發一則訊息並確認回覆
- [x] D11 `hermes plugins install` 可看到最新 catalog（驗 16 MiB 上限修正）
  - ✅ `hermes plugins browse` 正常輸出完整 catalog table（`web-venice` / `webmint` / `wiki-ref` / `yandex` / `you` …）
  - ✅ 快取 `/opt/data/cache/plugin-catalog.json` = **2,361,352 bytes（2.25 MiB）> 2 MiB 舊上限**，`entries = 1,378`（`generated_at` / `entries` / `removed`）
  - ✅ 上游修正確實在我們分支：`6cff782b8d fix(plugin-catalog): accept the published catalog past 2 MiB`；client 端上限見 `hermes_cli/plugin_catalog.py:41-42`（「The published doc passed 2 MiB on 2026-11-09 (2,109,306 bytes for 1,268 entries) … 16 MiB leaves …」）
  - ℹ️ **若未套用此修正**，client 會**靜默拒絕**該 catalog 並改用 in-tree pins（1,268 筆 → 看不到較新的移除項目）
- [ ] D12 24h 觀察：RESTARTS、記憶體、ERROR 數（on-demand 手動檢查即可）
  - 當下基線（2026-11-10 10:45 UTC+8 / 開機後約 13 分鐘）：`RESTARTS=0`、`readyReplicas=1`、`observedGeneration=94`、CPU `65m` / MEM `329Mi`、開機後 ERROR 數 `0`
  - ⏳ 於 2026-11-11 上下午手動複查即可（v0.23.0 先例亦為 on-demand 手動檢查，不設自動監控）

### Phase E — 收尾

- [ ] E1 刪除 `hermes-20261106` 備份（D 全綠後），保留 `hermes-20261110`
  - ⏳ 待 D10 / D12 全綠 + **使用者明授權**（v0.23.0 先例亦為取得明授權後才刪）
- [x] E2 撰寫 `UPGRADE_LOG_v0.23.0_to_v0.23.1.md`
  - ✅ 檔名：`/Users/mlee/hermes/UPGRADE_LOG_v0.23.0_to_v0.23.1.md`
  - ℹ️ **位置修正**：工作表原寫 `docs/UPGRADE_LOG_*.md`，但既有 6 份 `UPGRADE_LOG_*.md`（v0.22.1 → v0.23.0）**全部在 repo 根目錄** → 依既有慣例放根目錄
  - 內容涵蓋：官方 notes 稽核、schema/config 遷移實測、自訂層移植、線上全檢查、**pnpm 上游缺陷根因**、備份與回滾、image stamp 差異、尚待完成
- [ ] E3 關閉本工作表所有 checkbox，記錄 image stamp 與分支 HEAD 差異
  - ✅ **image stamp 差異已記錄**：build stamp `9527d9b9b9`（run `42741971255` 的 `headSha` = `hermes --version` 的 `upstream 9527d9b9`）；分支 HEAD `a4adce1b1b`；`git diff --name-only 9527d9b9b9..a4adce1b1b` → **只有本工作表檔** → runtime 程式碼零差異
  - ⏳ 待 D10 / D12 完成後關閉剩餘 checkbox
- [ ] E4 （視需要）以 `doc-and-wp-publish` 發佈至 wp.3pm.lol

### 回退計畫

1. kustomize `newTag` 改回 `v0.23.0`，`kubectl apply -k`。
2. **因 DB 已升 v33，必須先停 Pod，還原 Phase 0 備份的 `/opt/data`**，再起舊 image。
3. 驗證 Pod 1/1、Telegram 往返。

---

## 4. Go-Sign 確認區

- [x] 使用者確認 Q1–Q3 — ✅ 2026-11-10：**Q1 接受**（DB v33 單向遷移，以備份為回退手段）／**Q2 不等 v0.24.0**／**Q3 OK**（D 階段使用者實測 Telegram 往返）
- [x] **Go-Sign 日期 / 時間**：2026-11-10 02:0x UTC（+08:00 上午）

---

## 5. 已知上游問題（非本次升級造成，僅記錄）

### 5.1 `pnpm: not installed or outdated` 啟動警告 — **上游 v0.23.1 缺陷**

**症狀**：每次 CLI dispatch 與 gateway 啟動時，stderr / log 出現

```
⚠ install out of sync (pnpm: not installed or outdated) — this docker-managed install must rebuild the artifact to fix
```

**根因（實測確認）**：

1. 上游 commit `7062229090 chore(js): switch the workspaces from npm to pnpm` 讓 `pm/lock.json` **新增了 `pnpm` 套件條目**
   - 實測：`pm/lock.json` 在 v0.23.0 有 `pnpm` **0** 筆；在我們 v0.23.1 分支有 **19** 筆；`json.load(...)["packages"]["pnpm"]` 確實存在（含 `darwin-arm64` 等 artifacts）
2. `Dockerfile` 的 **runtime_base** stage 的安裝清單在 v0.23.0 與 v0.23.1 **完全相同**，沒有 pnpm：
   ```dockerfile
   RUN python3 -c 'from pm import ensure; [ensure(name, explicit=True) for name in ("uv", "chromium", "npm", "ffmpeg", "ripgrep")]'
   ```
   `pnpm` 只在 `frontend_build`（Dockerfile:334）與 `webapp_build`（Dockerfile:362）stage 被 `ensure("pnpm")` — 這兩個 stage **不會**進 runtime image
3. runtime image 內 `/opt/hermes/tools/facts.json` **沒有 pnpm 條目**，`/usr/local/bin/pnpm` 不存在
4. `pm/install.py: drift()` 會迭代 `lockfile.names()`（= lockfile 全部套件，含 pnpm），對每個非 optional / 非 internal 的套件檢查 `_installed_location(...)`；找不到 → `problems[name] = "not installed or outdated"`
5. `hermes_cli/venv_sync.py: check_runtime()` → `hermes_cli/main.py` 印到 stderr；`gateway/run.py` 記為 WARNING

**影響**：**純外觀**。一次 CLI dispatch 一行 stderr、gateway 一條 WARNING。gateway 正常運作，tool schema 正常 materialize（`Turn machinery warmed in 2.0s (21 tool schema(s))`）。

**是否我們的自訂層造成**：**否**。我們的 Dockerfile 在 pm 相關區段與 upstream **逐行相同**（已 diff 確認），自訂 hunk 都在 locale / ssh / useradd / extras / npm-cache / `HOME=/opt/data` 區段。

**上游是否已修**：**否**。`origin/main` 目前只比 `upstream-v0.23.1` 多 5 個 commit（`8b50838443`、`331a41a81f`、`8edd3120da`、`b3746e35dd`、`d1aed60ec1`），**沒有任何一個** 動到 `pm/` 或 `hermes_cli/venv_sync.py`。

**暫時處置**：不動。等待上游把 `pnpm` 加進 runtime_base 的 ensure 清單（或把 pnpm 標為 optional / internal）。我們不自行在 Dockerfile 加 `ensure("pnpm")` — 那是**改動我們的 image 偏離 upstream** 的方式，應由上游修；若日後確認要本地 workaround，必須另開一個可追溯的 commit 並記錄於升級日誌。

### 5.2 Telegram adapter 在網路中斷後的重建路徑（觀察，非缺陷）

舊 Pod（v0.23.0）於 `2026-11-10 07:11:49` 出現：

```
ERROR telegram.updater.stop() did not finish before the network-recovery deadline; rebuilding the adapter instead of reusing an Updater whose lifecycle lock may still be held. (likely CLOSE-WAIT socket)
ERROR gateway.run: Fatal telegram adapter error (telegram_network_error): ...
```

這是 Telegram API 連線中斷（`149.154.166.110` ConnectTimeout，連續 8 次重試）後的 **adapter 重建**路徑；隨後 `07:12:20 Connected to Telegram (polling mode)` 恢復正常。v0.23.1 開機後**未再復現**（`10:32:52 Connected to Telegram (polling mode)`，且開機後 ERROR 計數為 0）。屬**升級前**事件，非 v0.23.1 迴歸。

### 5.3 `faster-whisper` / `av` 無法在 baked image 內驗證（非缺陷）

`voice` extra 為**惰性安裝**（lazy-install），`faster-whisper` / `av` 不在 image 內，與 v0.23.0 相同。`av==18.1.0` pin（修 PyAV 19 造成的 `metadata_errors` TypeError，上游 #135245）確實存在於 image 內的 `pyproject.toml`（`[voice]` 與 `[stt-whisper]` 兩處），但**只有在實際 lazy-install 時才會生效**。故「無 `metadata_errors` TypeError」必須在使用者**首次觸發語音輸入**、安裝落地到 `/opt/data/installs/<generation>/` 後才能實測。
