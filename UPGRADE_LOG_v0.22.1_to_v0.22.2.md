# 升級紀錄：v0.22.1 → v0.22.2

- **日期**：2026-10-15
- **分支**：`my-config-v0.22.2`
- **官方 tag**：`v0.22.2` = `d923a5eb48`（merge of `release/0.22.1` + published `v0.22.1`）
- **最終 HEAD**：`26575c8a212270c35468c24bf4ed7e6696bdb2aa`
- **Image**：`ghcr.io/kuniakil/hermes-agent:v0.22.2`
- **Digest**：`sha256:7da703c77cba55ff337dc1c374fc780c1414b6a457de21e08f0b7fd33546debc`
- **GH Actions Run**：**38729951089**（prepare / linux-amd64 / linux-arm64 / merge 全部 success）
- **部署**：n100 / K3s，`newTag: v0.22.2`，rollout successfully rolled out，**0 restarts**
- **工作表**：`docs/worksheet-upgrade-hermes-v0.22.2-20261015.md`

---

## 1. 這不是升級，是回滾

官方 Release Notes 明言：

> **v0.22.1 was built from the wrong commit. It shipped unreleased gateway work**… 0.22.2 is the release 0.22.1 was meant to be.
> Known issue: Sessions that ran under the 0.22.1 gateway can't be deleted in 0.22.2.

拓撲證據（`d923a5eb48` 的第二父節點就是 `v0.22.1`）：

| 比較基準 | 檔案 | +/− | 意義 |
|---|---|---|---|
| v0.22.0 → v0.22.1 | 2,170 | +190,328 / −49,590 | v0.22.1 = session-authority 大重構 |
| v0.22.1 → v0.22.2 | 2,041 | +50,567 / **−185,914** | 整批回滾該重構 |
| **v0.22.0 → v0.22.2** | **256** | **+7,045 / −1,654** | **v0.22.2 的真實內容增量** |

**`v0.22.2 ≈ v0.22.0 + 256 檔修正`。**

---

## 2. 「刪不掉」的真正機制（三層阻擋，全部由 v0.22.1 留下）

```
① hermes_state_common.py (v0.22.1)
   CREATE TABLE session_admissions (... REFERENCES sessions(id) ON DELETE RESTRICT)
   CREATE TABLE worker_executions  (... REFERENCES sessions(id) ON DELETE RESTRICT)
   CREATE TABLE worker_receipts    (... REFERENCES worker_executions ON DELETE RESTRICT)

② hermes_state_mutation_retirement.py（僅 v0.22.1 存在）
   delete_session() 先清 worker_receipts / worker_executions / session_admissions，才刪 sessions

③ hermes_state_common.py (v0.22.1) 建立 trigger，v0.22.2 程式碼移除但 DB 中的 trigger 留存
   CREATE TRIGGER sessions_runtime_ledger_delete_guard
   BEFORE DELETE ON sessions
   WHEN EXISTS(... session_admissions ...) OR EXISTS(... worker_executions ...)
   BEGIN SELECT RAISE(ABORT, 'Refused to delete a session that has gateway runtime history: ...'); END
```

`hermes_state.py:806` 兩版都是 `PRAGMA foreign_keys=ON` → 阻擋是真的生效。

---

## 3. 官方對「降級」的正式立場

`hermes_cli/update_downgrade_guard.py`（存在於 `main`，v0.22.2 無此檔）：

> Releases before the gateway cutover know nothing of the runtime ledgers … and stamp the same
> `schema_version`, so moving the code back under a store that holds ledger rows leaves every session
> with that history undeletable there. **Downgrading is unsupported**: the update refuses before
> anything moves.

官方文件 `getting-started/updating`：

> `hermes update` refuses a pre-gateway-runtime target … A manual checkout of an old release also
> cannot delete or prune sessions with gateway history—it fails with:
> **`Refused to delete a session that has gateway runtime history`**
> **Supported recovery:** restore a coherent pre-update state (`hermes gateway stop` → 舊版 → `/snapshot restore <id>` 或 `hermes import <backup.zip>`)

**結論：這不是待修的 bug，是刻意設計的護欄。v0.22.2 上永遠不會修；v0.23.0 (`main`) 會把整套機制重新上架，屆時自動恢復。**

---

## 4. 我們的實測與處置

### 4.1 升級前勘查（唯讀）

```
sessions 127 / messages 17,657 / 45 張表 / state.db 175MB
session_admissions : 3 列，全 terminal/completed（零 pending）
worker_executions  : 0 列
worker_receipts    : 0 列
FK 阻擋的 session  : 1 / 127  ← 只有「系統升級檢查」(20260708_133022_65a00a95, 5,753 則訊息)
```

→ **風險由初版的 🔴 高下修為 🟢 低**：零 pending 代表清場零資料損失。

### 4.2 處置：備份 → 升級 → 清場

1. `sqlite3` online backup API 產生單一一致檔案 → `integrity_check = ok` → 拉回本機
   - `~/kubernetes/hermes/backups/20261015/state.db`（175,075,328 bytes, sha256 `3826940bff2bcf811eb3a3911c4f3406…`）
2. 建分支 + purge 54 → 1 workflows + cherry-pick 5 個自訂 commit（**全部零衝突**，因 Dockerfile blob 位元組相同）
3. push → dispatch `ghcr-publish.yml`（input **`tag_name`**，非 `tag`）→ Run 38729951089
4. `kubectl apply -k` → rollout success
5. **清場**（在 v0.22.2 上做，該版本無 ledger 寫入者）：
   ```sql
   DELETE FROM session_admissions;              -- 3 列，全 terminal
   DELETE FROM worker_executions;               -- 0 列
   DELETE FROM worker_receipts;                 -- 0 列
   ```
   → `FK-blocked: 1 → 0`，`messages: 17,657 → 17,657 不變`，`integrity_check = ok`

### 4.3 清場前後的一個重要發現

第一次驗證刪除時**仍然失敗**，但**不是 ledger 的問題** —— 漏了 app 實際會做的
`UPDATE sessions SET parent_session_id = NULL WHERE parent_session_id = ?`（該 session 有 1 個子 session `20260726_222217_5eedd5`，`sessions.parent_session_id` 是 `ON DELETE NO ACTION`）。

補上 orphan 步驟後刪除成功（rowcount=1，隨後 rollback）。這是**測試腳本的缺陷，不是產品缺陷** —— app 的 `delete_session()` 本來就有這一步。

---

## 5. 驗證結果

| # | 項目 | 結果 |
|---|---|---|
| D1 | kustomization `newTag` | `v0.22.2` ✅ |
| D2 | rollout | successfully rolled out，**0 restarts** ✅ |
| D3 | `sessions.auto_prune: false`（config.yaml:507） | 保留 ✅（`_config_version: 51` > v0.22.2 最高階梯 50 → 不會有任何 migration 執行，預期行為） |
| D4 | 自訂層冒煙 | locale 4 / sshd / rsync / tini / ffmpeg / agent-browser / edge_tts / firecrawl / lark_oapi / dingtalk **全部 OK** ✅ |
| D5 | 資料完整性 | sessions **127 → 127**、messages **17,657 → 17,657**、integrity ok ✅ |
| D6 | 已知 issue | 清場後 FK-blocked **1 → 0**，「系統升級檢查」實測可刪 ✅ |
| D8 | **Gateway 重啟修正（本次頭條）** | 刪 pod 強制重啟 → `Gateway running with 2 platform(s)`、Telegram 3 個 scope 註冊成功、cron tick、kanban dispatcher 就位、**本次開機後 0 ERROR** ✅ |
| D9 | 殘留 ledger 表 | `session_admissions` / `worker_executions` / `worker_receipts` **清空但保留**、`runtime_epoch` 1 列保留（不 DROP，留作回滾證據） |

> `sessions_runtime_ledger_delete_guard` trigger **仍留在 DB 中但已失效**（其 `WHEN` 子句查的兩張表都空了 → 恆為 FALSE）。這是安全的：未來升到 v0.23 時該 trigger 會重新生效，而那時正好是有需要的。

---

## 6. 相容性驗證（回滾沒有破壞任何東西）

| 檢查 | 結果 |
|---|---|
| `hermes_state_schema.py` v0.22.1 vs v0.22.2 | blob 位元組相同（`bf32e8ab7d`） |
| v0.22.1 專屬欄位（`runtime_generation` / `handoff_state` / `auto_archived`） | v0.22.2 不引用，但殘留無害 —— 3 處 `SELECT * FROM sessions` 全包在 `dict(row)` 內（`api_server.py:3179`、`hermes_state_compression.py:817`、`profile_repair.py:185`） |
| `Dockerfile` blob v0.22.1 vs v0.22.2 | 位元組相同（`e3d11031c8`）→ 8 處自訂補丁零衝突 |
| `docker/stage2-hook.sh` | 位元組相同（`48eb36f5a9`） |
| `pyproject.toml` / `uv.lock` / `pm/lock.json` | 零 diff |
| 5 個關鍵檔案 blob 對比（entrypoint-ssh / stage2-hook / docker-compose / AGENTS.md / ghcr-publish.yml） | **5/5 SAME** |

---

## 7. Post-mortem

### 做對的
1. **先勘查再規劃** —— 用唯讀 SQL 實測把「🔴 高風險」降為「🟢 低風險」。若照 release notes 字面判定，很可能因為「session 刪不掉」而放棄升級。
2. **沒有把官方 v0.22.1 的 tag 當基線** —— 用 `upstream-v0.22.2` 獨立 ref，diff 面積準確。
3. **清場順序正確** —— 先升級再清。v0.22.1 活著時清會被 gateway 重新寫入。
4. **備份用 SQLite online backup API** —— 產生單一一致檔案，可立即用 SQL 驗證，不受 WAL 分檔影響。

### 學到的
1. **「刪不掉」有三層，不只一層。** 官方文件只講 ledger 的 `ON DELETE RESTRICT`，實際 DB 裡還留著一個 `RAISE(ABORT)` trigger。清空 ledger 後 trigger 自動失效，但**若只清 ledger 不看 trigger，會誤判為沒修好**。
2. **TRUNCATE 全部是危險的。** `queued`/`started`/`unknown` 代表未處理完的輸入。我們剛好是 0，但若之後有人在 pending 期間升級，直接 TRUNCATE 就真的會丟訊息。**清場 SQL 必須帶 `status!='terminal'` 的保護檢查**（已寫進腳本）。
3. **降級不是「壞掉」，是官方明文拒絕的操作。** 官方寧可在 `hermes update` 事前擋下來，也不讓你降級進壞狀態。判斷降級風險時應先讀 `update_downgrade_guard.py`，不要只看 release notes 的 Known issue。
4. **v0.22.2 是過渡版本。** 官方說「只在 main 上的工作隨 v0.23.0 出貨」→ 下次規劃應以 `main` 的實際內容為準，而不是假設 v0.22.x 是穩定線。
5. **驗證腳本本身也要驗證。** 第一次刪除測試失敗，是因為腳本漏了 `UPDATE sessions SET parent_session_id = NULL`。app 的 `delete_session()` 有這步，手寫的驗證沒有。**驗證失敗時先懷疑驗證腳本。**

### 殘留事項
- [ ] `sessions_runtime_ledger_delete_guard` trigger 保留在 DB（已失效）。升 v0.23 後會重新生效，屆時是正確行為。
- [ ] 殘留空表 `session_admissions` / `worker_executions` / `worker_receipts` + `runtime_epoch`(1 列)。不 DROP，留作回滾證據；若未來要清理，先確認已升 v0.23。
- [ ] 本機 `.env` 的 `HERMES_IMAGE` 仍為舊值（k8s 走 `newTag` 不受影響，Mac 本機 `docker compose` 才用得到）。

---

## 8. ⚠️ 附錄：trigger 清理的危險性（2026-10-15 追加）

### 8.1 事件

升級後的系統檢查回報「**3 個 trigger 殘留（已失效）**」——**這是錯的**。實際只有 **1 個**。

```
trigger 總數：12
  messages 表：11 個 → messages_fts_insert / _delete / _update / _trigram_*
                        / messages_message_uid_insert
                        （全文檢索索引維護用，**pre-existing，非殘留，運作中**）
  sessions  表： 1 個 → sessions_runtime_ledger_delete_guard
                        （**唯一**的 v0.22.1 殘留，因 ledger 表已空而失效）
```

「3 個」這個數字推測是把「**3 張** ledger 表」（`session_admissions` / `worker_executions` / `worker_receipts`）與 trigger 混淆了 —— 兩者都是 3，極易誤記。

### 8.2 為什麼這個誤判有實際風險

若照「殘留 trigger 已失效，可以清理」的理解去 `DROP TRIGGER`：

> **會直接破壞全文檢索功能**（`hermes sessions search` / session 搜尋失效）。

驗證基準（可隨時複查）：

```sql
-- messages_fts 列數應與 messages 完全一致；不一致代表 FTS trigger 被破壞
SELECT (SELECT COUNT(*) FROM messages_fts) AS fts,
       (SELECT COUNT(*) FROM messages)     AS msgs;
-- 本次實測：17667 / 17667 ✅
```

### 8.3 正確的清理判準

| trigger | 處置 |
|---|---|
| `messages_*`（11 個，FTS 維護） | 🚫 **絕對不可動**。它們是搜尋功能的運作前提，不是殘留 |
| `sessions_runtime_ledger_delete_guard` | 🟡 可留可棄。當前失效（`WHEN` 查的兩張表已空）；升 v0.23 後該機制會回來，這個 trigger 會**重新生效且是正確行為**，屆時不應再手動刪 |

### 8.4 方法論教訓

> **判斷「殘留物件」時，必須先回答兩個問題：(1) 它是本次改動產生的，還是本来就存在？(2) 它現在有沒有在做事？**
>
> 本次兩個問題的答案都是「不是 / 有」，但只看 trigger 名稱和數量就下「已失效可清理」的結論，是危險的。
> 未來清 DB 殘留物時，先跑上面那條 `messages_fts` 對帳 SQL 作為基準線。