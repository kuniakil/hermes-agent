# Hermes 升級工作表：v0.23.2 → v0.23.3

- **Fork remote**：`kuniakil`（`kuniakil/hermes-agent`）；**Upstream remote**：`origin`（`NousResearch/hermes-agent`）
- **目前上線**：`v0.23.2`（分支 `my-config-v0.23.2`，HEAD `896c7e859c`）
  - Pod `hermes-agent-5f75cdcbf8-zpngh`｜`1/1 Running`｜`RESTARTS 0`｜IP `10.42.0.209`｜Node `n100`
  - Image `ghcr.io/kuniakil/hermes-agent:v0.23.2`
- **目標**：官方 `v0.23.3`（commit `caafe5389ae585ef77387a962aee05b1bcf17029`，2026-11-19 發布）
- **基線 ref**：`upstream-v0.23.3`（已 fetch，commit `caafe5389`）；`upstream-v0.23.2` = `ae2a81ccc0`
- **發布模型**：分支建置，不推 tag。`ghcr-publish.yml`（dispatch input **`tag_name`**）→ `ghcr.io/kuniakil/hermes-agent:v0.23.3`
- **狀態**：✅ **已上線並驗證完成**（Phase 0–D 全綠；Telegram 往返實測通過；僅 D12 24h 觀察期與 E4 發布待辦）
- **日期**：2026-11-21

---

## 0. ⚠️ 最高優先結論

### 0.1 一句話結論

**`v0.23.3` 名義上是 patch，實際是 1,657 non-merge commits / 3,948 檔 / 370 PRs 的大視窗（完整 curated notes 官方延至 `v0.24.0`）。好消息：DB `SCHEMA_VERSION`（33）、`FTS_STORAGE_VERSION`（3）與 Docker base image **全部未變**，唯一的 schema 變動是 **config `_config_version` 53 → 54**（且僅影響「模板 seeded 的 `prompt_caching.cache_ttl: 5m`」——我們線上是 bare `5m`，屬使用者 pin，遷移會保留，行為不變）。衝突面實測為 **0 個真衝突**（merge-tree 僅 17 個 `.github/workflows/*` modify/delete，全數由既有 purge 機制吸收）。整體風險為 🟢 低–中，仍走標準流程：先備份 `/opt/data` → 建分支 → 移植自訂層 → GHCR 建置 → 滾動上線 → Telegram 往返實測。**

### 0.2 不可逆性判定

| 面向 | v0.23.2 | v0.23.3 | 判定 |
|---|---|---|---|
| DB `SCHEMA_VERSION` | 33 | **33** | ✅ **無不可逆遷移**（定義位置從 `hermes_state_common.py:296` 移到 `persistence/sqlite/_schema_ddl.py:74`） |
| `FTS_STORAGE_VERSION` | 3 | **3** | ✅ 不變 |
| config `_config_version` | 53 | **54** | ⚠️ **會變更**（見 0.3，單向 stamp，可逆性 = 降回 v0.23.2 只會顯示「written by a newer Hermes」提示，**非致命**） |
| base image | `debian:trixie-20261020@sha256:4c25275…` | **同一 digest** | ✅ 不變（上游 `Dockerfile` 在此視窗 **完全未動**） |
| `Dockerfile` / `docker/` / `docker-compose.yml` / `.env.example` | 自訂層 | **上游零改動** | ✅ 與自訂層**零重疊** |
| `pyproject.toml` | — | wheel `include` 新增 `persistence` / `session_rules` | ✅ 打包層面，無行為影響 |

> **不可逆的部分**：只有 `/opt/data/config.yaml` 的 `_config_version: 53 → 54` 這個 stamp。降回 v0.23.2 映像時，`check_config_version()` 會回報「config.yaml is at version 54, written by a newer Hermes (this build knows up to 53). No migration runs on it…」——**只是提示，不會改寫設定、也不會阻擋啟動**。因此回退不需要額外備份 `config.yaml` 以外的東西。

### 0.3 官方 Release Notes（v0.23.3）稽核

- **視窗規模**：`v0.23.2...v0.23.3` 共 **1,657 non-merge commits**（含 merge 1,675）、**3,948 檔**（+222,379 / −96,154）、**370 merged PRs**、60 closed issues。
- **無 Breaking Changes / Deprecations 章節**：官方明言「Full curated release notes for this window ship with v0.24.0」，本視窗功能刻意不展開。→ **風險只能靠 diff 稽核補齊**（見 0.4 與第 2 節）。
- **官方列出的視窗重點**（Release Notes 節錄）：
  - Prompt-cache lifecycle controller：長工具執行中預熱、閒置對話在 1h 快取到期前壓縮、Nous Portal 走完整 1h 生命週期、`prompt_caching.cache_ttl` 預設改 `auto`。
  - 壓縮會封存（archive）它丟棄的 tool results；proactive tool-result prune 預設開啟。
  - 首次執行 CLI 設定改為單一問答流程，含 free tier。
  - OpenRouter / Nous Portal 新增 GPT-6.2 Astra、Sol（+ Pro）。
  - Bot Chat composer 上方新增「Waiting on teammates」狀態條。
  - Linux AppImage agent payload 改由 per-build 穩定副本執行。
  - **storage layer 拆成 persistence 介面 + SQLite backend**。
  - 依賴安全更新（oauthlib、opentelemetry、tornado）。
  - 新增大量 plugin-catalog 条目。

### 0.4 本地實測稽核（diff 挖掘，補足官方未列出的部分）

#### 0.4.1 config schema 遷移 53 → 54（唯一 schema 變動）

`hermes_cli/config_migrations.py` 新增 `_migrate_to_54`：

- 53 → 54：移除 `prompt_caching.cache_ttl: "5m"`，**但只在該行帶有模板 seeded 的行尾註解**（`# use "1h" for long sessions with pauses between turns`）時才移除；其他 `"5m"` 視為使用者 pin → **保留**並印 ℹ 提示。
- **我們線上實測**（`cat -A` 逐位元組確認）：
  ```
  prompt_caching:$
    cache_ttl: 5m$
  ```
  → **bare `5m`、無註解** → 遷移會 **保留**，prompt-cache TTL 維持 5m，**行為零變化**。
- 新安裝（無既有 config）的預設值改為 `prompt_caching.cache_ttl: "auto"`（1h for human-paced / 5m for machine-paced）。我們不是新安裝，不受影響。
- **若想吃到 1h 快取層**：手動刪掉 `/opt/data/config.yaml` 的 `cache_ttl: 5m` 那一行即可（遷移後預設即 `auto`）。→ 見 Q3。

#### 0.4.2 其他 config 預設值變更

| Key | v0.23.2 | v0.23.3 | 對我們的影響 |
|---|---|---|---|
| `prompt_caching.cache_ttl` | `"5m"` | `"auto"` | 無（我們 config 明確 pin `5m`） |
| `codex_request_compression` | — | `True`（新增） | 無（Codex 專用，我們用 MiniMax） |
| `_config_version` | 53 | 54 | 見 0.4.1 |

> compaction / `proactive_prune_tokens` / `micro_compact` 等區塊在本視窗 **完全未變更**（diff 為空）——Release Notes 所述「proactive tool-result prune 預設開啟」指的是 **既有 `proactive_prune_tokens` 區塊之外**的新機制，非預設值翻轉。

#### 0.4.3 `hermes_state_*.py` → `persistence/` + `session_rules/` 重構

- 上游把 68 個扁平 `hermes_state_*.py` 收斂成 **`persistence/`（169 檔）** + **`session_rules/`（18 檔）** + `persistence_assembly.py`，僅留 `hermes_state.py` / `hermes_state_common.py` / `hermes_state_loop_guard.py` / `hermes_state_registry.py`。
- `pyproject.toml` wheel `include` 同步新增 `persistence` / `persistence.*` / `session_rules` / `session_rules.*`。
- **DB 檔案路徑、`SCHEMA_VERSION`(33)、`FTS_STORAGE_VERSION`(3) 皆未變** → 既有 `/opt/data/state.db` 可直接沿用。

#### 0.4.4 依賴與工具鏈

- `pyproject.toml`：`opentelemetry-sdk` / `opentelemetry-exporter-otlp-proto-http` `1.45.1 → 1.45.2`（**僅 `otlp` extra**，我們未啟用）。
- `pm/lock.json`：`cua-driver` `0.21.0 → 0.52.0`（Cua browser driver，**我們未使用**）。
- `pnpm-lock.yaml`：16 行變更（上游 lock 更新）。
- **無 Python 版本 floor 變更**、`Dockerfile` 零改動 → 我們的自訂層無需重新 port。

#### 0.4.5 變更規模分布（依 area）

| Area | 檔數 | 說明 |
|---|---|---|
| `tests/` | 2,384 | 測試（不進 image） |
| `plugin-catalog/` | 307 | 目錄資料 |
| `gateway/` | 193 | gateway 核心 |
| `persistence/` | 169 | **新 storage 層** |
| `agent/` | 132 | agent 核心 |
| `hermes_cli/` | 115 | CLI / config |
| `website/` | 96 | 官網（**大量刪除** plugin/skills catalog 頁） |
| `apps/` | 96 | desktop |
| `tools/` | 59 | 工具 |
| `tui_gateway/` | 51 | TUI RPC |
| `plugins/` | 24 | **Telegram 僅 2 檔**（`adapter.py`、`telegram_dm_topic_send.py`） |
| `session_rules/` | 18 | **新** |

#### 0.4.6 Telegram 平台插件：實測為「零行為變更」

上游 `plugins/platforms/telegram/` 在本視窗只有 **2 檔、+5 / −5 行**的差異，且 **100% 是 `hermes_state` → `persistence` 重構的機械式改寫**：

```diff
-        db = getattr(getattr(self, "_session_store", None), "_db", None)
-        if db is None or not hasattr(db, "delete_telegram_topic_binding"):
+        persistence = getattr(getattr(self, "_session_store", None), "persistence", None)
+        if persistence is None:
-            removed = db.delete_telegram_topic_binding(chat_id=..., thread_id=..., profile_name=...)
+            removed = persistence.routing.delete_topic_binding(chat_id=..., thread_id=..., profile_name=...)
```

我們線上用到的 3 個 Telegram config key（`telegram.reactions`、`telegram.allowed_chats`、`telegram.extra.rich_messages`）在 v0.23.3 的 `hermes_cli/config_defaults.py` 中**行號與內容完全相同**（`:1574` / `:1577` / `:1581`），無被移除或改名。
→ **Telegram 側風險實測為 🟢 極低**（上一輪 v0.23.1→v0.23.2 曾是 46 檔大改，本輪只有 2 檔）。

### 0.6 `persistence/` 重構深度稽核（子代理實測）

- **上游重構主 commit**：`be3d6affc8` *"refactor(state)!: remove the old session store"*（2026-11-05）——68 個 `hermes_state_*.py` → `persistence/`(169) + `session_rules/`(18) + `persistence_assembly.py`。
- **磁碟格式完全未動**：`SCHEMA_SQL`（336 行）、`FTS_SQL`、`FTS_TRIGRAM_SQL`、`DEFERRED_INDEX_SQL`、27 欄 `messages` INSERT 清單 —— **byte-identical**；`PRAGMA journal_mode=WAL`、`foreign_keys=ON`、`busy_timeout`（讀 5.0s / 寫 1.0s）、`synchronous`、`apply_database_pragmas` 全部一致。**無新 on-disk 產物**（`cache/schema_columns.json` 舊版已有）。
- **無 schema migration 觸發**：`PRAGMA user_version` 兩版皆未寫；`schema_version` 表 = 33 → `if current_version < SCHEMA_VERSION` 為 false → 不寫 `UPDATE schema_version`；`_reconcile_columns` 只補 `PRAGMA table_info` 缺的欄位（相同 DDL → 無 `ALTER TABLE`）。
- **`hermes_state` public surface 縮水**：facade 變成 655 行 compat shim，**只承載 32 個名稱**（`__all__` = `hermes_state.py:106`）；`SessionDB` 由 **247 個 public method → 24 個**（`hermes_state.py:196-540`），其餘 223 個走 `__getattr__` 拋 `AttributeError`。被移除者含 `is_malformed_schema_error`、`repair_state_db_schema`、`log_write_lock_holders`、18 個 `Session*Mixin`。
  - ✅ **對我們無影響**：本 fork 相對 v0.23.2 的 Python 差異只有 `hermes_cli/models_catalog_static.py`，**沒有任何本地程式碼 import `hermes_state`**；上游 v0.23.3 自己也只剩 3 個內部 importer。
- **鎖定行為保留**：`persistence/sqlite/_state/write.py` 與舊 `hermes_state_write.py` **byte-identical**；`lockguard.py` 差異僅 3 行註解（OFD lock 幾何完全相同：`_PENDING_BYTE=0x40000000`、`_SHARED_SIZE=510`、`_SHM_DMS_BYTE=128`）；lock 檔案集合不變（`.fts_rebuild.lock` / `.quarantine.lock` / `.repair.lock` / `.auto-maintenance.lock`）。
  - ✅ 「probe first so a clean store takes no write lock on open」語意**兩版一致**。
  - 🆕 **連線模型改變**：v0.23.3 每 profile 每 process **共用一條 writer 連線**（`persistence_assembly.py:52-56`），取代原本每個 `SessionDB` 一條 → **second-writer 衝突變少**；但 `SessionDB.close()` 從關閉連線變成釋放參考。
- **備份/還原**：`hermes backup` 底層搬到 `persistence/sqlite/admin/_backup.py`，snapshot 語意不變；🆕 `_wal_copy_until_deadline`（`b6412b81be`）在 WAL 快照遇 `SQLITE_BUSY_RECOVERY` 時會在 10s 期限內重試 → **對「對執行中 pod 做備份」更穩健**。還原路徑（`_restore_epoch_source` + `_restore_db_pages`）語意保留；**我們的 tar-copy 還原不經過 Hermes，不受影響**。
- 🆕 **寫入交易 pinning**：commit `0316063447` 讓 ranked-FTS 路徑釘住一個讀交易，讓診斷 bm25 probe 看到同代 index → **可能暫時讓 `PRAGMA wal_checkpoint(TRUNCATE)` 回 busy**（已用重試迴圈處理）。
- **`session_rules/` 是純規則層**：18 檔皆**無 `sqlite3` import、無檔案 I/O**（`media.py` 的 `Path()` 只是字串解析呼叫端給的 `media_root`）→ **無新 on-disk 產物、無 migration**。

### 0.7 ⚠️ 線上 DB 實測：v0.23.3 首次開啟會觸發一次全量 FTS 重建

升級前對線上 `state.db` 做的唯讀盤點：

| 項目 | 值 | 意義 |
|---|---|---|
| `schema_version` 表 | **33** | ✅ 不觸發 migration ladder |
| `PRAGMA integrity_check` | `ok` | ✅ |
| `journal_mode` | `wal` | ✅ |
| `sessions` / `messages` | 134 / 18,340 | 基準值 |
| `messages_fts` / `messages_fts_trigram` | 18,340 / 18,340 | 兩套索引皆完整 |
| `state_meta.fts_tool_full_content_high_water` | **`'16551'`（存在）** | ⚠️ **v0.23.3 新增的 write-on-open 分支的觸發條件** |
| `state_meta.fts_storage_version` | **不存在** | 兩版皆為 opt-in 路徑，非 v0.23.3 regression |
| `state_meta.message_uid_backfill` | `'1'` | ✅ 已完成 |
| `state_meta.legacy_refusal_repair_done` | 不存在 | 兩版皆會在開啟時執行 repair（逐 chat 取寫鎖） |

v0.23.3 的 `_migrate_misaligned_fts_source`（`persistence/sqlite/_schema.py:406-435`）除了原本的「view stale / source misaligned」判斷，**新增**了：只要 `state_meta` 還留著已退役的 `fts_tool_full_content_high_water` marker，就 **DROP `messages_fts` + `INSERT INTO messages_fts(messages_fts) VALUES('rebuild')` 全量重建**（在 `BEGIN IMMEDIATE` 之下、持寫鎖）。上游量測為 1.35M 列 / 8.9 GB 耗 130s（commit `86ba5a8a52`）；**我們是 18,340 列 / 178 MB，預估秒級**。

→ 這是**一次性**成本（重建後 marker 被清掉），但落在**首次啟動**。詳見 Phase D 的 D3a 處理。

#### 0.7.1 FTS 重建路徑逐行追查（本地 diff 實測，取代被 rate-limit 打死的子代理）

| 問題 | 答案 | 證據 |
|---|---|---|
| 觸發點 | `_schema.py:1421` 在 `_init_schema` 流程內呼叫 → **同步**執行，非 background thread | `persistence/sqlite/_schema.py:1421`、`:1468-1489` |
| 會阻塞啟動嗎 | **會**。`with fts_rebuild_admission(...) as admitted:` 之後直接 `rebuild_fn()` inline | `persistence/sqlite/_schema.py:1479-1482` |
| 跨進程競爭 | 用檔案鎖 `{db_path}.fts_rebuild.lock`（= `/opt/data/state.db.fts_rebuild.lock`）。**阻塞等待最多 120 秒**；逾時則 **defer**（drop 全部 FTS triggers + 標記 stale → 搜尋暫時失效，等後續 recovery 重建） | `persistence/sqlite/_state/common.py:332-373`（`_FTS_REBUILD_LOCK_TIMEOUT_SECONDS = 120.0`、`_FTS_REBUILD_LOCK_POLL_SECONDS = 0.1`，`:146-147`） |
| 我們的風險 | 🟢 **低**：目前 pod 只有 **1 個** Hermes python 行程（PID 198 `gateway run --replace`），無競爭；重建預估秒級 ≪ 120s 逾時；且**升級前已確認 `/opt/data/state.db.fts_rebuild.lock` 不存在**（無 stale lock） | `ps -eo pid,etime,cmd` 實測；`ls -la /opt/data/state.db.fts_rebuild.lock` → No such file |
| trigram 會一起重建嗎 | ❌ **不會**。`_align()` 只在 `state_meta.fts_rebuild_high_water` 存在時才重建 trigram；我們線上該 marker **不存在** → 只動 `messages_fts`，`messages_fts_trigram` 不碰 | `persistence/sqlite/_schema.py:464-477`；線上 `state_meta` 實測 `fts_rebuild_high_water = None` |
| 會留髒資料嗎 | ❌ 重建走 `BEGIN IMMEDIATE` + `DROP TRIGGER` → `DROP TABLE messages_fts` → 重跑 `FTS_SQL` → `INSERT ... VALUES('rebuild')`，索引由 `messages_fts_src` 投影 view 重新生成，原始 `messages` 資料不動 | `persistence/sqlite/_schema.py:449-479` |
| marker 會清掉嗎 | ✅ 會。`_align()` 最後執行 `_CLEAR_REBUILD_MARKERS_SQL` + **`_DROP_RETIRED_TOOL_HIGH_WATER_SQL`** → 下次開啟不會再重建 | `persistence/sqlite/_schema.py:477-478` |
| 會有警告嗎 | 會，且是**預期**的：*"carried the tool-row high-water marker that only Hermes releases older than FTS storage v3 write; rebuilt messages_fts from the aligned projection in N.Ns. **Downgrading is unsupported.**"* → Phase D 看到這行是**正常**，不是故障 | `persistence/sqlite/_schema.py:479-487` |

> ⚠️ **注意那句 "Downgrading is unsupported"**：v0.23.3 重建後，降回 v0.23.2 會缺少 `messages_fts_src` 投影 view 的相容性。**回退計畫因此必須連 `state.db` 一起還原**（用 `~/backups/hermes-20261121/` 的備份），不能只換 image。

#### 0.7.3 ✅ 上線後實測更正：**我們是 legacy inline FTS 佈局，不會重建**

原本的 R9 預期「v0.23.3 首次開啟會重建 `messages_fts`」。**上線後實測推翻此預期**，並找到了原因。

在 v0.23.3 的 pod 內直接呼叫上游函式判定：

```
stored vtable: CREATE VIRTUAL TABLE messages_fts USING fts5(content)
base_index_recognised:      True
base_index_realigned_on_open: False
fts_layout_drift:            ['messages_fts', 'messages_fts_trigram']
fts_layout_current:          False
```

| 事實 | 意義 |
|---|---|
| 儲存的 vtable 是 `fts5(content)` —— **單欄、自帶內容的 inline 佈局** | 我們的 DB **沒有** `messages_fts_src` 投影 view（實測 `sqlite_master` 確認） |
| `_migrate_misaligned_fts_source` 的開頭 guard 是 `if legacy or not base_index_recognised(cursor): return` | **legacy inline DB 依設計直接跳過整條重建路徑**（docstring 原文：*"Legacy inline DBs skip this entirely (their index is self-contained; they still take the DDL on the optimize-storage path)"*） |
| `fts_layout_drift` 列出兩個索引 | 這是**舊版定義**，只有 `hermes sessions optimize-storage`（opt-in）才會換掉 —— **與 v0.23.2 行為相同，非 regression** |
| `state_meta.fts_tool_full_content_high_water` 仍在 | **預期且正確**：legacy inline 不重建 → marker 不被清 → 每次開啟都早退（成本為零） |

**淨結果（實測）**：

- ✅ **沒有重建** → 沒有 startup 阻塞、沒有寫鎖、沒有 120s admission 競爭
- ✅ **搜尋功能完全正常**（實測 MATCH 命中數見 D3a）
- ✅ **回退大幅簡化** → 只需換 image，**不需要還原 `state.db`**（原本擔心的 *"Downgrading is unsupported"* 不適用）
- ⚠️ 唯一待觀察項：`fts_layout_drift` 顯示兩個 FTS 索引仍是舊定義。若日後想收斂到 v3 佈局，需跑 `hermes sessions optimize-storage`（**本次不做**：屬 opt-in 維護動作，會重建索引、與本次升級無關，且改變搜尋佈局需要另外驗證）

#### 0.7.2 其他 write-on-open 路徑盤點（依我們的 marker 狀態）

| 路徑 | 我們會不會觸發 | 證據 |
|---|---|---|
| `schema_version` migration ladder | ❌ 不会（表 = 33，門檻 `current_version < 16/18/20/22/23/25/30/33` 全為 false） | `persistence/sqlite/_schema.py:1199-1292` |
| `_reconcile_columns`（ADD COLUMN） | ❌ 不会（DDL byte-identical，無欄位缺失） | `persistence/sqlite/_schema.py:857-859` |
| `message_uid_backfill` | ❌ 不会（marker = `'1'`） | 線上 `state_meta` 實測 |
| `legacy_refusal_repair_done` | ⚠️ **會**（marker 不存在）→ 逐 chat 取寫鎖執行 repair。與 v0.23.2 相同，非 v0.23.3 regression | `persistence/sqlite/conversation/_store/legacy_refusal.py` |
| `fts_storage_version` marker 缺失 | 🟢 兩版皆為 opt-in 路徑（`optimize-storage` / `_stamp_settled_fts_layout`），**非 v0.23.3 regression** | `persistence/sqlite/_schema.py:1180-1185` |

### 0.8 Breaking-change 深度稽核（子代理實測，diff 佐證）

| # | 面向 | 變更 | 證據 | 對我們的影響 |
|---|---|---|---|---|
| B1 | `hermes_state` 公開 API | 1748 → 655 行 compat shim（docstring：*"removed in v0.27.0"*）；`SessionDB` 縮成約 30 個精選 method，其餘 `__getattr__` 拋 `AttributeError`；**`SessionDB(db_path=…)` 現在要求檔名必須是 `state.db`**，否則拋 `ValueError`；首次使用轉發名稱會發 `DeprecationWarning` | `hermes_state.py:1-3, :28, :196, :203-215, :292, :639-645`；commit `3f68c057c5`、`95038c9bcd` | ✅ 無（我們沒跑自訂插件；唯一 Python 差異是 `models_catalog_static.py`） |
| B2 | Telegram topic bindings | `SessionTelegramTopicsMixin.delete_telegram_topic_binding` 整個消失，改由 `persistence.gateway.routing.RoutingRepository.delete_topic_binding` 接手（1:1 改名，6 個方法全數對應） | `plugins/platforms/telegram/adapter.py:990-998`；`gateway/run_topics.py:64-80`；commit `3f91a4a43b` | ✅ 無（唯一呼叫者就是 Telegram adapter 本身，已同步更新） |
| B3 | Platform adapter API | `adapter._ensure_session_db()` → `adapter._ensure_store()`；gateway `self._session_db` → `self.persistence` | `gateway/run_notifications.py:1139`；`gateway/platforms/api_server.py:1623,1733` | ✅ 無（stock adapter 已同步；只會打斷自訂插件） |
| B4 | `state.db` 還原路徑 | 改走 store admin（`open_store_admin(dst).restore_from(src)`），取代原本的 raw page-copy + runtime-epoch staging；`hermes sessions recover` 仍存在（搬到 `persistence/sqlite/admin/_recovery.py:1183`） | `hermes_cli/backup_restore.py:53-56` | ✅ 我們的 **tar-copy 還原不經過 Hermes**，不受影響；⚠️ 回退計畫**不要**依賴 `hermes sessions recover` |
| B5 | `config_home` 目錄建立 | `make_user_dir(path, parents=True)` → `mkdir_under_hermes_home(path)`：**具名 profile 的 home 永遠不會被建立** | `hermes_cli/config_home.py:40-43`；`hermes_constants.py:476-501` | ✅ 無（我們用 default home） |
| B6 | Gateway session policy | `_adopt_stored_policy` 現在會**丟棄未知的 stored policy key**（每 process 警告一次），不再拒收 receipt；`LocalSessionPolicy` 欄位集 old↔new **完全相同** | `gateway/session_policy.py:134-170, :87-97` | ✅ 無 |
| B7 | CLI 指令面 | 逐一 diff `hermes_cli/subcommands/` 所有 `add_parser("…")` 名稱 → **空 diff**；`hermes_cli/subcommands/sessions.py` 零改動；`/handoff` 只是搬到 `CLIHandoffMixin` | `hermes_cli/cli_commands_handoff.py` | ✅ 無 |
| B8 | `session_retention.py`（新） | 會 unlink `cache/pruned/` 中無人引用的封存，並可能 VACUUM（沿用既有 `min_vacuum_interval_days` / `min_vacuum_freelist_ratio` 閘門） | `session_retention.py:80, 185-218` | 🟢 低（與 0.10 的 cold-prune 封存連動，見 D10） |
| B9 | `MACHINE_PACED_SOURCES` | 新增 `api_server` / `curator` / `a2a` / `msgraph_webhook` / `gateway_hygiene`（原為 `api`） | `agent/prompt_caching.py:158-160` | ✅ 無（我們顯式 pin `5m`；且 api_server 前後皆解析為 5m） |
| B10 | `providers` 套件 | Nous Portal `prompt_cache_max_ttl` `5m → 1h` + `prompt_cache_markers_from_catalog=True` | `plugins/model-providers/nous/__init__.py:76-84` | ✅ 無（我們用 MiniMax） |
| B11 | Python / 依賴 floor | `requires-python = ">=3.11,<3.15"` **不變**；`dependencies` 清單未動；`.python-version` = `3.14` 不變；`opentelemetry` 僅 `otlp` extra | `pyproject.toml:15` | ✅ 無 |

**上游刪除的 38 個 non-test `.py`**：全為 `hermes_state_*.py` mixin 模組（38 支），加上 `agent/context_compressor_retry.py`、`agent/message_content.py`、`gateway/session_admission.py`、`hermes_cli/session_lost_and_found.py`、`hermes_cli/session_schema_history.py`。
**模組改名表**（26 項，含 `tools/checkpoint_manager.py` → `agent/checkpoints/manager.py`、`hermes_state_keys.py` → `session_keys.py`、`hermes_state_user_copy.py` → `storage_user_copy.py`、`hermes_state_errors.py` → `storage_errors.py`）——**全是內部路徑，非 API**（AGENTS.md 明載「internal paths are not API」）。

### 0.9 🆕 Prompt-cache lifecycle controller（上游新子系統，預設開啟）

上游新增 `agent/prompt_cache_lifecycle/` + `agent/prompt_cache_routes.py`，**四項預設啟用的行為**（與本次 `cache_ttl` 預設改 `auto` 同一個 release）：

| # | 行為 | 細節 | 證據 | 對我們的影響 |
|---|---|---|---|---|
| C1 | **Keep-alive 預熱** | 每則使用者訊息 **3 次** idle keep-alive；工具等待期間另有無上限的 warming | `agent/prompt_cache_lifecycle/warmer.py:41`（`WARM_BUDGET = 3`）、`:46, :49` | ⚠️ **額外 API 呼叫與花費**。閒置的 Telegram 對話在 tier 升到 1h 後會持續被預熱 |
| C2 | **Learned route store** | 路由樣本存在 `<HERMES_HOME>/cache/prompt_cache_routes.json`；**2 個不同 session 各給 2 次一致樣本後**，若該路由從未被讀回 → **停止給它 keep-alive，且停止送 `cache_control` markers**；事實 7 天後過期 | `agent/prompt_cache_routes.py:1-31, :38`（`EXPIRY_SECONDS = 7*24*3600`）、`:40`（`MIN_SAMPLES = 2`）、`:61-66`（`_path()`） | ⚠️ **我們的 MiniMax 路由可能在累積樣本後被靜默地停止送 cache markers**（`agent/agent_runtime_helpers.py:525-527` 新增 `learned_or_catalog_markers` 分支）。需在 Phase D 觀察 |
| C3 | **Cold prune** | 當 prompt-cache clock 判定快取已消失 → 修剪舊 tool output（需回收 **≥ 16,000 tokens** 才動手），原文寫入 `$HERMES_HOME/cache/pruned/`；**不需要** `proactive_prune_tokens` | `agent/turn_proactive_prune.py`（新）、`website/docs/user-guide/configuration.md`（+"When the cache has already expired (on by default…)"） | 🟢 低（我們 `proactive_prune_tokens` 仍為 `0`，本區塊在視窗內未改） |
| C4 | `/context` 擴充 | 新增 tier / learning 行 | `website/docs/user-guide/configuration.md` | 🟢 低（觀察用） |

> 我們的 `HERMES_HOME=/opt/data` → 新 store 落在 `/opt/data/cache/prompt_cache_routes.json`，cold-prune 原文落在 `/opt/data/cache/pruned/`。**Phase D 需檢查這兩個路徑。**

#### 0.9.1 我們的 MiniMax 路由實質不受 prompt-cache lifecycle 影響（實測推導）

我們線上 `model.default: MiniMax-M3.1-Flash`、`model.provider: minimax`。逐條對照 v0.23.3 的 markers 決策鏈：

| 步驟 | 程式碼 | 我們的結果 |
|---|---|---|
| 1 | `is_anthropic_wire = eff_api_mode == "anthropic_messages"`（`agent/agent_runtime_helpers.py:1359`） | 兩種 api_mode 都要分別驗 |
| 2 | `is_minimax_route = provider_lower in {"minimax", "minimax-cn"} or base_url_host_matches(..., "api.minimax.io"/"api.minimaxi.com")`（`:1389-1393`） | ✅ **True**（provider = `minimax`） |
| 3 | anthropic wire 分支：`_model_name_suggests_minimax_m3(eff_model)` → `"minimax-m3" in "minimax-m3.1-flash"` → **True** → `return False, False`（`:1394-1398`） | ✅ **不送 markers**，且此分支在 `learned_or_catalog_markers` **之前**就 return |
| 4 | chat_completions 分支：`learned_or_catalog_markers(...)` → `marker_preference()`（無樣本 → None）→ `catalog_cache_markers()` → `get_provider_profile("minimax")` → **minimax 不是註冊的 ProviderProfile**（`providers/` 內 0 筆 minimax）→ **None** → 該分支不成立 | ✅ **不送 markers**（落到函式尾端 `return False, False`，`:1435`） |
| 5 | warmer 的門檻 `has_cache_markers(api_kwargs)`（`agent/prompt_cache_lifecycle/replay.py:14-27`）—— **沒有 markers 就不會 keep-alive 預熱** | ✅ **無額外 API 呼叫、無額外花費** |
| 6 | learned route 樣本只有「實際送過 markers 且被讀回」才會被記錄 | ✅ 我們從不送 markers → 永遠沒有樣本 → 不會出現「抑制 markers」的狀況 |

→ **結論：R11 對我們的 MiniMax-M3.1-Flash 路由不成立。** 仍列 D10 觀察（確認上游實際行為與推導一致），但不列為阻擋項。

### 0.10 ⚠️ 一項已解決的分析歧異（位元組級證據）

子代理假設「我們線上 `config.yaml` 是用舊模板 seeded 的，那一行會帶模板註解 → 遷移會刪掉它 → 掉到 `auto`」。
**實測反證**（升級前在線上 pod 以 `cat -A` 取位元組）：

```
prompt_caching:$
  cache_ttl: 5m$
```

我們的行是 **bare `5m`、無引號、無行尾註解**。遷移正則
`_TEMPLATE_CACHE_TTL_LINE = ^[ \t]+cache_ttl:[ \t]*(["']?)5m\1[ \t]*#[ \t]*use "1h" for long sessions with pauses between turns[ \t]*$`
在 `cache_ttl: 5m` 之後要求 `#`，**不匹配** → `seeded = False` → 遷移走「保留 + 印 ℹ 提示」分支。

另補一點代理未涵蓋的關鍵條件：遷移 54 **只在 `config.yaml` 的 `_config_version` < 54 時才執行**（不在 `LEGACY_KEY_STEPS` / `STAMP_INDEPENDENT_STEPS`）。我們線上是 `_config_version: 53` → **遷移確實會跑**，但結論是**保留**。

→ **最終行為：`prompt_caching.cache_ttl` 維持 `"5m"`，Telegram 快取層不變，僅多一行 ℹ 提示。** 與 Go-Sign 的 Q2 決策一致。

### 0.11 決策點（Go-Sign 時請回覆）

| # | 決策 | 建議 |
|---|---|---|
| Q1 | config `_config_version` 53 → 54（唯一 schema 變動），是否仍執行 Phase 0 線上 `/opt/data` 備份？ | ✅ **建議執行**：DB schema 未變但視窗 3,948 檔，留一份升級前快照可確保隨時無痛回退。 |
| Q2 | `prompt_caching.cache_ttl` 維持我們的 bare `5m`（遷移會保留），或改吃預設 `auto`（1h 層）？ | ✅ **建議維持 `5m`**：本次升級不夾帶行為變更；`auto` 可另案評估。 |
| Q3 | Telegram plugin 僅 3 檔異動（遠小於 v0.23.1→v0.23.2 的 46 檔），是否仍於 Phase D 實測 Telegram 往返？ | ✅ **必須**：Telegram 為唯一使用平台，且 `gateway/` 193 檔異動。 |
| Q4 | 是否授權依本工作表建立 `my-config-v0.23.3`、推送並觸發 GHCR Build？ | ⏳ **待確認** |

---

## 1. Diff 與衝突面稽核（`upstream-v0.23.2 → upstream-v0.23.3`）

自訂 commits 共 **63 個**（`upstream-v0.23.2..my-config-v0.23.2`，線性 0 merge）。

### 1.1 衝突面（`comm -12` 實測，19 檔）

| 檔案 | 上游變動 | 衝突風險 / 處置 |
|---|---|---|
| `.github/workflows/*`（**17 檔**） | 上游 workflow 異動 | 🟢 **全部 purge**，由 `my-config-v0.23.2` checkout 我們的 `ghcr-publish.yml`（註：`ghcr-publish.yml` **上游根本沒有**——上游用 `docker.yml` 發佈到 Docker Hub `nousresearch/hermes-agent`；我們的 154 行 Matrix 版是純自訂檔，purge 時必須排除它） |
| `AGENTS.md` | 改 3 行（`persistence/` 取代 `hermes_state.py` 說明、`grep`→`search_files`） | 🟡 **可自動合併**（merge-tree 已驗 `Auto-merging AGENTS.md`），但需確認 Mac 資源限制章節仍完整保留 |
| `hermes_cli/models_catalog_static.py` | 上游加 GPT-6.2 Astra/Sol（3 個 hunk） | 🟢 **可自動合併**（merge-tree 已驗），且上游**未觸碰任何 MiniMax 行** → 我們的 MiniMax patch 可直接帶過 |

**不在交集（可乾淨 cherry-pick）**：`Dockerfile`、`docker/entrypoint-ssh.sh`、`docker/stage2-hook.sh`、`docker-compose.yml`、`.env.example`、根目錄 `UPGRADE_LOG_*.md`（8 份）、`scripts/*`（4 檔）、`docs/**`。

### 1.2 merge-tree 三方合併實測（決定性證據）

```bash
git merge-tree --write-tree --name-only upstream-v0.23.3 my-config-v0.23.2
```

結果：**17 個 `CONFLICT (modify/delete)` 全部落在 `.github/workflows/`**，其餘 **0 衝突**（`Auto-merging AGENTS.md`、`Auto-merging hermes_cli/models_catalog_static.py`；`Dockerfile` / `docker/` / `.env.example` / `docker-compose.yml` 靜默合併）。
→ **真衝突數 = 0**，且既有 purge 機制（`f8a2aeed43`）可完整吸收全部 workflow 衝突。

### 1.3 自訂 commits 移植清單（63 → 9 個功能型 + 54 個 docs 型）

| 類型 | Commit | 檔案 | 處置 |
|---|---|---|---|
| 功能 | `9c710397b7` | `hermes_cli/models_catalog_static.py` | ✅ cherry-pick（上游未觸 MiniMax 行） |
| 功能 | `df6988b743` | `Dockerfile`（`--extra stt-whisper`） | ✅ cherry-pick（上游 Dockerfile 零改動） |
| 功能 | `1e44e86bfe` | `Dockerfile`（自訂層 re-port） | ✅ cherry-pick |
| 功能 | `ac02ee39d4` | `docker/stage2-hook.sh` | ✅ cherry-pick |
| 功能 | `d84038b3b1` | `docker/entrypoint-ssh.sh` | ✅ cherry-pick |
| 功能 | `1efa309d41` | `docker-compose.yml` | ✅ cherry-pick |
| 功能 | `b02ef9db7e` | `.env.example`（`HERMES_IMAGE`） | ✅ cherry-pick **+ 將版本字串 `v0.23.2` → `v0.23.3`** |
| 功能 | `6e4530da25` | `AGENTS.md`（Mac 資源限制章節） | ✅ cherry-pick（可自動合併）／必要時手動補回章節 |
| CI | `f8a2aeed43` | `.github/workflows/*`（purge） | 🔁 **重做**：上游 v0.23.3 有 **48 個** workflow（v0.23.2 為 47，新增 `canary-e2e.yml`），purge 全部再 checkout 我們的 `ghcr-publish.yml` |
| docs | 其餘 54 個 | `UPGRADE_LOG_*.md` ×8、`docs/**`、`scripts/**` | ✅ cherry-pick（零衝突） |

### 1.4 npm / lockfile 狀態（無本地分歧，直接繼承上游安全更新）

- 我們的 `pnpm-lock.yaml` 與 `upstream-v0.23.2` **完全相同**（`git diff` 為空）→ **無本地分歧**，切到 v0.23.3 後自動繼承上游的漏洞修補：
  - `follow-redirects` `1.16.1 → 1.16.2`（安全更新）
  - `joi` `18.2.9 → 18.3.1`
- `website/package-lock.json` 上游亦有 9 行更新（官網用 npm，**不進 image**）。
- Docker 的 Node 依賴安裝走 `scripts/build/node-deps.mjs` + `scripts/build/pnpm-lock.mjs`，兩者在 v0.23.3 **皆存在且 `node-deps.mjs` 零改動** → 建置路徑穩定。
- 我們自訂的 `scripts/camofox_*.py`、`scripts/smoke-v0.22.5.sh` **不在上游異動清單內** → cherry-pick 零衝突。

### 1.5 Dockerfile 自訂層必須保留（目標 14/14 marker）

`openssh-server`、`rsync`、`ssh-keygen -A`、`zh_TW.UTF-8`、`en_US.UTF-8`、`useradd -u 10000`、`--extra edge-tts`、`--extra firecrawl`、`--extra dingtalk`、`--extra feishu`、`--extra exa`、`--extra stt-whisper`、`/tmp/.npm-cache`、`docker/entrypoint-ssh.sh`、`ENV HOME=/opt/data`（base image `debian:trixie-20261020@sha256:4c25275446ca371766b8b093c696782eabce06263fccacb8d5d813b3dc44b308` 不變）。

---

## 2. 風險重點

| # | 風險 | 嚴重度 | 緩解 / 驗證 |
|---|---|---|---|
| R1 | config `_config_version` 53 → 54 單向 stamp | 🟢 低 | 降回 v0.23.2 只會顯示提示、不改寫設定；Phase D 確認 `Config version up to date (v54)` |
| R2 | `persistence/` + `session_rules/` 大重構（187 新檔） | 🟡 中 | DB schema 33 不變、無 migration；Phase D 驗 `PRAGMA integrity_check`、`schema_version = 33`、FTS trigram 正常 |
| R3 | 3,948 檔大視窗，上游完整 notes 延至 v0.24.0 | 🟡 中 | Phase 0 備份 + 上線後觀察 `RESTARTS`、記憶體與 `errors.log` |
| R4 | `gateway/` 193 檔、`agent/` 132 檔異動 | 🟡 中 | Phase D 檢查 gateway 開機 log、`hermes doctor`、Telegram 往返實測 |
| R5 | `prompt_caching.cache_ttl` 預設改 `auto` | 🟢 低 | 我們 config 為 bare `5m`，遷移保留 → 行為不變；Phase D 比對實際 TTL |
| R6 | Telegram plugin 重構（**僅 2 檔 / +5 −5 行**，且為 `persistence` 機械改寫） | 🟢 極低 | 實測 diff 與 config key 相容性皆無行為變更；Phase D 仍實測往返確認 |
| R7 | GitHub Actions `HTTP 422` fork auto-disable（Hard Rule 8） | 🟢 低 | 若遇 422，至 `https://github.com/kuniakil/hermes-agent/actions` 點擊 re-enable banner |
| R8 | 網站 catalog 頁大量刪除（`website/src/pages/plugins/`、`skills/`） | 🟢 低 | 不影響 runtime image；若日後要自架官網需注意 |
| ~~R9~~ | ~~v0.23.3 首次開啟觸發全量 `messages_fts` 重建~~ | ✅ **N/A（已證實不會發生）** | **上線後實測確認：我們的 DB 是 legacy inline FTS 佈局（`CREATE VIRTUAL TABLE messages_fts USING fts5(content)`，無 `messages_fts_src` 投影 view），上游 `_migrate_misaligned_fts_source` 對 legacy inline 佈局**依設計早退**，不重建 → **無 startup 阻塞、無寫鎖、無 admission 競爭**。marker 保留是預期行為。見 0.7.3 |
| **R10** | `hermes_state` public surface 由 247 → 24 個 method，且 `SessionDB(db_path=…)` 現在要求檔名必須是 `state.db` | 🟢 低 | 本 fork 無任何本地程式碼 import `hermes_state`（唯一 Python 差異是 `models_catalog_static.py`），無影響。**但**若日後安裝任何 pinned catalog 插件 import `hermes_state`，會在 2027 的 v0.27.0 移除前收到 `DeprecationWarning` |
| **R11** | 🆕 Prompt-cache lifecycle controller 預設開啟：idle keep-alive 預熱 + learned route store 可能靜默停止送 `cache_control` markers | 🟢 **低（實測後降級）** | ✅ **對我們的 MiniMax 路由實質無影響**（見 0.9.1）：我們的路由**本來就不送 markers**，因此 (a) 不會有 keep-alive 預熱 → 無額外花費；(b) learned route 沒有樣本可學 → 不會抑制 markers。Phase D 仍觀察 `/context` tier/learning 行與 `cache/prompt_cache_routes.json` |
| **R12** | `hermes sessions recover` 底層改寫為 `persistence/sqlite/admin/_recovery.py`，輸出未經行為稽核 | 🟢 低 | **回退計畫一律走 tar-copy 還原**（不經 Hermes），不依賴 `hermes sessions recover` |

### 本次**不需要**做的事

- 不重建 memory/embedding 索引（DB schema、embedding 模型、輸入格式版本皆未變）。
- 不推 `v0.23.3` git tag、不建「已知良好」快照 tag（分支建置模型）。
- 不更新 `pm/lock.json` 的 cua-driver（我們未用 Cua）；`opentelemetry` 僅 `otlp` extra 未啟用。
- 本機不跑 `pytest` / `pnpm` / `docker build`（Mac 資源保護規則 + Hard Rule 7）。

---

## 3. 執行步驟 Checklist（**待 Go-Sign 後才執行**）

### Phase 0 — 停機前盤點 + 備份

- [x] 0.1 `kubectl --context n100-cf -n hermes get pod`，記錄目前 pod / image digest（基線：`v0.23.2`）
  - Pod `hermes-agent-5f75cdcbf8-zpngh`，`1/1 Running`，`RESTARTS 0`，`IP 10.42.0.209`，Node `n100`，AGE `3d15h`
  - `imageID`：`ghcr.io/kuniakil/hermes-agent@sha256:08dd8898ecf7207ac008b7ad4fe9d1468bdd2178f090c4bae0b634397f44af85`
  - `hermes --version`：`Hermes Agent vv0.23.2 (2026.9.24) · upstream 9c710397`
- [x] 0.2 備份 `/opt/data` 至 `~/backups/hermes-20261121/`
  - WAL checkpoint **第 1 次即成功** → `(0, 0, 0)`，`state.db-wal` 截為 0 bytes
  - `tar -czf -` 壓縮串流（state.db + -wal + -shm + config.yaml + .env + .hermes/）→ exit 0，無 stderr
  - 落地：`state.db` 187,817,984 B、`config.yaml` 13,244 B、`.env` 997 B、`.hermes/` 38 MB
- [x] 0.3 驗證備份：`integrity_check = ok`、`schema_version = 33`、`sessions = 134`、`messages = 18,340`、`messages_fts = 18,340`、`fts_tool_full_content_high_water = '16551'`（見 0.7）

### Phase A — 建立分支 + Purge + 移植自訂 Commits

- [x] A1 `git checkout -b my-config-v0.23.3 upstream-v0.23.3`（base `caafe5389a`）
- [x] A2 purge 上游 48 個 workflow（`find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete` → 再由 `my-config-v0.23.2` checkout 我們的 `ghcr-publish.yml`），commit `f28603f62b`
  - 實刪 **47 檔**（上游 48 − 我們的 `ghcr-publish.yml`），新增 `ghcr-publish.yml`（154 行）
  - ⚠️ 排除檔名必須是 **`ghcr-publish.yml`**（Hermes 專屬），不是 skill 通用範例裡的 `docker-release.yml`
  - ⚠️ 上游 v0.23.3 新增 `canary-e2e.yml`（第 48 個 workflow），已一併刪除
- [x] A3 cherry-pick 功能型 commits（零衝突）：`d84038b3b1`、`1efa309d41`、`ac02ee39d4`、`1e44e86bfe`、`df6988b743`、`9c710397b7`
- [x] A4 `.env.example` 的 `HERMES_IMAGE` 版本字串 `v0.23.2` → **`v0.23.3`**（已提交）
- [x] A5 cherry-pick `6e4530da25`（`AGENTS.md`）；確認「Local Resource Constraint (Mac Host Protection)」章節完整 ✅（`git diff upstream-v0.23.3 -- AGENTS.md` 僅 +6 行該章節）
- [x] A6 cherry-pick 其餘 54 個 docs commits（`UPGRADE_LOG_*.md`、`docs/**`、`scripts/**`）
  - ✅ **62 個 commits 一次 cherry-pick 完畢，exit 0，零衝突**（舊 purge commit `f8a2aeed43` 排除，改由 A2 重做）
- [x] A7 加入本工作表

### Phase B — 本地輕量驗證（嚴禁重型測試 / 本機 docker build）

- [x] B1 `git log --oneline upstream-v0.23.3..HEAD` = **63 commits、0 merge commits（線性）**；`git status` 乾淨
- [x] B2 `ls .github/workflows` 只剩 `ghcr-publish.yml` ✅
- [x] B3 `Dockerfile` 自訂層 **15/15 marker 全數在位**（`openssh-server` `rsync` `ssh-keygen -A` `zh_TW.UTF-8` `en_US.UTF-8` `useradd -u 10000` `edge-tts` `firecrawl` `dingtalk` `feishu` `exa` `stt-whisper` `npm-cache` `entrypoint-ssh.sh` `HOME=/opt/data`）；base image `debian:trixie-20261020@sha256:4c25275446ca371766b8b093c696782eabce06263fccacb8d5d813b3dc44b308` 不變
- [x] B4 `git diff upstream-v0.23.3 -- Dockerfile` = +36 行（僅自訂層）；`docker/stage2-hook.sh` +84、`docker/entrypoint-ssh.sh` +13（新增）、`docker-compose.yml` +85、`.env.example` +13
- [x] B5 `git diff upstream-v0.23.3 -- hermes_cli/models_catalog_static.py` = **僅** 我們的 MiniMax 變更（上游 GPT-6.2 已含在 base）✅

### Phase C — 推送 Fork + 觸發 GHCR Build

- [x] C1 `git push -u kuniakil my-config-v0.23.3` — ✅ 已推送
- [x] C2 `grep -A6 workflow_dispatch: .github/workflows/ghcr-publish.yml` 確認 input 為 `tag_name`（非 `tag`）— ✅
- [x] C3 `gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v0.23.3 -f tag_name=v0.23.3 -f platforms=all` — ✅ Run **44839843310**（無 422）
- [x] C4 驗證 run：`event=workflow_dispatch`、`headBranch=my-config-v0.23.3`、`headSha=67246ec0b6554732b185e572472d4065ce3e2c2f`（**我們的 commit**）；背景子代理 watch，總耗時 **11m11s**（prepare 4s / amd64 10m35s / arm64 9m13s / merge 22s），結論 **success**
- [x] C5 `docker buildx imagetools inspect ghcr.io/kuniakil/hermes-agent:v0.23.3` — ✅
  - **Multi-arch Index Digest**：`sha256:90eace7745088aa3b3be8beecde7224f4fe91d282cf7a7d3dad9ed19ffbc04f0`
  - `linux/amd64`：`sha256:c85578c1881603da70700542f64ec6b8f7e9a4efcf1f742e6799469b14d50cae`
  - `linux/arm64`：`sha256:60c1f65ae18ec67e20973c7bab7627b2ad504308c40586419d868d23d76d2f3f`
  - `latest` tag 亦指向同一 index digest
  - install stamp：`{"branch": "my-config-v0.23.3", "commit": "67246ec0b…", "baseVersion": "v0.23.3", "dirty": false, "source": "ci"}`
- [x] C6 若遇 `HTTP 422` — N/A（未遇）

### Phase D — K3s 部署 + 驗證

- [x] D0 更新 `~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag: "v0.23.3"`（`~/kubernetes` commit `e781529`，已 push）
- [x] D1 `kubectl --context n100-cf apply -k ~/kubernetes/hermes/overlays/n100` + `rollout status` — ✅ `deployment "hermes-agent" successfully rolled out`
- [x] D2 確認 Pod `1/1 Running`、`RESTARTS 0`、Pod `imageID` 與 C5 multi-arch index digest 一致
  - Pod `hermes-agent-5676f5cb65-5bcl9`，`1/1 Running`，`RESTARTS 0`，IP `10.42.0.96`
  - `imageID`：`ghcr.io/kuniakil/hermes-agent@sha256:90eace7745088aa3b3be8beecde7224f4fe91d282cf7a7d3dad9ed19ffbc04f0`（**與 C5 完全一致**）
- [x] **D3a ✅ 最終結果：沒有重建，也不需要重建**（原預期有重建 —— 預期錯誤，已更正，見 0.7.3）
  - 實測 `messages_fts` = 18,340、`messages_fts_trigram` = 18,340、`integrity_check = ok`、`schema_version = 33`
  - `state_meta.fts_tool_full_content_high_water` **仍為 `'16551'`** → 這是**正確且預期**的：legacy inline 佈局在 v0.23.3 **依設計不重建**（`_migrate_misaligned_fts_source` 的 `if legacy or not base_index_recognised(cursor): return` 早退）
  - **FTS 搜尋功能實測通過**：`messages_fts MATCH '升級'` → 111 hits、`'hermes'` → 5,186 hits、`'test'` → 409 hits；`messages_fts_trigram MATCH 'hermes'` → 5,372 hits（trigram 對 2 字中文不命中是 FTS5 trigram 的正常行為，base index 負責中文）
  - 無 startup 阻塞、無寫鎖競爭、無 admission 競爭
- [x] D4 開機 log — ✅ `✓ telegram connected`、`✓ api_server connected`、`set_my_commands OK (60 cmds)` × 3 scopes（Default / AllPrivateChats / AllGroupChats）
  - **新 pod 啟動後 `errors.log` 0 ERROR / 0 CRITICAL**（最後一筆 ERROR 為 07:03 的 Telegram 網路重試，屬舊 pod 期間的既有噪音）
  - `08:06:26 sqlite3.OperationalError: database is locked` → 來自**舊 pod 關閉時** shared-metrics exit flush（`hermes_cli/observability/shared_metrics.py:526` → `BEGIN IMMEDIATE`），與 v0.23.3 無關
- [x] D5 `hermes doctor` + s6 supervision 樹 — ✅
  - `✓ Config version up to date (v54)`（遷移 53→54 已套用）
  - `✓ No deprecated config keys or env vars`、`✓ Python 3.14.9`、`✓ SQLite 3.53.1`、`state.db: WAL (179.1 MB)`
  - `✓ Runtime venv staged`、所有 Required Packages ✓、`✓ Skills Hub lock file OK (22 hub-installed skill(s))`
  - `Found 1 issue(s)`（缺選用 API keys）— **與 v0.23.2 基線一致**
  - `⚠ install out of sync (pnpm: not installed or outdated)` — **既有上游噪音，維持不修**（與 v0.23.2 基線一致）
  - s6：`main-hermes` up（pid 723），單一 python 行程 `gateway run --replace`
- [x] D6 DB 驗證 — ✅ `integrity_check = ok`、`schema_version = 33`、`sessions = 134`、`messages = 18,340`（與 Phase 0 完全一致）、`messages_fts` = 18,340、`messages_fts_trigram` = 18,340
- [x] D7 自訂層實測 — ✅ 全數正常：`HOME=/opt/data` / `HERMES_HOME=/opt/data`、`sshd` `rsync` `tini` `tmux` `ffmpeg` `ffprobe` `rg` `node` `npm` `python3`、`en_US.utf8` + `zh_TW.utf8`、`/opt/hermes/docker/entrypoint-ssh.sh`、`/tmp/.npm-cache`（1777）、`edge_tts` `firecrawl` `lark_oapi` `exa_py` `dingtalk_stream` `faster_whisper` `av`
- [x] D8 **Telegram 往返實測** — ✅ **使用者於 08:24 於 Telegram 下達升級後檢查指令，08:24:57 收到完整回覆（2,839 字）**
  - Session `20260708_133022_65a00a95`，4 次 API 呼叫（`MiniMax-M3.1-Flash` / `minimax`），耗時 63.7s，`response_len=2839`
  - **prompt cache 實測命中 98%**：`cache=103936/106021 (98%)` → 105984/107766 (98%) → 107520/108964 (99%)
    （與 0.9.1 的推導一致：Hermes 不送 `cache_control` markers，但 MiniMax-M3 的**伺服器端自動前綴快取**照樣生效 → 我們不必送 markers 也有 98% 命中）
  - 實測報告結論：**v0.23.3 升級成功，核心全數正常，部署後 0 ERROR；資料無損（integrity ok、FTS 正常）；STT 未受影響（兩個 venv 端到端中文轉錄都通過）；staged venv 已自動輪替（`4a07758b` → `714f77f4`），舊環境已被 pm 清掉無殘留**
  - 報告涵蓋：版本演進、環境、sessions 134 / messages 18,346 / integrity ok / triggers 14 個未動 / worker_executions 0 / session_admissions 23 / Config v54 / 磁碟 / 記憶體 / API 44 項全通 / Skills Hub 22 / Tools 30 active / 日誌 0 ERROR / STT 雙 venv / gateway 實際執行環境（`/opt/hermes/.venv`，`HERMES_SITE` 正確）
- [x] D9 `hermes --version` — ✅ `Hermes Agent vv0.23.3 (2026.9.24) · upstream 67246ec0`
- [x] D10 **prompt-cache lifecycle 觀察** — ✅ **與 0.9.1 的推導完全一致**
  - `/opt/data/cache/prompt_cache_routes.json` **未生成**（我們的路由不送 markers → 無樣本可學 → 不會建立 store）
  - `/opt/data/cache/pruned` **未生成**（cold prune 需先有 cache 過期 + 回收 ≥16,000 tokens）
  - → **無 keep-alive 預熱、無額外花費、無 learned 抑制**
- [x] D11 **確認 `prompt_caching.cache_ttl` 仍為 `5m`** — ✅ 遷移後 `config.yaml` 第 102–103 行仍為 `prompt_caching:` / `  cache_ttl: 5m`（bare 值保留）；`_config_version` 已由 53 更新為 **54**
- [ ] D12 觀察期：24h 內 `RESTARTS 0`、記憶體穩定、`errors.log` 無新增 ERROR（**待 24h 後複查**）

### Phase E — 收尾

- [x] E1 保留 `~/backups/hermes-20261121/`（228M，`integrity_check = ok`、`schema_version = 33`、`sessions = 134` / `messages = 18,340`）；✅ **已依使用者指示刪除前次備份 `~/backups/hermes-20261117/`**（202M，刪除時遇到唯讀 skill 檔以 `chmod -R u+w` 後完成）
- [x] E2 撰寫 `UPGRADE_LOG_v0.23.2_to_v0.23.3.md`（repo 根目錄）— ✅ 含 2.1–2.6 技術調整、3 線上驗證、4 後續補充、5 回退計畫
- [x] E3 關閉本工作表所有 checkbox（僅 D12 24h 觀察期與 E4 發布待辦）
- [ ] E4 以 `doc-and-wp-publish` 發布收工文章至 **https://wp.3pm.lol/**（n8n 自動同步至 Dify）— **待使用者確認**

### Phase F — Telegram 實測回報的兩個後續發現（**不阻擋收尾，另案處理**）

| # | 發現 | 實測 | 判定 |
|---|---|---|---|
| F1 | 🆕 doctor 新警告：`~/./cache/uv/` **1.7 GB 沒有任何 pruner 管**（只有 `cache/scratch/` 與 `cache/terminal/` 會被回收） | `archive-v0` 1.2G + `simple-v21` 37M + `wheels-v6` 596K | 🟡 **中**：這是 uv 的套件下載快取，**每次 pm 佈建新 venv 都會增長**，屬「沒有上限的增長點」。本次升級的 staged venv 輪替（`4a07758b` → `714f77f4`）是它的來源。**建議**：在 `asr-subtitle-ops` 或 disk 章節加一條「每次升級後檢查 `cache/uv` 與 `installs` 累積」的檢查項 |
| F2 | `/opt/data` 從 3.4G 漲到 5.7G | `.cache/uv` 1.7G（新增）/ `.cache/huggingface` 142M / `.cache/electron` 111M / `.cache/node-gyp` 67M / `installs` 1.3G | 🟢 **低**：Hermes 自身 5.7G 只佔 658G 已用空間的 0.9%；容器外來源（`/data/services/k8s-media`、`/var/lib/containerd`）量不到，**磁碟 21G 增量不歸因給 Hermes**（與既有記憶一致：N100 磁碟暴增來自 Sonarr 拉劇） |

### 回退計畫

1. `~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag` 改回 `"v0.23.2"`，`kubectl --context n100-cf apply -k`。
2. ✅ **實測後簡化：只需換 image，不需還原 DB。**
   - 我們的 DB 是 **legacy inline FTS 佈局**，v0.23.3 **未重建**、未改動任何 FTS 結構（見 0.7.3）→ v0.23.2 可直接讀同一個 DB。
   - DB schema 同為 v33；config `_config_version: 54` 降回 v0.23.2 只會顯示「written by a newer Hermes」提示，**不改寫設定、不阻擋啟動**。
   - （原先前擔心的 *"Downgrading is unsupported"* 僅出現在 v0.23.3 **實際重建**時的 log，我們未觸發該路徑。）
3. 仍**不依賴 `hermes sessions recover`**（底層已改寫為 `persistence/sqlite/admin/_recovery.py`，行為未稽核；見 B4/R12）。若真要還原原檔，用 `~/backups/hermes-20261121/`（`state.db` + `-wal` + `-shm` + `config.yaml` + `.env` + `.hermes/`）。
4. 驗證 Pod `1/1 Running` 與 Telegram 往返正常。

---

## 4. Go-Sign 確認區

- [x] 使用者確認 Q1–Q4（2026-11-21）
  - Q1 備份 → ✅ 執行（Phase 0.2 已完成，`~/backups/hermes-20261121/` 已驗證）
  - Q2 `prompt_caching.cache_ttl` → ✅ **維持 `5m`**（本次升級不夾帶行為變更；0.10 已用位元組級證據確認遷移會保留 bare 值）
  - Q3 Telegram 往返實測 → ✅ 執行（Phase D8）
  - Q4 授權建分支 + 推送 + 觸發 GHCR Build → ✅ 執行
  - 舊備份 `~/backups/hermes-20261117/` → ⏳ **新備份驗證後由使用者再確認**（已驗證通過，暫不刪）
- [x] **Go-Sign 日期 / 時間**：2026-11-21（Phase 0–C）
