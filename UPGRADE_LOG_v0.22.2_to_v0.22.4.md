# 升級紀錄：v0.22.2 → v0.22.4

- **日期**：2026-10-22
- **分支**：`my-config-v0.22.4`
- **官方 tag**：`v0.22.4` = `4d04303818`（含 `v0.22.3` = `5b147ab036`，後者已被前者包含）
- **Image**：`ghcr.io/kuniakil/hermes-agent:v0.22.4`
- **Manifest digest**：`sha256:079618425a6ded8c63b7733c8bf848087eeb3eb4efe5120be5e7547c88b25d1c`
  - linux/amd64：`sha256:e6c235ded5d66fe6b5d5515658bfcc90173a2d2411c5f08241b6714d4d212ec5`
  - linux/arm64：`sha256:312022a41c5db4db4fc0daf6766fa4528bd14c702ba74505c92af100139b1897`
- **GH Actions Run**：**39733973873**（prepare / linux-amd64 / linux-arm64 / merge 全部 success）
- **部署**：n100 / K3s，`newTag: v0.22.4`，rollout successfully rolled out，**0 restarts**（強制刪 pod 重啟後仍 0）
- **備份**：`~/backups/hermes-20261022/state.db`（175,075,328 bytes，`PRAGMA integrity_check = ok`）
  - 🔴 **已於 2026-10-24 14:21 刪除**（使用者明確指示；由 `~/backups/hermes-20261024/` 取代）。見本文 §9 與 §10.1 的刪除標記。
  - ⚠️ 這是**升級前**的快照（`schema_version = 31`、ledger 為空、messages 17,671），**正是回滾到 v0.22.2 image 所需的正確產物**
- **工作表**：`docs/worksheet-upgrade-hermes-v0.22.4-20261022.md`

---

## 1. 這次的本質：620 PR 的巨型收斂版（官方沒給人讀版說明）

| 比較基準 | 檔案 | +/− | 意義 |
|---|---|---|---|
| v0.22.2 → v0.22.3 | 4,206 | +360,278 / −64,308 | **約 620 個 PR 的收斂** |
| v0.22.3 → v0.22.4 | 82 | +1,475 / −3,022 | 純 patch（Desktop / plugin / dashboard） |
| **v0.22.2 → v0.22.4** | **4,242** | **+361,206 / −66,783** | **本次實際升級幅度** |

官方 v0.22.3 Release Notes 原文：

> This tag rolls up the ~620 PRs merged since v0.22.2… **Full curated release notes for this window ship with v0.23.0.**

→ **v0.22.3/v0.22.4 沒有 curated release notes**，本次的所有行為變更盤點都是我們自己從 diff 做的（見工作表 §2）。

拓撲已驗證（`git merge-base --is-ancestor`）：`v0.22.2 → v0.22.3 → v0.22.4` 為直線 → **跳版安全**。

---

## 2. 最重要的一件事：gateway runtime ledger 機制「正確版」回來了

v0.22.2 是官方為撤回錯誤出貨的 v0.22.1 而做的**臨時回滾版**。v0.22.4 把整套 gateway runtime 以修正版重新落地：

| 項目 | v0.22.2 | v0.22.4 |
|---|---|---|
| `SCHEMA_VERSION` | 31 | **32** |
| `session_admissions` / `worker_executions` / `worker_receipts` / `runtime_epoch` | 表殘留、無人寫入 | **重新寫入 + 有刪除路徑** |
| 18 個 ledger 模組（`hermes_state_mutation_retirement.py` 等） | ❌ 不存在 | ✅ **全部回來** |
| `sessions_runtime_ledger_delete_guard` trigger | ❌ 不存在 | ✅ **新增** |
| `sessions.transcript_revision` | ❌ | ✅ 新增欄位 |

### 2.1 好消息：v0.22.2 的「session 刪不掉」問題**已消失**（實測）

```
hermes sessions delete --yes local-6c0ff960080d9e27f54a88c21ed87ed004f39a24b28d60ea8867898bb5ed5bd2
→ Deleted session 'local-6c0ff960080d9e27f54a88c21ed87ed004f39a24b28d60ea8867898bb5ed5bd2'.
```

實測數據（該 session 帶 1 條 terminal ledger 列）：

| 指標 | 刪除前 | 刪除後 |
|---|---|---|
| `sessions` | 128 | **127** ✅ |
| `messages` | 17,673 | **17,671** ✅（回到基線） |
| `session_admissions` | 1 | **0** ✅（先清 ledger 再刪 session） |
| `worker_executions` | 0 | 0 |
| `PRAGMA integrity_check` | ok | **ok** |

→ **v0.22.4 的刪除路徑會先 retire ledger 列**，官方那個護欄不再阻擋正常刪除。

### 2.2 壞消息：**回滾變成單向**

v0.22.4 一旦跑起來就會重新寫入 `session_admissions`。此時若把 image 退回 v0.22.2：

* v0.22.2 看不懂 ledger → 帶 ledger 歷史的 session **刪不掉**（v0.22.2 的限制復發）；
* 而且 `sessions_runtime_ledger_delete_guard` trigger 會被觸發並直接 `RAISE(ABORT, 'Refused to delete a session that has gateway runtime history: … Downgrading is unsupported.')`。

> **結論：本次備份是 MANDATORY，且升級後若要回退，必須用備份 DB，不能只換 image。**
> 備份位置：`~/backups/hermes-20261022/state.db`（175MB，integrity ok）。
> 🔴 **該備份已於 2026-10-24 14:21 刪除**（使用者明確指示；由 `~/backups/hermes-20261024/` 取代）。

---

## 3. Schema 判定：additive + idempotent，無人工遷移

官方原始碼註解（`hermes_state_common.py` v0.22.4）：

> `v32 (#140315): no data migration. … its catch-up is the declarative executescript(SCHEMA_SQL) + _reconcile_columns() every writable open already runs (additive, idempotent). The bump only records that the declared shape changed; a new table or column needs no bump.`

**實測**（部署後唯讀查詢）：

```
schema_version table                    : 32        ← 31 → 32（宣告形狀變更，無資料遷移）
sessions.transcript_revision            : present
session_turn_leases / session_model_usage / async_delegations : present
sessions_runtime_ledger_delete_guard    : present（新增 trigger）
messages_transcript_revision_update     : present（新增 trigger）
sessions / messages                     : 127 / 17,671（與升級前完全一致）
PRAGMA integrity_check                  : ok
```

**config**：`v0.22.4` 的 migration 階梯最高 = **51**，我們的 `_config_version` = **51** → **不會有任何 migration 執行**（與 v0.22.2 時的情況相同）。`sessions.auto_prune: false` 未被改動。

---

## 4. 自訂層驗證（8 處補丁全部存活）

上游 `Dockerfile` blob 在 v0.22.2 / v0.22.3 / v0.22.4 **位元組相同**（`e3d11031c8`）→ 8 個 hunk 零衝突、原樣套用。

| 檢查 | 結果 |
|---|---|
| `git diff upstream-v0.22.4 HEAD -- Dockerfile \| grep -c '^@@'` | **8** ✅ |
| apt：`openssh-server` `rsync` `locales` | ✅ |
| `locale -a` | `C.utf8` / `en_US.utf8` / `zh_TW.utf8` ✅ |
| `ssh-keygen -A` + `/run/sshd` + sshd + rsync + tini | ✅ |
| `useradd -s /bin/bash hermes` | ✅ |
| `agent-browser`（pm ensure + symlink） | ✅ `/usr/local/bin/agent-browser` |
| extras：`edge-tts` `firecrawl` `dingtalk` `feishu` `exa` | ✅ 全部可 import |
| `ENV HOME=/opt/data` + `/tmp/.npm-cache` (1777) + `/root/.npm` chown | ✅ |
| `docker/entrypoint-ssh.sh`（Zeabur shim） | ✅ blob 與 v0.22.2 分支相同 |
| 上游 `--cache /opt/hermes/uv-cache` / `--record-selection` | ✅ 保留 |

**依賴面**：

| 項目 | 結果 |
|---|---|
| Python | 3.14.7（`requires-python >=3.11,<3.15` 不變） |
| `ruamel.yaml.clib` 0.2.15 | ✅ cp314 wheel 已安裝（`_ruamel_yaml.cpython-314-x86_64-linux-gnu.so`），`from _ruamel_yaml import CParser` 成功 → **官方想要的 YAML C 加速有生效** |
| `PyJWT` 2.15.1 / `urllib3` 2.8.0 | ✅ 依 v0.22.4 lockfile |
| `pm/lock.json` | 僅 llamacpp b11370→b11671（本機模型 runtime，**我們不用**） |

---

## 5. Gateway 開機驗證（本次重點）

v0.22.4 重寫了 `gateway/status.py`（185 行）並新增 `status_lock_dir.py` / `status_scoped_locks.py` / `session_worker_*.py`；v0.22.3/4 另有多筆 gateway ownership / startup stamp / restart-loop 修補。我們是 supervised（K3s pod）部署，直接命中這條路徑。

**實測**：刪 pod 強制重啟 →

```
hermes-agent-5656b5d479-6rnjx   1/1 Running   0 restarts
14:57:41  Turn machinery warmed in 1.7s
14:57:51  ✓ telegram connected
14:57:52  Gateway running with 2 platform(s)
```

啟動後 60 秒複查：**restarts = 0、ready = true**，**0 條 ERROR level、0 條 Traceback**（自 14:31 升級後）。

> 舊 log 裡的 Traceback 全部是歷史（2026-05-31 / 2026-06-23），與本次升級無關。

---

## 6. FTS：我們的 DB 停在舊 layout，本次維持 opt-in

生產 DB 實測（升級前後一致）：

```
messages_fts          :: CREATE VIRTUAL TABLE messages_fts USING fts5( content )          ← 舊 layout
messages_fts_trigram  :: CREATE VIRTUAL TABLE messages_fts_trigram USING fts5( content, tokenize='trigram' )
state_meta.fts_optimize_available = 1
state_meta.fts_storage_version      = （仍不存在）
```

| 判定 | 說明 |
|---|---|
| 🟢 **升級時沒有自動重建** | v0.22.4 的 `base_index_realigned_on_open()` 要求 base index 含 `tool_name`；我們的沒有 → 不是 on-open realign |
| 🟡 **會被 doctor / 更新提示標記為 drift** | v0.22.4 新增 layout registry 與結構化偵測，讓既有狀態「被看見」 |
| ℹ️ **這不是本次造成的** | v0.22.2 時代 `fts_optimize_available=1` 就已存在（`state_meta` 早就有） |

**決策**：本次**不執行** `hermes sessions optimize-storage`（175MB / 17,671 則，重建需停機且會改寫索引）→ 另開專案處理。

---

## 7. npm 漏洞：維持「不修」

| 檢查 | 結果（2026-10-22） |
|---|---|
| 根 `package-lock.json` `overrides` v0.22.2 → v0.22.4 | 皆為空 → 前提成立 |
| 觸發條件 issue | **#133435 OPEN、#132924 OPEN、#79021 OPEN** → 條件**未成立** |
| 上游自行修掉的部分 | `photon/sidecar` 新增 `overrides: undici 7.30.0` ✅ |
| 我們的 runtime 暴露面 | photon sidecar 未啟用、Electron desktop 不部署 → **= 0** |
| `hermes doctor` | 報 `web workspace 4`、`ui-tui workspace 3` 個 npm 漏洞（與 v0.22.0 實測的 28 個 real advisories 同源，仍是 build-time/devDependency 為主） |

---

## 8. Post-mortem

### 8.1 教訓

1. **官方會把 curated release notes 攤延到下一個大版本**。v0.22.3 = 620 PR 的收斂版，卻沒有任何「人讀版变更說明」→ 遇到這種 tag，**盤點成本要自己吸收**，不要等官方。
2. **「回滾版」不是終點**。v0.22.2 是臨時回滾、v0.22.4 才把整套機制以正確版落地；我們跟著官方走，兩次都是對的。
3. **ledger 機制是有方向性的**：一旦新版寫入 ledger，往回退會被 trigger 阻擋 → **每次跨 ledger 世代的升級，備份是 MANDATORY 而不是可選**。
4. **`hermes doctor` 的 npm 檢查不可信**（容器內 web / ui-tui 沒 node_modules → audit 對空樹回 0）；真實數字要用 `npm audit --package-lock-only`。延續 v0.22.0 的結論。
5. **FTS layout drift 是長期既有狀態**，官方加了偵測只是讓它變得可見；不要在升級窗口順手修（風險 >> 收益）。
6. `kubectl cp` 在本機對 175MB 檔案會 `unexpected EOF`（tar 問題）→ 改用 `kubectl exec -- cat > local`，並在 pod 內用 Python `sqlite3.Connection.backup()` 做**一致快照**（含 WAL 內容），再用 `PRAGMA integrity_check` 驗證。

### 8.2 本次沒有發生的事（記錄以免下次誤判）

* 沒有資料損失：`sessions` 127 / `messages` 17,671 升級前後一致（且測試 session 刪除後回到基線）。
* 沒有 config migration 執行（stamp 51 = 階梯上限）。
* 沒有 FTS 自動重建。
* 沒有 ERROR / Traceback。
* 沒有 restart loop。

---

## 9. 尚未完成（需使用者參與）

- [x] **真實 Telegram 訊息往返**（D12）：✅ **已確認**（部署後 `session_admissions` 有 Telegram 實際往來記錄，2026-10-22 07:05 UTC 與 07:34 UTC，部署時間 06:31 UTC）。
- [x] **備份處置**：`~/backups/hermes-20261022/`（175MB）— ✅ **已於 2026-10-24 14:21 刪除**（使用者明確指示）。
      取代者：`~/backups/hermes-20261024/`（schema 32，v0.22.5 升級前快照）。
      刪除依據：v0.22.4 → v0.22.5 的 schema **未變**（32→32），退回 v0.22.4 image **不依賴任何 DB 備份**，
      且本次 schema 未變 → v0.22.5 也不需要舊的 schema 31 快照。

---

## 10. 復原（回滾）程序

### 10.1 備份盤點（2026-10-22 全機掃描結果）

| 路徑 | 來源 | schema | sessions | messages | `session_admissions` | integrity | 用途 |
|---|---|---|---|---|---|---|---|
| `~/backups/hermes-20261022/state.db` | **本次升級前快照**（2026-10-22 14:12） | **31** | 127 | **17,671** | **0** | ok | 🔴 **已於 2026-10-24 14:21 刪除**（使用者明確指示；由 `~/backups/hermes-20261024/` 取代） |
| `~/kubernetes/hermes/backups/20261015/state.db` | **上次升級（v0.22.1→v0.22.2）殘留**，2026-10-15 19:47 | 31 | 127 | 17,657 | **3** | ok | ⚠️ v0.22.1 殘留 ledger（清場前）；**帶它回滾會讓「session 刪不掉」限制復發** |
| `~/kubernetes/hermes/backups/` | 被 `~/kubernetes/.gitignore` 的 `backups/` 規則排除 | — | — | — | — | — | 未進 git ✅ |
| `/opt/data/backups/config/`（pod 內） | 2026-10-15 的 **config** 備份（184K） | — | — | — | — | — | 非 DB 備份 |
| `/opt/data/.curator_backups/blobs`（pod 內） | skills curator 備份 | — | — | — | — | — | 非 DB 備份 |
| `~/hermes/data/state.db` | **本機開發用 live DB**（非備份） | — | — | — | — | — | — |
| n100 主機 `/data/services/hermes/` | — | — | — | — | — | — | **無任何 DB 備份**（SSH 使用者無權限讀寫該目錄，歷次升級皆走 `kubectl exec -- cat`） |

> **兩個 DB 備份不可互換**：schema 相同但 ledger 狀態不同。本次備份（ledger 空）才是能配 v0.22.2 image 的那份。

### 10.2 回滾步驟（若必須退回 v0.22.2 image）

1. `kubectl apply -k ~/kubernetes/hermes/overlays/n100`（把 `newTag` 改回 `v0.22.2`）；
2. **必須同時用備份 DB 還原** `/opt/data/state.db`：
   - 🔴 `~/backups/hermes-20261022/state.db` **已於 2026-10-24 刪除**；
     若仍需退回 v0.22.2，請改用 `~/backups/hermes-20261024/state.db`（schema 32、ledger 為當前版本形態），
     或就地重新做一次升級前快照（`sqlite3.Connection.backup()` + `kubectl exec -- cat`）。
   - **不要**用 20261015 那份（帶著 3 列 v0.22.1 殘留 ledger）：
     否則帶 ledger 歷史的 session 會被 `sessions_runtime_ledger_delete_guard` 阻擋而刪不掉
     （v0.22.4 已在 `session_admissions` 寫入新列）；
3. 官方文件建議的正規路徑是 `hermes update --backup` + `/snapshot restore <id>` 或 `hermes import <backup.zip>`。

---

## 11. 升級後複查（2026-10-22 15:20，逐項獨立驗證）

由 Hermes Agent 自行做了一次全面檢查，逐項覆核結果如下（**以程式碼與 DB 實測為準**）。

### 11.1 覆核通過（獨立實測一致）

| 項目 | 報告值 | 實測值 | 判定 |
|---|---|---|---|
| 版本 | v0.22.4 (upstream 621915ab) | 同 | ✅ |
| `sessions` | 127 | 127 | ✅ |
| `messages` | 17,678 | **17,686**（持續增加） | ✅ |
| `integrity_check` | ok | ok | ✅ |
| `messages_fts` | = messages | **17,686 = 17,686** | ✅ |
| `messages_fts_trigram` | 未檢 | **17,686 = 17,686** | ✅ |
| triggers | 13（messages 12 + sessions 1） | **完全一致** | ✅ |
| `worker_executions` / `worker_receipts` | 0 / 0 | 0 / 0 | ✅ |
| config | v51 | 51 | ✅ |
| `state.db` 大小 | — | 175.1 MB（與升級前持平） | ✅ |
| cron jobs | 無 | 無 | ✅ |
| npm audit | 24（2c/5h/9m/8l） | **24（2 critical / 5 high / 9 moderate / 8 low）完全一致** | ✅ 決策不變 |

### 11.2 需要修正的三點

1. **「Uptime 17 天 15 小時」是 host（n100）的 uptime，不是 pod**。pod 起於 2026-10-22 14:57:23 CST（本次升級驗 gateway 開機時主動刪除重建），檢查時僅 ~21 分鐘，**0 restarts**。不可引用為「新版已穩定運行」的證據。
2. **「今日 6 個 ERROR」的時間歸屬**：嚴格以 ERROR level 切分 → **部署前（<14:31，舊 v0.22.2 pod）5 筆**（06:14 ×2 Telegram adapter rebuild、09:11:48、09:12:09、09:12:39）、**部署後（≥14:57，新 pod）僅 1 筆**（15:05:50 MiniMax 529 overloaded_error）。報告中的 09:11/09:12 在 `gateway.log` 是 WARNING、在 telegram.ext 自己的 logger 才是 ERROR（同一事件、不同檔案、不同 level）。**「非本地邏輯錯誤」的判斷方向正確，但應改述為「升級後只有 1 筆 ERROR，且是上游 529」。**
3. **「v0.22.4 改了 session_admissions 的 schema，跟 v0.22.1 結構不同」→ 事實錯誤**：v0.22.1（`297552a9d6`）與 v0.22.4 的 `session_admissions` DDL **逐字相同**（欄位一直是 `target_session_id`，從無 `session_id`）。報告中的 `no such column: session_id` 是查詢用錯欄位名，不是 schema 差異。結論（新 runtime 寫入）仍成立，理由不成立。

### 11.3 已被證偽的擔心：「session_admissions 又有 1 筆 → 下次刪 session 可能又被擋」

**不會發生。程式碼與實測雙重證據：**

* **程式碼**：`retire_sessions()` → `retire_terminal_receipts()` 在刪 session **之前**執行
  `DELETE FROM session_admissions WHERE target_session_id=?` 與 `DELETE FROM worker_executions WHERE session_id=?`。
  所有刪除路徑都走它：`delete_in_transaction`（`hermes sessions delete`）、`prune_sessions`、
  `prune_empty_ghost_sessions`、auto-prune（→ `retire_prunable` → `retire_sessions`）。
  `sessions_runtime_ledger_delete_guard` 只在 ledger 列仍存在時 abort —— 那只發生在**降級到 v0.22.2 或更舊**。
* **實測**：升級當天即建立一個帶 1 筆 terminal admission 的 session 並 `hermes sessions delete --yes` 成功，
  `session_admissions` 1→0、`sessions` 128→127、`messages` 回到 17,671、`integrity_check: ok`，
  `state_meta` 留下 `gateway.retired_session.v1.local-6c0ff…` 標記（證明完整柵欄有發布）。
* 現存那 1 筆：`target_session_id=20260708_133022_65a00a95`、**status=terminal / outcome=completed**、
  intent=queue、principal=telegram、seq=5 → 屬可正常 retire 的完成態 admission，**不是阻塞態**。
* 邊界情況：session 有未完成工作（admission status = queued/started/unknown）時，explicit delete 拋
  `session_busy`（人話錯誤）、prune 直接跳過該 session —— 都不是「無提示被擋」。

→ **不需要再清 ledger，也不需要「下次觀察」。**

### 11.4 非問題、但列入長期觀察

`state_meta` 的 `gateway.*` key 現有 8 個（5 個 `admission.result` 快取 + `retired_session` 標記 +
`terminal_admission` / `terminal_identity` 標記）。v0.22.4 會持續寫 admission 快取；
目前 `state.db` 175.1MB 與升級前持平，官方有 housekeeping 老化標記 → 長期只需確認 DB 不異常膨脹。
