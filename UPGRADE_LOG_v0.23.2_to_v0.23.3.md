# Hermes Agent 升級紀錄：v0.23.2 → v0.23.3

- **升級日期**：2026-11-21
- **目標版本**：`v0.23.3`（官方 commit `caafe5389ae585ef77387a962aee05b1bcf17029`，2026-11-19 發布）
- **升級前版本**：`v0.23.2`（基於官方 `v0.23.2` = `ae2a81ccc00e9b7c06301523e5bb09608397149c`）
- **新分支**：`my-config-v0.23.3`（基底 = `upstream-v0.23.3`）
- **Image source SHA**：`67246ec0b6554732b185e572472d4065ce3e2c2f`（= GHCR run `44839843310` 的 `headSha`，`hermes --version` 顯示 `upstream 67246ec0`）
- **GH Actions Run**：[`44839843310`](https://github.com/kuniakil/hermes-agent/actions/runs/44839843310)（success，11m11s：prepare 4s / amd64 10m35s / arm64 9m13s / merge 22s）
- **發布映像**：`ghcr.io/kuniakil/hermes-agent:v0.23.3`（multi-arch index）
  - index digest：`sha256:90eace7745088aa3b3be8beecde7224f4fe91d282cf7a7d3dad9ed19ffbc04f0`
  - `linux/amd64` → `sha256:c85578c1881603da70700542f64ec6b8f7e9a4efcf1f742e6799469b14d50cae`
  - `linux/arm64` → `sha256:60c1f65ae18ec67e20973c7bab7627b2ad504308c40586419d868d23d76d2f3f`
- **部署環境**：K3s n100，pod `hermes-agent-5676f5cb65-5bclq`（`1/1 Running`、`RESTARTS 0`、IP `10.42.0.96`）
- **schema_version**：33 → **33**（無不可逆遷移）
- **config_version**：53 → **54**（遷移 53→54：移除「模板 seeded 的 `prompt_caching.cache_ttl: "5m"`」；我們的 bare 值被保留）
- **FTS_STORAGE_VERSION**：3 → **3**（不變）
- **備份**：`~/backups/hermes-20261121/`（已驗證 `integrity_check = ok`、`schema_version = 33`、`sessions = 134`、`messages = 18,340`）；前次備份 `~/backups/hermes-20261117/`（202M）已依指示刪除
- **工作表**：`docs/worksheet-upgrade-hermes-v0.23.3-20261121.md`

---

## 1. 一句話總結

`v0.23.3` 名義上是 patch，實際是 **1,657 non-merge commits / 3,948 檔 / +222,379 −96,154 / 370 PRs** 的大視窗（官方明言完整 curated notes 延至 `v0.24.0`）。DB `SCHEMA_VERSION`（33）、`FTS_STORAGE_VERSION`（3）與 Docker base image 皆未變；唯一 schema 變動是 **config `_config_version` 53 → 54**。上游把 68 個 `hermes_state_*.py` 重組成 `persistence/`（169 檔）+ `session_rules/`（18 檔），但**磁碟格式 byte-identical**。衝突面實測為 **0 個真衝突**（merge-tree 僅 17 個 `.github/workflows/*` modify/delete，全數由既有 purge 機制吸收）。升級順利完成，線上 0 ERROR，Telegram 往返與中文語音轉錄實測通過。

---

## 2. 關鍵技術調整與問題排除

### 2.1 上游 storage 重構：`hermes_state` → `persistence/` + `session_rules/`

上游主 commit `be3d6affc8`（*refactor(state)!: remove the old session store*）把扁平的 `hermes_state_*.py` 收斂成新套件：

| 面向 | 實測結果 |
|---|---|
| 磁碟格式 | `SCHEMA_SQL`（336 行）、`FTS_SQL`、`FTS_TRIGRAM_SQL`、`DEFERRED_INDEX_SQL`、27 欄 `messages` INSERT 清單 —— **byte-identical** |
| PRAGMA | `journal_mode=WAL`、`foreign_keys=ON`、`busy_timeout`（讀 5.0s / 寫 1.0s）、`synchronous`、`apply_database_pragmas` —— 全部一致 |
| Migration | `PRAGMA user_version` 兩版皆未寫；`schema_version` 表 = 33 → 所有 `current_version < N` 門檻皆為 false → **不寫任何 migration**；`_reconcile_columns` 只補缺失欄位（DDL 相同 → 無 `ALTER TABLE`） |
| 鎖定行為 | `persistence/sqlite/_state/write.py` 與舊檔 **byte-identical**；`lockguard.py` 差異僅 3 行註解（OFD lock 幾何完全相同）。「probe first so a clean store takes no write lock on open」語意兩版一致 |
| 連線模型 | v0.23.3 每 profile 每 process **共用一條 writer 連線**（取代每個 `SessionDB` 一條）→ second-writer 衝突變少；`SessionDB.close()` 從關連線改為釋放參考 |
| `hermes_state` 公開面 | 655 行 compat shim，只承載 32 個名稱；`SessionDB` 由 **247 個 public method → 24 個**；`SessionDB(db_path=…)` 現在要求檔名必須是 `state.db`。docstring 明寫 *"removed in v0.27.0"* |

**對本 fork 的影響：無。** 相對 v0.23.2 的 Python 差異只有 `hermes_cli/models_catalog_static.py`（MiniMax 清單），**沒有任何本地程式碼 import `hermes_state`**；上游自己 也只剩 3 個內部 importer。

`session_rules/` 是**純規則層**：18 檔皆無 `sqlite3` import、無檔案 I/O → 無新 on-disk 產物、無 migration。

### 2.2 ⚠️ 被實測推翻的預期：FTS 全量重建**不會**發生

升級前的分析預期 v0.23.3 首次開啟會重建 `messages_fts`（因為線上 DB 的 `state_meta.fts_tool_full_content_high_water = '16551'` 存在）。**上線後實測推翻此預期**：

在 v0.23.3 的 pod 內直接呼叫上游函式判定：

```
stored vtable: CREATE VIRTUAL TABLE messages_fts USING fts5(content)
base_index_recognised:       True
base_index_realigned_on_open: False
fts_layout_drift:             ['messages_fts', 'messages_fts_trigram']
fts_layout_current:           False
```

我們的 DB 是 **legacy inline FTS 佈局**（單欄 `fts5(content)`，**沒有** `messages_fts_src` 投影 view）。上游 `_migrate_misaligned_fts_source` 開頭的 guard 是 `if legacy or not base_index_recognised(cursor): return` —— **legacy inline DB 依設計直接跳過整條重建路徑**（docstring 原文：*"Legacy inline DBs skip this entirely (their index is self-contained; they still take the DDL on the optimize-storage path)"*）。

**淨結果**：

- ✅ 沒有重建 → 沒有 startup 阻塞、沒有寫鎖、沒有 120s admission 競爭
- ✅ marker 保留是**預期且正確**（legacy inline 不重建 → marker 不被清 → 每次開啟都早退，成本為零）
- ✅ **搜尋功能實測正常**：`messages_fts MATCH '升級'` 111 hits、`'hermes'` 5,186 hits、`'test'` 409 hits；`messages_fts_trigram MATCH 'hermes'` 5,372 hits（trigram 對 2 字中文不命中是 FTS5 trigram 正常行為，base index 負責中文）
- ✅ **回退大幅簡化**：原本擔心的 *"Downgrading is unsupported"*（僅出現在實際重建時的 log）不適用 → **回退只需換 image，不需還原 `state.db`**

唯一待觀察：`fts_layout_drift` 顯示兩個索引仍是舊版定義 —— 與 v0.23.2 行為相同（非 regression）；要收斂到 v3 佈局需 `hermes sessions optimize-storage`（opt-in 維護動作，本次不做）。

### 2.3 config 遷移 53 → 54：對我們是 no-op

上游新增 `_migrate_to_54`：移除 `prompt_caching.cache_ttl: "5m"`，**但只在該行帶有模板 seeded 的行尾註解**（`# use "1h" for long sessions with pauses between turns`）時才移除；其他 `"5m"` 視為使用者 pin → **保留**並印 ℹ 提示。

升級前在線上 pod 以 `cat -A` 取位元組級證據：

```
prompt_caching:$
  cache_ttl: 5m$
```

bare `5m`、無引號、**無行尾註解** → 不匹配遷移正則 → `seeded = False` → **保留**。另補一項條件：遷移 54 只在 `_config_version < 54` 時才執行（我們是 53 → 確實會跑），但結論是保留。

**上線後實測**：`config.yaml` 第 102–103 行仍為 `prompt_caching:` / `  cache_ttl: 5m`；`_config_version` 由 53 更新為 **54**。行為零變化。

### 2.4 上游新 prompt-cache lifecycle controller：對我們的 MiniMax 路由不成立

上游新增 `agent/prompt_cache_lifecycle/`（四項預設開啟的行為）：idle keep-alive 預熱、learned route store、cold prune、`/context` tier 行。

逐條對照我們的 `MiniMax-M3.1-Flash` / `provider: minimax`：

| 步驟 | 結果 |
|---|---|
| `is_minimax_route`（provider 在 `{"minimax","minimax-cn"}`） | ✅ True |
| anthropic wire：`is_anthropic_wire and is_minimax_route` + `_model_name_suggests_minimax_m3("minimax-m3.1-flash")` → `return False, False`（`:1394-1398`） | ✅ **不送 markers**，且此分支在 learned-route 分支**之前** return |
| chat_completions：`catalog_cache_markers()` 找不到註冊的 minimax ProviderProfile（`providers/` 內 0 筆）→ None → 落到函式尾端 `return False, False`（`:1435`） | ✅ **不送 markers** |
| warmer 門檻 `has_cache_markers(api_kwargs)` | ✅ **無 markers → 不 keep-alive 預熱 → 無額外花費** |
| learned route 樣本 | ✅ 從不送 markers → 永遠沒有樣本 → 不會出現 marker 抑制 |

**上線後實測佐證**：`/opt/data/cache/prompt_cache_routes.json` 與 `/opt/data/cache/pruned/` **皆未生成**；而 agent log 顯示 **prompt cache 命中 98%**（`cache=103936/106021`）—— MiniMax-M3 的**伺服器端自動前綴快取**照樣生效，所以我們不必送 markers 也有高命中率。

### 2.5 Telegram 插件：2 檔、+5/−5 行的機械式改寫

`plugins/platforms/telegram/` 在本視窗只有 `adapter.py` 與 `telegram_dm_topic_send.py` 兩個檔案差異，且 **100% 是 `hermes_state` → `persistence` 的機械式改寫**（`db.delete_telegram_topic_binding(...)` → `persistence.routing.delete_topic_binding(...)`）。我們用到的 3 個 Telegram config key（`telegram.reactions`、`telegram.allowed_chats`、`telegram.extra.rich_messages`）在 v0.23.3 的 `hermes_cli/config_defaults.py` 中**行號與內容完全不變**。

對比上一輪 v0.23.1→v0.23.2 同區間是 **46 檔大改** —— 本輪風險實測極低。

### 2.6 自訂層移植：62 個 commits 零衝突

上游 `Dockerfile` / `docker/` / `docker-compose.yml` / `.env.example` 在本視窗**完全未動** → 自訂層零重疊。

- `git merge-tree --write-tree upstream-v0.23.3 my-config-v0.23.2` 實測：17 個 `CONFLICT (modify/delete)` **全部在 `.github/workflows/`**，其餘 0 衝突
- 62 個自訂 commits（排除舊 purge commit）**一次 cherry-pick 完畢，exit 0，零衝突**
- Dockerfile 自訂層 **15/15 marker** 全數在位，base image `debian:trixie-20261020@sha256:4c25275446ca371766b8b093c696782eabce06263fccacb8d5d813b3dc44b308` 不變
- workflow purge 重做：上游 48 個 workflow（新增 `canary-e2e.yml`）→ 只留我們的 `ghcr-publish.yml`
- `pnpm-lock.yaml` 我們與上游**無本地分歧** → 自動繼承上游安全更新（`follow-redirects 1.16.1→1.16.2`、`joi 18.2.9→18.3.1`）；`scripts/build/node-deps.mjs` 零改動

---

## 3. 線上驗證結果

| 項目 | 結果 |
|---|---|
| Pod / Digest | `hermes-agent-5676f5cb65-5bclq`（`1/1 Running`、`RESTARTS 0`、IP `10.42.0.96`），`imageID` 與 multi-arch index digest `sha256:90eace7745088aa3b3be8beecde7224f4fe91d282cf7a7d3dad9ed19ffbc04f0` 一致 |
| 版本 | `Hermes Agent vv0.23.3 (2026.9.24) · upstream 67246ec0`（Python 3.14.9 / SQLite 3.53.1 / OpenAI SDK 2.54.0） |
| 開機 log | `✓ telegram connected`、`✓ api_server connected`、`set_my_commands OK (60 cmds)` × 3 scopes；**部署後 `errors.log` 0 ERROR / 0 CRITICAL** |
| 資料庫 | `PRAGMA integrity_check = ok`、`schema_version = 33`、`sessions = 134`、`messages = 18,340`（與升級前完全一致）、兩套 FTS 索引 18,340 / 18,340 |
| doctor | `✓ Config version up to date (v54)`、`✓ No deprecated config keys or env vars`、22 個 hub-installed skills；`Found 1 issue(s)`（缺選用 API keys）與 v0.23.2 基線一致 |
| 自訂層 | `HOME=/opt/data`、`sshd` `rsync` `tini` `tmux` `ffmpeg` `ffprobe` `rg` `node` `npm`、`en_US.utf8` + `zh_TW.utf8`、`entrypoint-ssh.sh`、`/tmp/.npm-cache`、`edge_tts` `firecrawl` `lark_oapi` `exa_py` `dingtalk_stream` `faster_whisper` `av` 全數正常 |
| **Telegram 往返** | ✅ 08:24 下達升級後檢查指令 → 08:24:57 收到 2,839 字回覆（4 次 API 呼叫，63.7s），報告涵蓋版本/環境/DB/日誌/STT/磁碟/記憶體/API/Tools 全部項目，結論「升級成功，核心全數正常」 |
| STT | ✅ 兩個 venv（gateway 用的 `/opt/hermes/.venv` 與新 staged `714f77f4`）端到端中文轉錄都通過；`local.language=zh` 未被升級洗掉 |
| staged venv | ✅ 自動輪替（`4a07758b` → `714f77f4`），舊環境已被 pm 清掉，`/opt/data/installs` 無殘留累積 |
| prompt cache | ✅ 實測命中 **98%**（`cache=103936/106021`） |

### 既有上游噪音（維持不修，與 v0.23.2 基線一致）

- `⚠ install out of sync (pnpm: not installed or outdated)` —— 上游 `pm.drift()` 缺陷
- `⚠ /v1/skills 500 (include_editorial)` —— 上游既有缺陷
- 舊 pod 關閉時 shared-metrics exit flush 的一次 `sqlite3.OperationalError: database is locked`（與 v0.23.3 無關）

---

## 4. 後續補充：兩個待辦（不阻擋收尾）

| # | 發現 | 實測 | 建議 |
|---|---|---|---|
| F1 | 🆕 doctor 新警告：`~/./cache/uv/` **1.7 GB 沒有任何 pruner 管**（只有 `cache/scratch/` 與 `cache/terminal/` 會被回收） | `archive-v0` 1.2G + `simple-v21` 37M + `wheels-v6` 596K | 🟡 這是 uv 的套件下載快取，**每次 pm 佈建新 venv 都會增長**，屬沒有上限的增長點。本次 staged venv 輪替就是它的來源。建議在磁碟章節加一條「每次升級後檢查 `cache/uv` 與 `installs` 累積」 |
| F2 | `/opt/data` 從 3.4G 漲到 5.7G | `.cache/uv` 1.7G（新增）/ `.cache/huggingface` 142M / `.cache/electron` 111M / `.cache/node-gyp` 67M / `installs` 1.3G | 🟢 Hermes 自身 5.7G 只佔 658G 已用空間的 0.9%；容器外來源（`/data/services/k8s-media`、`/var/lib/containerd`）量不到，**磁碟 21G 增量不歸因給 Hermes** |

---

## 5. 回退計畫（實測後簡化）

1. `~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag` 改回 `"v0.23.2"`，`kubectl --context n100-cf apply -k`。
2. ✅ **只需換 image，不需還原 `state.db`**：我們的 DB 是 legacy inline FTS 佈局，v0.23.3 未重建、未改動任何 FTS 結構 → v0.23.2 可直接讀同一個 DB。DB schema 同為 v33；config `_config_version: 54` 降回 v0.23.2 只會顯示「written by a newer Hermes」提示，不改寫設定、不阻擋啟動。
3. 仍**不依賴 `hermes sessions recover`**（底層已改寫為 `persistence/sqlite/admin/_recovery.py`，行為未稽核）。若真要還原原檔，用 `~/backups/hermes-20261121/`（`state.db` + `-wal` + `-shm` + `config.yaml` + `.env` + `.hermes/`）。
4. 驗證 Pod `1/1 Running` 與 Telegram 往返正常。
