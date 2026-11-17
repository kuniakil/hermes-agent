# Hermes 升級工作表：v0.23.1 → v0.23.2

- **Fork remote**：`kuniakil`（`kuniakil/hermes-agent`）；**Upstream remote**：`origin`（`NousResearch/hermes-agent`）
- **目前上線**：`v0.23.1`（分支 `my-config-v0.23.1`，HEAD `1df104be3c`）
- **目標**：官方 `v0.23.2`（commit `ae2a81ccc00e9b7c06301523e5bb09608397149c`，2026-11-16 發布）
- **基線 ref**：`upstream-v0.23.2`（已 fetch；`upstream-v0.23.1` = `3b42157858`）
- **發布模型**：分支建置，不推 tag。`ghcr-publish.yml`（dispatch input **`tag_name`**）→ `ghcr.io/kuniakil/hermes-agent:v0.23.2`
- **狀態**：🚧 **Go-Sign 已取得 → Phase 0–B 已完成（備份驗證 ok、56 linear commits、14/14 Dockerfile markers），準備推送並觸發 GHCR Build**
- **日期**：2026-11-17

---

## 0. ⚠️ 最高優先結論

### 0.1 一句話結論

**`v0.23.2` 名義上是 patch，實際包含 7,918 non-merge commits / 5,211 檔 / 1,989 PRs 的大視窗（完整 curated notes 延至 `v0.24.0`）。好消息是 DB `SCHEMA_VERSION`（33）、`FTS_STORAGE_VERSION`（3）、config `_config_version`（53）與 Docker base image 皆未變更，無不可逆 schema 遷移；但因變更幅度大且 Telegram plugin 有大幅重構，仍維持「先備份 `/opt/data`、再上線、D 階段實測 Telegram 往返」的標準流程。**

### 0.2 不可逆性判定

| 面向 | v0.23.1 | v0.23.2 | 判定 |
|---|---|---|---|
| DB `SCHEMA_VERSION` | 33 | **33** | ✅ **無不可逆遷移**（僅新增冪等 `_heal_reset_rows_carrying_a_delegate_marker`） |
| `FTS_STORAGE_VERSION` | 3 | **3** | ✅ 不變 |
| config `_config_version` | 53 | **53** | ✅ 不變 |
| base image | `debian:trixie-20261020@sha256:4c25275…` | **同一 digest** | ✅ 不變 |
| `Dockerfile` / `stage2-hook.sh` | 自訂 7 hunks / 2 hunks | 上游僅改註解、uv-cache 權限與 umask 077 | ✅ 與自訂層**零重疊** |

> **`hermes_state_schema.py` 實質變動**：新增冪等修復 `_heal_reset_rows_carrying_a_delegate_marker`（清除 `/new` 延續對話誤帶的 `_delegate_from` 標記並補建 trigram 索引，#109073）。若無此異常列，開啟 DB 時不取寫入鎖。

### 0.3 官方 Release Notes（v0.23.2）稽核

- **視窗規模**：`v0.23.1...v0.23.2` 共 7,918 non-merge commits、5,211 個檔案（+239,733 / −22,788）、1,989 PRs、940 closed issues。
- **無 Breaking Changes / Deprecations 章節**：官方明言完整 curated notes 隨 `v0.24.0` 發布，本視窗功能刻意不展開。
- **視窗重點新功能**（節錄自 Release Notes）：
  - **Durable subagents**：gateway 重啟或崩潰後可存活並延續原對話。
  - **Prompt cache**：每個 session 單一 prompt-cache clock。
  - **CLI / 維運**：`hermes fallback check`、`hermes update --force`。
  - **Telegram / Discord / Cron**：Telegram & Discord 支援一次性 `browser_vault` 驗證碼輸入；opt-in shared Telegram DM threads；per-job cron 選項（`wrap_response`、fresh thread per run）。
  - **Model / Provider**：Gemini 3+ 與 Gemini 4 Carbon 預設走 Gemini Interactions API；Claude Mythos 5.2 fast mode。
  - **Plugin APIs & 相容層**：新增 `ctx.fork_session`、`ctx.redact_text()`、`ctx.register_idle_task`；模組搬移相容 shim。
- **RC 修正項目**：
  - Telegram / edit-streaming crash 恢復不再顯示重複 `"Recovered reply"`，修正含 key prefix 的詞（`program_id`）延遲顯示問題（#156546）。
  - Desktop bare `custom` provider（#156545）、Stop button 卡住（#156553）、啟動輸入遺失（#156615, #156642）、斷線重連回覆重複（#156611）、Webapp Nous Portal 導向（#156652）、CLI 離開時殘留 `git` 程序（#156616）。

### 0.4 決策點（Go-Sign 時請回覆）

| # | 決策 | 建議 |
|---|---|---|
| Q1 | DB / Config 版本皆未變（v33 / v53），是否仍執行 Phase 0 線上 `/opt/data` 備份？ | ✅ **建議執行**：雖無 schema 遷移，但 5,211 檔跨度大，留一份升級前快照可確保隨時無痛回退。 |
| Q2 | Telegram plugin 大幅重構（46 檔異動），是否於 Phase D 實測 Telegram 往返？ | ✅ **必須**：Telegram 為唯一使用平台，需實際發訊息驗證。 |
| Q3 | 是否授權依本工作表建立 `my-config-v0.23.2`、推送並觸發 GHCR Build？ | ⏳ **待確認** |

---

## 1. Diff 與衝突面稽核（`upstream-v0.23.1 → upstream-v0.23.2`）

自訂 commits 共 **56 個**（`upstream-v0.23.1..my-config-v0.23.1`，線性 0 merge）。

與上游變動檔案的交集（`comm -12` 實測）：

| 檔案 | 上游變動 | 衝突風險 / 處置 |
|---|---|---|
| `.github/workflows/*`（11 檔） | 上游 workflow 異動 | **全部 purge**，從 `my-config-v0.23.1` checkout 我們的 `ghcr-publish.yml` |
| `Dockerfile` | line 201 註解修正（arm64 chrome 路徑）；line 552 `find /opt/hermes/uv-cache ... chmod o-w` | 🟢 **低（無重疊）** — 直接 cherry-pick `ab78b29e23`（或 `git apply -3`） |
| `docker/stage2-hook.sh` | `.env` / `auth.json` 改以 `umask 077` 建立、`gateway_state.json` chmod 改 best-effort | 🟢 **低（無重疊）** — 直接 cherry-pick `1ee17b3540` |
| `AGENTS.md` | 更新首段說明、新增 `test_prompt_surface.py` 規範 | 🟡 **手動重做** — 取上游版，重新 append「Local Resource Constraint (Mac Host Protection)」 |
| `.env.example` | sudo 密碼安全性警告補充 2 行 | 🟡 **手動重做** — 取上游版，重新加入頂部 `HERMES_IMAGE` 註解（改為 `v0.23.2`） |

不在交集（可乾淨 cherry-pick）：`docker/entrypoint-ssh.sh`、`docker-compose.yml`、根目錄 `UPGRADE_LOG_*.md`（7 份）、`scripts/*`（4 檔）、`docs/**`。

### 1.1 Dockerfile 自訂層必須保留（目標 14/14 marker）

`openssh-server`、`rsync`、`ssh-keygen -A`、`zh_TW.UTF-8`、`en_US.UTF-8`、`useradd -u 10000`、`--extra edge-tts`、`firecrawl`、`dingtalk`、`feishu`、`exa`、`/tmp/.npm-cache`、`docker/entrypoint-ssh.sh`、`ENV HOME=/opt/data`。

---

## 2. 風險重點

| # | 風險 | 嚴重度 | 緩解 / 驗證 |
|---|---|---|---|
| R1 | Telegram plugin 大改（`plugins/platforms/telegram/` 46 檔異動） | 🟠 中 | Phase D 檢查 gateway log 無 ERROR，並由使用者實測 Telegram 往返 |
| R2 | `pm/` 與 `venv_sync.py` 異動（v0.23.1 曾有 `pnpm: not installed or outdated` 警告） | 🟢 低 | Phase D 確認 `hermes doctor`、s6 supervision 與啟動 log |
| R3 | 5,211 檔大視窗，上游完整 notes 尚未發布 | 🟠 中 | Phase 0 備份 + 上線後觀察 `RESTARTS`、記憶體與 `errors.log` |
| R4 | GitHub Actions `HTTP 422` fork auto-disable（Hard Rule 8） | 🟢 低 | 若遇 422，至 `https://github.com/kuniakil/hermes-agent/actions` 點擊 re-enable banner |

### 本次**不需要**做的事

- 不重建 memory/embedding 索引。
- 不推 `v0.23.2` git tag、不建「已知良好」快照 tag（分支建置模型）。
- 本機不跑 `pytest` / `pnpm` / `docker build`（Mac 資源保護規則）。

---

## 3. 執行步驟 Checklist（**待 Go-Sign 後才執行**）

### Phase 0 — 停機前盤點 + 備份

- [x] 0.1 `kubectl --context n100-cf -n hermes get pod`，記錄目前 pod / image digest（基線：`v0.23.1`）
  - Pod `hermes-agent-6587cc854c-464mf`，`1/1 Running`，`RESTARTS 1 (40h ago)`，`IP 10.42.0.63`，Node `n100`
  - Image：`ghcr.io/kuniakil/hermes-agent:v0.23.1`（`sha256:6546fcb872d6f6b75031b0d153e8556a906556b9ed6dc8fe108917ed8e56c055`）
- [x] 0.2 備份 `/opt/data` 至 `~/backups/hermes-20261117/`（`PRAGMA wal_checkpoint(TRUNCATE)` → `[(0, 0, 0)]`，改以 `tar -czf -` 串流避免 Cloudflare websocket 斷線）
- [x] 0.3 驗證備份：`PRAGMA integrity_check = ok`、`schema_version = 33`、`sessions = 134`、`messages = 18,239`（`state.db` 178 MB、`state.db-wal` 0 B）

### Phase A — 建立分支 + Purge + 移植自訂 Commits

- [x] A1 `git checkout -b my-config-v0.23.2 upstream-v0.23.2`（base `ae2a81ccc0`）
- [x] A2 purge 官方 workflows（刪除 47 個上游 workflow，由 `my-config-v0.23.1` checkout `ghcr-publish.yml`，commit `f8a2aeed43`）
- [x] A3 cherry-pick `docker/entrypoint-ssh.sh`（`d84038b3b1`）、`docker-compose.yml`（`1efa309d41`）— 零衝突
- [x] A4 手動重做 `AGENTS.md` Mac 資源限制章節（`6e4530da25`）與 `.env.example` 頂部 `HERMES_IMAGE=ghcr.io/kuniakil/hermes-agent:v0.23.2`（`b02ef9db7e`）
- [x] A5 cherry-pick `docker/stage2-hook.sh`（`ac02ee39d4`）與 `Dockerfile` 自訂層（`1e44e86bfe`）— 零衝突
- [x] A6 cherry-pick 其餘 `UPGRADE_LOG_*.md`、`scripts/*` 與 `docs/**` commits（共 49 commits 零衝突），並加入本工作表

### Phase B — 本地輕量驗證（嚴禁重型測試 / 本機 docker build）

- [x] B1 `git status` 乾淨、`git log --oneline upstream-v0.23.2..HEAD` 為線性（56 + 1 = 57 commits，**0 merge commits**）
- [x] B2 `ls -la .github/workflows` 只剩 `ghcr-publish.yml`
- [x] B3 驗證 `Dockerfile` 自訂層 **14/14 marker 全數在位**，且 `docker/stage2-hook.sh`、`docker/entrypoint-ssh.sh` 完整
- [x] B4 `git diff upstream-v0.23.2 -- Dockerfile` 僅含預期自訂層差異

### Phase C — 推送 Fork + 觸發 GHCR Build

- [ ] C1 `git push -u kuniakil my-config-v0.23.2`
- [ ] C2 `grep -A6 workflow_dispatch: .github/workflows/ghcr-publish.yml` 確認 input 為 `tag_name`
- [ ] C3 `gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v0.23.2 -f tag_name=v0.23.2 -f platforms=all`
- [ ] C4 驗證 run：`event=workflow_dispatch`、`headBranch=my-config-v0.23.2`、`headSha` 為我方最新 commit；派背景子代理 `gh run watch`
- [ ] C5 `docker buildx imagetools inspect ghcr.io/kuniakil/hermes-agent:v0.23.2` 確認 multi-arch index（`amd64` + `arm64`）與 `HOME=/opt/data` env
- [ ] C6 若遇 `HTTP 422`，依 Hard Rule 8 至 `/actions` 點擊 re-enable banner（N/A 若順利觸發）

### Phase D — K3s 部署 + 驗證

- [ ] D1 更新 `~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag: "v0.23.2"`（commit + push）
- [ ] D2 `kubectl --context n100-cf apply -k ~/kubernetes/hermes/overlays/n100` + `rollout status`（長等待交子代理）
- [ ] D3 確認 Pod `1/1 Running`、`RESTARTS 0`、Pod `imageID` 與 C5 multi-arch index digest 一致
- [ ] D4 開機 log 檢查：無 ERROR / CRITICAL、確認 `_heal_reset_rows_carrying_a_delegate_marker`（若有觸發）與 `venv_sync` 狀態
- [ ] D5 `hermes doctor` 與 s6 supervision 樹檢查
- [ ] D6 DB 驗證：`PRAGMA integrity_check = ok`、`schema_version = 33`、`sessions` / `messages` 筆數與 Phase 0 一致
- [ ] D7 自訂層實測：SSH、`zh_TW.UTF-8` locale、`edge_tts` / `firecrawl` / `lark_oapi` / `exa_py` / `dingtalk_stream`、`HOME=/opt/data`
- [ ] D8 **Telegram 往返實測**：確認 gateway `Connected to Telegram`，並由使用者發送訊息實測回覆正常
- [ ] D9 `hermes --version` 確認顯示 `v0.23.2`

### Phase E — 收尾

- [ ] E1 確認保留 `~/backups/hermes-20261117/`，視使用者指示清理前次備份 `~/backups/hermes-20261110/`
- [ ] E2 撰寫 `UPGRADE_LOG_v0.23.1_to_v0.23.2.md`（放 repo 根目錄，依既有慣例）
- [ ] E3 更新並關閉本工作表所有 checkbox，記錄 image stamp 與分支 HEAD 差異
- [ ] E4 視需要以 `doc-and-wp-publish` 發布升級紀錄至 `wp.3pm.lol`

### 回退計畫

1. `~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag` 改回 `"v0.23.1"`，執行 `kubectl --context n100-cf apply -k`。
2. 因 DB / Config 版本同為 v33 / v53，理論上可直接降回；若需完整回復升級前狀態，先停 Pod 再以 `~/backups/hermes-20261117/` 還原 `/opt/data`。
3. 驗證 Pod `1/1 Running` 與 Telegram 往返正常。

---

## 4. Go-Sign 確認區

- [x] 使用者確認 Q1–Q3（同意，執行 Phase 0–C）
- [x] **Go-Sign 日期 / 時間**：2026-11-17 15:21 +08:00
