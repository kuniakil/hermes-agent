# Hermes Agent 升級工作表：v0.22.1 → v0.22.2

- **目標版本**：`v0.22.2`（commit `d923a5eb48`，2026-10-15 發佈）
- **升級前版本**：`my-config-v0.22.1`（HEAD `27c377fdb4`，基於官方 `v0.22.1` = `297552a9d6`）
- **新分支**：`my-config-v0.22.2`
- **Remote**：`origin` = 官方（NousResearch）、`kuniakil` = 個人 fork（⚠️ 兩者名稱與 OpenClaw 相反）
- **發布模型**：`my-config-v0.22.2` 分支為 source of truth，由 `ghcr-publish.yml`（dispatch input **`tag_name`**）建置 `ghcr.io/kuniakil/hermes-agent:v0.22.2`
- **狀態**：✅ **已完成升級並部署**（2026-10-15）
- **最終 HEAD**：`26575c8a21`
- **GHCR digest**：`sha256:7da703c77cba55ff337dc1c374fc780c1414b6a457de21e08f0b7fd33546debc`
- **GH Actions Run**：`38729951089`（prepare / linux-amd64 / linux-arm64 / merge 全部 success）
- **清場**：FK 阻擋 **1 → 0**；messages **17,657 → 17,657 不變**
- **日期**：2026-10-15

---

## 0. ⚠️ 最高優先結論：v0.22.2 是 **回滾**，不是增量

這是本次升級唯一真正重要的事，先講清楚：

> 官方 Release Notes：「**v0.22.1 was built from the wrong commit. It shipped unreleased gateway work**… 0.22.2 is the release 0.22.1 was meant to be.」
> **Known issue: Sessions that ran under the 0.22.1 gateway can't be deleted in 0.22.2.**

拓撲證據（本地已驗證）：

```
d923a5eb48  parents = 4ccc58062c (release 分支) + 297552a9d6 (v0.22.1 正式 tag)
```

`v0.22.1` 是 `v0.22.2` 的**第二父節點**（merge commit 的 side branch），所以 `git diff v0.22.1 v0.22.2` 是「把 v0.22.1 的內容整批拿掉」。

| 比較基準 | 檔案數 | +/− | 意義 |
|---|---|---|---|
| `v0.22.0 → v0.22.1` | 2,170 | +190,328 / −49,590 | v0.22.1 = **session-authority 大重構** |
| `v0.22.1 → v0.22.2` | 2,041 | +50,567 / **−185,914** | v0.22.2 = **整批回滾該重構** |
| **`v0.22.0 → v0.22.2`** | **256** | **+7,045 / −1,654** | **v0.22.2 的真實內容增量** |

**換言之：`v0.22.2 ≈ v0.22.0 + 256 檔修正`。** 我們目前部署的 `v0.22.1` 帶著官方自己承認「不該出貨」的 gateway 重構。

### 0.1 被移除的 v0.22.1 模組（21 個 state 檔 + 工具層）

| 類別 | 被 v0.22.2 移除的檔案 |
|---|---|
| Worker 生命週期 | `hermes_state_worker_lifecycle.py` `hermes_state_worker_compression.py` `hermes_state_worker_context.py` `hermes_state_runtime_workers.py` `hermes_state_runtime.py` |
| Mutation receipt 層 | `hermes_state_mutations.py` `hermes_state_mutation_binding.py` `_branch.py` `_compress.py` `_guards.py` `_prepared.py` `_reset.py` `_retirement.py` `_transcript.py` |
| 本機 / lineage | `hermes_state_local.py` `hermes_state_local_lineage.py` `hermes_state_local_migration.py` `hermes_state_terminal.py` `hermes_state_media.py` `hermes_state_keys.py` `hermes_state_sessions_model_config.py` `hermes_state_profile_repair.py` |
| Agent 層 | `agent/managed_worker.py` `agent/runtime_session_store.py` `agent/runtime_session_lifecycle.py` `agent/persisted_turn_receipt.py` `agent/safe_worker_policy.py` `acp_adapter/*` |

被刪的 DB 物件（`hermes_state_common.py` 在 v0.22.2 移除 63 行）：

```sql
CREATE TABLE IF NOT EXISTS runtime_epoch      -- 已移除
CREATE TABLE IF NOT EXISTS session_admissions -- 已移除
CREATE TABLE IF NOT EXISTS worker_executions   -- 已移除（含 FK ON DELETE RESTRICT）
CREATE TABLE IF NOT EXISTS worker_receipts     -- 已移除
CREATE INDEX  IF NOT EXISTS idx_worker_executions_session_status
-- 以及 sessions 上的 DELETE 保護 trigger（原本檢查 worker_executions）
```

### 0.2 這個回滾對我們的實際影響

| 面向 | 影響 | 等級 |
|---|---|---|
| **既有 session 可讀性** | v0.22.1 寫進 DB 的 session 訊息仍在 `messages` / `sessions` 表（核心 schema 未變），v0.22.2 讀得到 | 🟢 |
| **既有 session 刪除** | 官方明示：**在 0.22.1 gateway 跑過的 session，在 0.22.2 刪不掉** | 🔴 需實測 |
| **殘留 `worker_*` 表** | v0.22.2 不再建立也不讀取，**沒有 DROP** → 表會留在 DB 裡當垃圾（無害，但要知情） | 🟡 |
| **config `_config_version`** | 我們的 config 已被 v0.22.1 蓋成 **51**；v0.22.2 的 migration 最高只到 **50** → 沒有任何 migration 會跑（`current_ver=51 > max target=50`），**不會崩、不會降版改寫** | 🟡 |
| `cron.bot_chat_delivery_timeout_seconds` | v0.22.1 的 step-51 會刪掉它；v0.22.2 不讀這個 key → 殘留無害 | 🟢 |
| **我們的自訂補丁** | ✅ **完全不受影響**（見 §3） | 🟢 |
| **本地模型（Local Models）** | v0.22.2 新增 7 個 agent 檔做筆電續命（我們容器內用不到，但無害） | 🟢 |

> **決策點（Go-Sign 時請一併回覆）**：
> **(A) 照升 v0.22.2** — 追隨官方，修掉 v0.22.1 的錯誤出貨，gateway 開機 bug 有實質修正（見 §1.2）。
> **(B) 暫停在 v0.22.1** — 等 v0.23.0（官方說「只在 main 上的工作隨 v0.23.0 出貨」）。代價是繼續跑官方已承認錯誤的版本。
>
> 傾向 **(A)**：官方把 v0.22.1 標記為錯誤出貨、Microsoft Store 卡在 "Connecting."，長期跟一個已知壞版本不划算；且我們的自訂層與 v0.22.2 零衝突。
>
> ✅ **2026-10-15 使用者已選定 (A)**，理由：v0.22.1 是今天稍早才升級，只下過一個提示詞（系統檢查），得到一組回覆；既然 v0.22.1 非官方預期版本，這一組往返不值得保留糾結。
> （§9 的實地勘查進一步證實：**實際損失為零**，連那一組提示詞+回覆都會完整保留。）

---

## 0.3 「刪不掉」的真正機制（FK `ON DELETE RESTRICT`）

官方 Known issue 的根因，三段式：

### ① v0.22.1 留下反向參照 sessions 的表

`hermes_state_common.py`（v0.22.1 第 510–552 行）：

```sql
CREATE TABLE IF NOT EXISTS session_admissions (
    target_session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE RESTRICT,  -- ← 阻擋器
    ...);
CREATE TABLE IF NOT EXISTS worker_executions (
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE RESTRICT,          -- ← 阻擋器
    ...);
CREATE TABLE IF NOT EXISTS worker_receipts (
    execution_id TEXT NOT NULL REFERENCES worker_executions(execution_id) ON DELETE RESTRICT, ...);
```

### ② v0.22.1 刪除時會先拆阻擋器

`hermes_state_mutation_retirement.py`（**該檔在 v0.22.2 整個不存在**）：

```python
conn.execute('DELETE FROM worker_receipts    WHERE execution_id=?', ...)
conn.execute('DELETE FROM worker_executions  WHERE session_id=?',   (sid,))
conn.execute('DELETE FROM session_admissions WHERE target_session_id=?', (sid,))
...  # 最後才 DELETE FROM sessions
```

### ③ v0.22.2 忘了前兩步，而 FK 檢查是開著的

`hermes_state_sessions.py:1770-1773`（v0.22.2）直接：

```python
conn.execute("DELETE FROM messages WHERE session_id = ?", (session_id,))
conn.execute("DELETE FROM sessions WHERE id = ?",         (session_id,))   # 沒清 child
```

`hermes_state.py:806`（**兩版都有**）：`conn.execute("PRAGMA foreign_keys=ON")`
→ SQLite 掃到仍有參照列 → **`FOREIGN KEY constraint failed`** → 交易 rollback → 刪不掉。

### 三張表分別存什麼（清場會不會傷到對話）

| 表 | 內容 | 對話本體？ | 清掉後損失 |
|---|---|---|---|
| `session_admissions` | `payload_json` = **每則使用者輸入的原文副本** + `intent`/`status`/`outcome` 收件帳 | ❌ 不是 | 訊息**內容不損失**（在 `messages`）；損失的是「這則當初是 queue 還是 steer 進去、最後 outcome 為何」的帳 |
| `worker_executions` | worker 登記簿（cron / delegate child / kanban 的 session 指標 + 狀態） | ❌ 不是 | 追蹤指標 |
| `worker_receipts` | `result_json` = parent/session 指針 + `title_candidate` 標題候選 | ❌ 不是 | 指派紀錄、標題去重憑證 |

> **`sessions` / `messages` / 標題 / 附件 完全不動。**
> 唯一真實資料損失風險：`status IN ('queued','started','unknown')` 的**未完成輸入**會被丟掉 → §9 實測為 **0 列**，此風險已排除。

---

## 1. 官方 Release Notes 稽核（v0.22.2）

來源：`https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.2`（`gh release view v0.22.2`）

### 1.1 發佈定位

- v0.22.1 由錯誤 commit 建置，出貨了未發佈的 gateway 工作，且 Microsoft Store app 會卡在 "Connecting."。
- **v0.22.2 = v0.22.1 本應發佈的內容**。
- Release notes 涵蓋「v0.22.0 之後 0.22 線的**全部**內容」（含 0.22.1 本該帶的修正 + 下面兩個亮點）。

### 1.2 兩大亮點（與我們的關聯）

| 亮點 | 內容 | 對我們 |
|---|---|---|
| **Gateway 開機後又會啟動了** | 重開機後 Linux 可能把早期 PID 指派給無關行程，gateway 誤判已有 gateway 在跑，導致 systemd / launchd / Docker 下的 supervised gateway 拒絕啟動。現在會記錄啟動時的 boot，並在無法判斷時改問 host lock（只有活著的 gateway 持有）。Fixes #133744 | 🔴 **直接命中我們的部署形态**（K3s pod 重啟 = supervisor 重啟） |
| **筆電上的本地模型長對話不再死掉** | 本機請求一律帶 prompt 閱讀進度（顯示在 status line）、stall 計時器扣除睡眠時間、本機 server 復原後會再試一次、壓縮不再因 server 還在讀長對話而逾時。Windows unified-memory 機器上模型啟動與 prompt cache 依空閒記憶體 sizing。 | 🟢 我們用雲端 provider，不吃這條 |

### 1.3 Breaking Changes / Deprecations 稽核

**Release Notes 沒有 `Breaking Changes` 或 `Deprecations` 章節。** 但因為它是回滾（§0），隱含的行為變更必須自行盤點：

| 隱含變更 | 說明 |
|---|---|
| ❌ session authority / mutation receipt 機制**不存在了** | 所有 session 寫入路徑回到 v0.22.0 的模型。若我們日後依賴 v0.22.1 新增的 canonical 控制面，需改寫 |
| ❌ `worker_executions` / `worker_receipts` / `session_admissions` / `runtime_epoch` 表**不再被寫入** | 已產生的資料靜止 |
| ❌ 對 `sessions` 的 DELETE 保護 trigger 移除 | 理論上刪除更容易，但官方說 0.22.1 跑過的 session 仍刪不掉 → 需實測找出真正阻擋來源 |
| ⚠️ config migration 階梯**倒退**（51 → 50） | 已 stamp 51 的 config 不會有任何 migration 執行；**沒有 downgrade 破壞** |
| ⚠️ `STAMP_INDEPENDENT_STEPS`（v0.22.1 為 `{46, 50}`）在 v0.22.2 不存在 | 對我們（單一 config stamp 51）無影響 |

### 1.4 Dependency / Runtime 稽核（機器可讀真相）

| 項目 | v0.22.1 | v0.22.2 | 判定 |
|---|---|---|---|
| `pyproject.toml` | — | **零 diff** | ✅ `requires-python >=3.11,<3.15` 不變，我們 3.14.7 相容 |
| `uv.lock` | — | **零 diff** | ✅ |
| `pm/lock.json` | — | **零 diff** | ✅ pm 套件版本全不變 |
| `Dockerfile` | blob `e3d11031c8` | blob **`e3d11031c8`** | ✅ **位元組相同** → 我們 8 處補丁零衝突 |
| `docker/stage2-hook.sh` | blob `48eb36f5a9` | blob **`48eb36f5a9`** | ✅ 位元組相同 |
| `docker/entrypoint-ssh.sh` | 我們自創 | 上游仍不存在 | ✅ 乾淨沿用 |
| `docker-compose.yml` | 我們自訂 | 上游存在但我們覆寫 | ✅ 沿用我們的 |
| 根 `package-lock.json` | — | +2 / −2 | 例行 bump，**`overrides` 未動** |
| `hermes_state_common.py: SCHEMA_VERSION` | **31** | **31** | ✅ **未變** |
| `FTS_STORAGE_VERSION` | **3** | **3** | ✅ 未變 |
| `hermes_state_schema.py` | — | **零 diff** | ✅ 核心表欄位不變 |
| config migration 最高階梯 | **51** | **50** | ⚠️ 倒退一階（見 §1.3） |

### 1.5 Schema / 不可逆性判定

> **`SCHEMA_VERSION` 31 → 31 未變、`hermes_state_schema.py` 零 diff → 沒有需要人工 DB 遷移的變更。**

但因為是版本**倒退**，仍建議在部署前做一次 **state.db 備份**（成本極低、可回滾），理由不是 schema 遷移，而是：
1. 官方自曝「0.22.1 gateway 跑過的 session 在 0.22.2 刪不掉」——未知邊界的資料相容性；
2. 回滾到 v0.22.1 時，若 v0.22.2 期間有寫入，回滾路徑未經測試。

**判定：非不可逆，但備份列為 MANDATORY（低成本保險）。**

---

## 2. Diff 稽核（`upstream-v0.22.1..upstream-v0.22.2`）

### 2.1 關鍵路徑

| # | 路徑 | 上游變更 | 影響 |
|---|---|---|---|
| 1 | **`Dockerfile`** | **零 diff（blob 相同）** | 🟢 **我們的 8 處補丁可原樣套用** |
| 2 | `docker/stage2-hook.sh` | 零 diff（blob 相同） | 🟢 乾淨沿用 |
| 3 | `docker/entrypoint-ssh.sh` | 上游無此檔 | 🟢 沿用我們的 |
| 4 | `docker-compose.yml` | 上游有，但我們覆寫 | 🟢 沿用我們的 |
| 5 | `AGENTS.md` | 我們追加的 Mac host 保護規則 | 🟢 沿用（見 §3.3 確認上游無新 AGENTS 規則） |
| 6 | `.github/workflows/` | 55 → **54** 檔（`docs-search-monitor.yml` 刪除）；`ci.yaml`、`tests.yml` 有修改 | 🟢 依 Purge 規則全刪 |
| 7 | `hermes_state_*.py` | **−3,723 行 / 21 檔被刪除** | 🔴 §0.1 |
| 8 | `gateway/host_rendezvous.py` | 修改（boot epoch / PID 重用 / argv 身分移除） | 🔴 我們的核心部署路徑 |
| 9 | `tools/` | 修改（`mcp_tool*` `process_registry.py` `file_operations_search.py` `approval_smart.py` `environments/local.py`） | 🟡 |
| 10 | `hermes_cli/` | 修改（新增 `hermes_cli/profile_model_seed.py`、`local_runtime/*` 大改） | 🟡 |
| 11 | `agent/` | 新增 6 檔（local model 長對話續命） | 🟢 |
| 12 | `tests/gateway/`、`apps/desktop/`、`ui-tui/src/` | 分別刪 466 / 132 / 60 檔 | 🟢 回滾的一部分 |

### 2.2 衝突面計算

```
我們自訂 commit 觸及：  64 檔
上游 v0.22.1→v0.22.2：2041 檔
重疊：                  3 檔  ← ci.yaml / docs-search-monitor.yml / tests.yml
                        （三者在我們分支皆為 DELETED → 依 Purge 規則直接刪，不需解決）
Dockerfile / docker/ / docker-compose.yml / AGENTS.md / .env.example：零重疊
```

✅ **結論：唯一實質衝突 = 0。** 這是歷次升級中最乾淨的一次。

---

## 3. 需攜帶的自定義補丁

我們的 Dockerfile 對上游的差異共 **8 個 hunk**（`git diff upstream-v0.22.2 my-config-v0.22.1 -- Dockerfile | grep -c '^@@'` = **8**，已驗證）：

| # | 內容 |
|---|---|
| 1 | apt：`openssh-server` `rsync` `locales`；`mkdir /var/run/sshd` + `ssh-keygen -A`；`locale-gen`（`C.UTF-8` / `en_US.UTF-8` / `zh_TW.UTF-8`）+ `/etc/default/locale` + `/etc/profile` + `.bashrc` |
| 2 | `useradd ... -s /bin/bash hermes` |
| 3 | pm ensure + symlink 加入 **`agent-browser`** |
| 4 | `build_env --extra edge-tts firecrawl dingtalk feishu exa`（保留上游 `--cache /opt/hermes/uv-cache`） |
| 5 | `/tmp/.npm-cache`（sticky bit 1777） |
| 6 | `/root/.npm` `/root/.cache` chown 10000 |
| 7 | `ENV HOME=/opt/data` |
| 8 | `COPY docker/entrypoint-ssh.sh`（Zeabur 相容 shim） |

自訂 commit 清單（`upstream-v0.22.1..my-config-v0.22.1`，13 個）：

| # | commit | 說明 | 處置 |
|---|---|---|---|
| 1 | `1fc47d42ac` | `chore(ci)`:purge 官方 CI，只留 `ghcr-publish.yml` | 🔁 重做（在新分支 purge） |
| 2 | `08fa3fc96e` | `fix(docker)`:還原 `docker/entrypoint-ssh.sh` | ✅ cherry-pick |
| 3 | `1e87666e04` | `chore`:帶入 `docker-compose.yml`（`HERMES_IMAGE` / `TZ=Asia/Taipei`） | ✅ |
| 4 | `b85ee26ccb` | `chore`:Mac host 資源限制規則 → AGENTS.md | ✅ |
| 5 | `b4e66c5ecb` | `fix(docker)`:stage2 SSH 設定 + npm cache | ✅ |
| 6 | `be2a5bab24` | `feat(docker)`:re-port custom layer（8 處補丁） | ✅ **可整顆 cherry-pick**（Dockerfile blob 相同 → 應零衝突） |
| 7 | `297552a9d6` 前的 docs 群（`81bc37f796` `743fff18a2` `44ad86732b` `50211a022c` `63ee4be848` `68179b7d4a` `27c377fdb4`） | v0.22.1 歷史文檔 + `.env` 修復 | ✅ 歷史文檔保留 |
| 8 | `a36fb64f28` `297552a9d6` | 壓縮修正 — **屬上游**，不 cherry-pick（v0.22.2 已回滾） | ❌ 跳過 |

> 📌 `.env` 風險已解除：commit `27c377fdb4` 已把 `.env` untrack 並 gitignore。
> §Phase B 會再跑一次「tracked-but-ignored 檔案遺失偵測」確認。

### 3.3 上游 AGENTS.md 是否有新規則需合併

- [x] §3.3 檢查完畢：`git diff upstream-v0.22.1 upstream-v0.22.2 -- AGENTS.md` **零 diff**；我們的 Mac host 保護區塊保留（`git grep -c 'Local Resource Constraint' = 1`）

---

## 4. 執行步驟 checklist

### Phase 0 — 停機（§9 實測：現在閒置，可安全停）
- [x] 0.1 確認無使用中（24h 訊息 25 則，最後 14:48）：`kubectl exec ... -- python3 -c "..."` 檢查 24h 內訊息數（本文件產生時為 25 則，最後一則 14:48）
- [x] 0.2 記錄基線：sessions 127 / messages 17,657：`sessions` 127 / `messages` 17,657（升級後不得下降）
- [x] 0.3 **備份 DB（含 -wal / -shm，缺一則備份不完整）**
  ```bash
  kubectl cp n100/hermes-agent-...:/opt/data/state.db       ./backup/state.db-20261015
  kubectl cp n100/hermes-agent-...:/opt/data/state.db-wal   ./backup/state.db-wal-20261015
  kubectl cp n100/hermes-agent-...:/opt/data/state.db-shm   ./backup/state.db-shm-20261015
  ```
- [x] 0.4 驗證備份：`sqlite3 backup/state.db-20261015 "SELECT COUNT(*) FROM messages"` → 17657
- [x] 0.4b 🗑️ **狀態更新 (2026-10-22)：本工作表產生的備份已刪除**
  - 落地路徑：`~/kubernetes/hermes/backups/20261015/state.db`（+ wal/shm，177 MB）→ **已於 2026-10-22 15:25 刪除**
  - 刪除理由：這是**清場之前**的快照（帶 3 列 v0.22.1 殘留 `session_admissions` ledger），拿它回滾 v0.22.2 會讓「session 刪不掉」復發 → 不是合格回滾產物；且已被 v0.22.4 升級前的新備份取代
  - 保留中的備份：`~/backups/hermes-20261022/state.db`（保留至 **2026-10-25**）→ 詳見 `UPGRADE_LOG_v0.22.2_to_v0.22.4.md` §8
    - 🔴 **實際於 2026-10-24 14:21 提前刪除**（使用者明確指示，由 `~/backups/hermes-20261024/` 取代）→ 詳見 `UPGRADE_LOG_v0.22.4_to_v0.22.5.md` §14
- [x] 0.5 **已取消 scale-to-0**（改為：清場在 v0.22.2 上線後做，該版本無 ledger 寫入者 → 服務全程不中斷） deploy/hermes-agent -n hermes --replicas=0`（保留 1 個舊 pod 做 DB 來源比較）

### Phase A — 建分支 + Purge + 攜帶自訂
- [x] A0. **Go-Sign 確認** → §0.2 決策 **(A)** 已於 2026-10-15 選定
- [x] A2. `git fetch origin refs/tags/v0.22.2:refs/tags/upstream-v0.22.2 --no-tags`（已完成 ✅）
- [x] A3. `git checkout -b my-config-v0.22.2 upstream-v0.22.2` → 應為 `d923a5eb48`
- [x] A4. Purge 官方 workflows，只留我們的 `ghcr-publish.yml`（54 → 1，blob 須與 v0.22.1 分支相同）
- [x] A5. cherry-pick commit #2 #3 #4 #5 #6（**預期全部零衝突**）
- [x] A6. 複驗 `git diff upstream-v0.22.2 HEAD -- Dockerfile | grep -c '^@@'` = **8**
- [x] A7. 複驗 Dockerfile 仍含上游 `--cache /opt/hermes/uv-cache` 與 `--record-selection`
- [x] A8. **tracked-but-ignored 遺失偵測**（承 v0.22.1 教訓）
  ```bash
  comm -23 <(git ls-tree -r my-config-v0.22.1 --name-only | sort -u) \
           <(git ls-tree -r my-config-v0.22.2 --name-only | sort -u) \
    | git check-ignore --stdin --no-index 2>/dev/null
  ```
  期望：**空輸出**（本次預檢已確認為空 ✅）
- [x] A9. 提交歷史文檔（v0.22.1 worksheet / upgrade log）

### Phase B — 本地輕量驗證（不做重測 / 不本機 build）
- [x] B1. `git status` 乾淨
- [x] B2. Dockerfile 8 個自訂標記全數存在（`openssh-server` `rsync` `locales` `en_US.UTF-8` `zh_TW.UTF-8` `ssh-keygen -A` `-s /bin/bash` `agent-browser` `edge-tts` `firecrawl` `uv-cache`）
- [x] B3. `.github/workflows/` 僅 `ghcr-publish.yml`
- [x] B4. blob 雜湊比對：`docker/entrypoint-ssh.sh`、`docker/stage2-hook.sh`、`docker-compose.yml`、`AGENTS.md`、`ghcr-publish.yml` → 應 5/5 SAME
- [x] B5. dispatch input 仍為 **`tag_name`**（不是 `tag`）
- [x] B6. 確認 v0.22.1 特有檔案已消失（`hermes_state_worker_lifecycle.py`、`hermes_state_runtime.py`、`agent/managed_worker.py`、`acp_adapter/`）→ 證明回滾生效
- [x] B7. 確認 `hermes_state_common.py` 已無 `worker_executions` / `worker_receipts` 建表
- [x] B8. `.env` 仍在 working tree 且未被刪（`ls -la .env`）
- [x] B9. npm 決策複驗（兩版 `overrides` 皆為 `(none)` → 維持「不修」決策）：根 `package-lock.json` 的 `overrides` 在 v0.22.2 仍為 `{}` → 維持「不修」決策

### Phase C — 推送 + 建置
- [x] C1. `git push -u kuniakil my-config-v0.22.2`
- [x] C2. dispatch：**`gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v0.22.2 -f tag_name=v0.22.2 -f platforms=all`**
- [x] C3. 驗證 run：`event=workflow_dispatch`、`headBranch=my-config-v0.22.2`、`headSha` = **我方 commit**（絕非 `d923a5eb48`）
- [x] C4. `gh run watch` → prepare / linux-amd64 / linux-arm64 / merge 全 success
- [x] C5. image tags 存在：`v0.22.2`、`latest`
- [x] C6. **未 force-push 版本 tag**

### Phase D — 部署 + 驗證（🔴 針對回滾的專項測試）
- [x] D1. `~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag: "v0.22.1"` → `"v0.22.2"`
- [x] D2. `kubectl kustomize .` render 正確；rollout **successfully rolled out**
- [x] D3. `sessions.auto_prune: false` 仍在（注意 config stamp 51 > v0.22.2 最高階梯 50，**不會有任何 migration 執行**——這是預期行為）
- [x] D4. 冒煙測試：Python 3.14.7 / locale 3 種 / sshd+rsync+tini / ffmpeg+agent-browser / edge_tts+dingtalk_stream+lark_oapi+firecrawl / Telegram connected / **0 ERROR**
- [x] D5. **🔴 Session 回滾專項**：部署前 `SELECT COUNT(*)` sessions/messages → 部署後重測，數字**不得下降**
- [x] D6. **🔴 已知-issue 重現**：抽 2–3 個「v0.22.1 期間建立的 session」嘗試 `hermes sessions delete`，記錄是否仍被拒（官方說會被拒；我們要知道實際阻擋來源與嚴重度）
- [x] D7. `state.db` `schema_version` 實測 = **31**；部署 60s 後 **0 restart**
- [x] D8. **Gateway 開機修正驗證**：刪 pod 強制重啟，確認 gateway 在新 PID 下正常啟動（本次亮點 #138594，命中我們的 supervised 部署）
- [x] D9. **🔴 清場（已在 v0.22.2 上線後執行）**：必須在 v0.22.2 已上線後做
  > ⚠️ **v0.22.1 還活著時清 = 白清**，因為它的 gateway 收到一則訊息就會重新寫入 `session_admissions`。
  > 必須「先升級 → 再清」，清完 v0.22.2 不會寫回，才是永久乾淨。
  - [x] D9.1 清場前複查 pending（應仍為 0）
    ```sql
    SELECT status, COUNT(*) FROM session_admissions GROUP BY status;
    ```
    ⚠️ 若出現 `queued`/`started`/`unknown` **> 0** → **停止**，那些是未處理完的輸入
  - [x] D9.2 執行清場（§9 實測：3 條 terminal、worker 兩表已空）
    ```sql
    DELETE FROM session_admissions;   -- 3 列，全 terminal
    -- worker_executions / worker_receipts 本來就是 0 列，無需動
    ```
  - [x] D9.3 驗證 FK 阻擋解除
    ```sql
    SELECT COUNT(*) FROM sessions s
    WHERE EXISTS(SELECT 1 FROM session_admissions a WHERE a.target_session_id=s.id)
       OR EXISTS(SELECT 1 FROM worker_executions  w WHERE w.session_id=s.id);
    -- 期望：0
    ```
  - [x] D9.4 **實測「系統升級檢查」可刪**：在交易內 `BEGIN; DELETE FROM sessions WHERE id='20260708_133022_65a00a95'; ROLLBACK;` 確認不再拋 FK 錯誤（測完 rollback，**不真刪**）
  - [x] D9.5 `sessions` 仍 127 / `messages` 仍 17,657
  - [x] D9.6 殘留的 `worker_executions` / `worker_receipts` / `runtime_epoch` **空表不 DROP**（保留為回滾證據；若需清理留待後續）

### Phase E — 收尾
- [x] E1. 產出 `UPGRADE_LOG_v0.22.1_to_v0.22.2.md`（**務必記錄這是回滾，不是升級**）
- [x] E2. 在 post-mortem 加入「官方 v0.22.1 出貨錯誤」與「回滾導致 session 刪除受限」兩筆
- [x] E3. 本工作表同步實際執行結果
- [x] E4. `.env` `HERMES_IMAGE` — k8s 走 `newTag` 不受影響；本機 docker compose 尚未使用

---

## 5. 專案特定備註（Hermes）

- **Fork remote**：`kuniakil`；**Upstream remote**：`origin`（⚠️ 與 OpenClaw 相反，先跑 `git remote -v` 確認）
- **Workflow**：`ghcr-publish.yml`（上游**沒有**這個檔，純自訂）
- **dispatch input**：**`tag_name`**（**不是** `tag`；傳錯會被靜默忽略，只會產出 `latest`）
- **k8s overlay**：`~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag` → `v0.22.2`
- **目前上線版本**：`v0.22.1`
- **Host 保護**：本機**不**跑 pytest / docker build / 全面 typecheck；僅 `git diff` / `git status` + 單檔語法檢查；編譯與完整測試交由 GitHub Actions

---

## 6. npm 漏洞決策複驗（承 v0.22.0 §8.3）

| 檢查 | 結果 |
|---|---|
| ① 根 `package-lock.json` `overrides` v0.22.1 → v0.22.2 | 皆為 `{}`，**未變動** → 維持「不修」決策的前提成立 |
| ② `package-lock.json` 整體 diff | 僅 +2 / −2 例行 bump |
| ③ 容器內 `find /opt/hermes -name node_modules -type d` | Phase D4 重測（沿用 v0.22.0 結論：僅 photon sidecar 一棵樹，未啟用） |

**額外收穫**：官方 v0.22.1 已修 `agent-browser` / WhatsApp bridge / httpx2 等 npm audit 問題 — 但那些程式碼在 v0.22.2 **被回滾掉了**。我們容器內不啟用 sidecar，暴露面維持不變。

---

## 7. 風險總結

| 風險 | 等級 | 緩解 |
|---|---|---|
| **v0.22.2 是回滾，非升級**（2,041 檔被撤） | 🔴 高 | §0 已完整盤點；Go-Sign 前明確告知；D5/D6 專項實測 |
| **0.22.1 建立的 session 在 v0.22.2 刪不掉**（官方 known issue） | 🟢 **低**（實測後下修） | §9：全庫僅 **1/127** 個 session 受影響；`session_admissions` 僅 3 列**全 terminal**、`worker_*` 兩表已空 → **清場零資料損失**（Phase 0 已備份、D9 清場） |
| 「損失一組提示詞+回覆」 | 🟢 **無損失** | §9.3 已驗證：`messages` 不動、`hermes_state_schema.py` 兩版 blob 相同、v0.22.2 的 `SELECT *` 全包在 `dict(row)` 內 → v0.22.1 專屬欄位（`runtime_generation` 等）殘留但無害 |
| config stamp 51 > v0.22.2 最高階梯 50 | 🟡 中 | 已確認無 downgrade 破壞（migration 只往前跑）；D3 驗證 `auto_prune: false` 未被動 |
| 殘留 `worker_*` 表 | 🟡 中 | D9 先記錄不 DROP，保留回滾保險 |
| Gateway 開機／PID 判定邏輯大改（`host_rendezvous.py`） | 🟡 中 | D8 強制重啟驗證；我們 K3s 部署直接命中此路徑 |
| Dockerfile 補丁衝突 | 🟢 **無** | 上游 Dockerfile blob 逐位元相同，8 hunk 可原樣套用 |
| 54 個 workflow 衝突 | 🟢 無 | Purge 規則直接刪除 |
| pm 套件版本 / Python 版本 | 🟢 無 | `pm/lock.json`、`pyproject.toml` 零 diff |
| DB schema 遷移不可逆 | 🟢 **無** | `SCHEMA_VERSION 31 → 31`、`hermes_state_schema.py` 零 diff |

---

## 8. Go-Sign

- [x] 使用者選定 §0.2 決策 **(A) 照升 v0.22.2**（2026-10-15）
- [x] 使用者回覆「Go」並選定 **(A)**，Phase 0 → A → B → C → D → E 全部執行完畢（2026-10-15）

---

## 10. 官方對「降級」的正式立場（2026-10-15 查證）

### 10.1 原始碼：`hermes_cli/update_downgrade_guard.py`（存在於 `main`，v0.22.2 無此檔）

> Releases before the gateway cutover know nothing of the runtime ledgers (`session_admissions` /
> `worker_executions`, `ON DELETE RESTRICT`) and stamp the same `schema_version`, so moving the
> code back under a store that holds ledger rows leaves every session with that history undeletable
> there. **Downgrading is unsupported**: the update refuses before anything moves and names the
> recovery point that predates the cutover.

這個 guard 的行為：`target_predates_runtime()` 會在套用前偵測目標版本是否早於 gateway cutover，若目標版本看不懂 ledger 而本地 DB 已有 ledger 列 → **拒絕更新**，並指向 pre-cutover 快照作為復原點。

### 10.2 官方文件 `getting-started/updating`

> `hermes update` refuses a pre-gateway-runtime target before changing the checkout. A manual
> checkout of an old release also cannot delete or prune sessions with gateway history—it fails with:
> **`Refused to delete a session that has gateway runtime history`**
>
> **Supported recovery:** restore a coherent pre-update state rather than running the old release
> against the upgraded database — `hermes gateway stop` → 舊版 checkout → `/snapshot restore <id>`
> 或 `hermes import <backup.zip>`（`hermes update --backup` 產生）。

### 10.3 「以後會不會修？」的精確答案

| 版本 | 受影響 session 刪得掉嗎 | 原因 |
|---|---|---|
| **v0.22.2** | 🔴 **永遠不會** | 舊世界看不懂這兩張表；官方**刻意不寫任何清理程式碼**（已 grep 確認 `v0.22.2` 與 `main` 對 `session_admissions`/`worker_executions` 的清理邏輯皆為 0）。這不是 bug，是護欄 |
| **v0.23.0 (`main`)** | 🟢 **會** | `main` **已重新上架整套 ledger 機制**（`hermes_state_worker_lifecycle.py` / `hermes_state_runtime.py` / `hermes_state_mutation_retirement.py` 等全部回來），刪除路徑會先清 ledger 再刪 session；且殘留的 terminal 列對它無害（會被自己的刪除路徑清掉） |

> 📌 **結論：v0.22.2 是「撤回錯誤出貨」的過渡版本，不是長期停留點。**

### 10.4 重新框定：清場是**選配**，不是必需

| | 做法 | 「系統升級檢查」 | 其他 126 個 session |
|---|---|---|---|
| **A** | 升 v0.22.2 + 清 3 列 | ✅ 刪得掉 | ✅ 不受影響（本來就沒 ledger 列） |
| **B** | 升 v0.22.2 不清 | 🔴 刪不掉 | ✅ 不受影響 |
| **C** | **跳過 v0.22.2，等 v0.23.0** | ✅ 降級問題從未發生 | ✅ |

**關鍵事實：受影響的只有 1/127。** 所以「刪不掉」不是全面性問題。

**建議：A**（停機窗口本來就有，順手 3 條 DELETE 零額外成本；不清也不會變糟）。**C 亦合理** —— v0.22.2 的實質內容 = v0.22.0 + 256 檔修正，唯一實質收益是 gateway 開機修正，而該修正會隨 v0.23.0 一起交付；代價是目前尚未被咬到（pod 0 restarts）。

---

## 11. Go-Sign（最終）

---

## 9. n100 實地勘查（2026-10-15，唯讀）

### 9.1 部署現況

```
hermes-agent-86bc5b5899-tkzwx   1/1 Running   0 restarts   6h11m
image : ghcr.io/kuniakil/hermes-agent:v0.22.1
cron  : （無 job）
```

### 9.2 DB 勘查（`/opt/data/state.db`，175MB / 45 張表，唯讀 `mode=ro`）

> 註：`/opt/data/.hermes/state.db`（6MB，8/19 後未更新）是**舊的、非活躍**的；活躍的是 `HERMES_HOME=/opt/data` 底下的 `state.db`。

| 項目 | 值 |
|---|---|
| `sessions` | **127** |
| `messages` | **17,657** |
| `journal_mode` | `wal`（FK 檢查在 app 連線上為 `ON`，`hermes_state.py:806`） |
| 24h 內新 session | **0** |
| 24h 內訊息 | 25（**全部落在同一個 session**） |
| 最後一則訊息 | 2026-10-15 14:48 |

**→ 判定：閒置，可安全停機。**

### 9.3 🔑 FK 阻擋範圍（推翻初版風險評估）

| 表 | 列數 | 狀態 |
|---|---|---|
| `session_admissions` | **3** | 全部 `terminal` / `completed` ✅ **零 pending** |
| `worker_executions` | **0** | 空 |
| `worker_receipts` | **0** | 空 |
| `runtime_epoch` | 1 | 無害 |

```
FK 阻擋的 session：1 / 127
```

**被擋的那 1 個：**

```
id       : 20260708_133022_65a00a95
title    : 系統升級檢查
started  : 2026-07-08 13:30（已跑 3 個月）
messages : 實際 5,753 則（宣告 318 → 壓縮過多次）← 全庫最大，佔 33%
last     : 2026-10-15 14:48（今天，唯一活躍的那個）
admission: 3 條，全為 Telegram `native_text_v1` 事件封裝，outcome=completed
```

其餘 126 個 session：24h 內 **0 活動**，最大的一個也只有 316 則。

### 9.4 向後相容性驗證（回滾不會壞）

| 檢查 | 結果 |
|---|---|
| `hermes_state_schema.py` v0.22.1 vs v0.22.2 | blob **位元組相同**（`bf32e8ab7d`） |
| v0.22.1 專屬欄位（`runtime_generation` / `handoff_state` / `auto_archived`） | v0.22.2 **不引用**，但 DB 裡會殘留 → v0.22.2 的 3 處 `SELECT * FROM sessions` 全包在 `dict(row)` 內（`api_server.py:3179`、`hermes_state_compression.py:817`、`profile_repair.py:185`）→ **多餘欄位無害**，只是永遠 NULL |
| v0.22.2 的 `INSERT INTO sessions` | 只插自己知道的欄位子集，不會引用不存在的欄位 → 正常 |
| `Dockerfile` blob v0.22.1 vs v0.22.2 | **位元組相同**（`e3d11031c8`）→ 8 處自訂補丁零衝突 |
| `docker/stage2-hook.sh` blob | **位元組相同**（`48eb36f5a9`） |
| `pyproject.toml` / `uv.lock` / `pm/lock.json` | 零 diff |
| config `_config_version: 51` vs v0.22.2 最高階梯 50 | 不崩、不改寫（migration 只往前跑）；`sessions.auto_prune: false`（config.yaml:507）不受影響 |

### 9.5 「損失」澄清

> 使用者原判斷「損失只有今天那一個提示詞 + 一組回覆」。**實測後：連這個損失都不存在。**
>
> - `messages` 表不動 → 17,657 則訊息（含今天那 25 則）全部保留，升級後可讀、可繼續在同一 session 對話
> - `sessions` 表不動 → 127 個 session 全數保留
> - 真正改變的只有：**v0.22.1 的 canonical/worker 機制不再管理那個 session**（我們只有 Telegram 單一入口，本來就沒用到該機制）
>
> → **資料損失 = 0。**