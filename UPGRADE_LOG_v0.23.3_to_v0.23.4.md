# Hermes Agent 升級紀錄：v0.23.3 → v0.23.4

- **升級日期**：2026-11-26（跨日收尾 2026-11-27）
- **目標版本**：`v0.23.4`（官方 commit `8fc0374447313e276f6b9a2764bfc750190c966a`，2026-11-24 發布）
- **升級前版本**：`v0.23.3`（基於官方 `v0.23.3` = `caafe5389ae585ef77387a962aee05b1bcf17029`）
- **新分支**：`my-config-v0.23.4`（基底 = `upstream-v0.23.4`）
- **Image source SHA**：`9d96bba1b71045976b54e32f620a019b436eb558`（= GHCR run `45846888070` 的 `headSha`，`hermes --version` 顯示 `upstream 9d96bba1`）
- **GH Actions Run**：[`45846888070`](https://github.com/kuniakil/hermes-agent/actions/runs/45846888070)（success，8m41s：prepare 3s / amd64 7m15s / arm64 8m10s / merge 17s）
- **發布映像**：`ghcr.io/kuniakil/hermes-agent:v0.23.4`（multi-arch index）
  - index digest：`sha256:b3c78f4f41618938ee3d1be0b68037f1980afaad041d56492a863275b4d9b55f`
  - `linux/amd64` → `sha256:a46fbf3cd678fd725d07709740e3691627d86589c1406c919103bf2e4a9a19d1`
  - `linux/arm64` → `sha256:bb9f8242a53b0436b8a0e4ffc0603e17e8f3c3c7a75c31eb42cf38fbafda3c79`
- **部署環境**：K3s n100，pod `hermes-agent-5bd9f5c748-zbzdf`（`1/1 Running`、`RESTARTS 0`、IP `10.42.0.195`）
- **schema_version**：33 → **33**（無不可逆遷移；`SCHEMA_SQL` 全檔 md5 兩版相同 = byte-identical）
- **config_version**：54 → **54**（不變 → **不會觸發任何 config migration**）
- **FTS_STORAGE_VERSION**：3 → **3**（不變）
- **備份**：`~/backups/hermes-20261126/`（已驗證 `integrity_check = ok`、`schema_version = 33`、`sessions = 134`、`messages = 18,419`）；前次備份 `~/backups/hermes-20261121/`（228M）已依指示刪除
- **工作表**：`~/kubernetes/docs/worksheet-upgrade-hermes-v0.23.4-20261126.md`（私有 repo；fork 為 public，工作表含營運細節故不入專案 repo）

---

## 1. 一句話總結

`v0.23.4` 名義上是 patch，實際是 **1,122 non-merge commits / 1,316 檔 / +96,873 −6,703 / 229 PRs** 的大視窗（官方明言完整 curated notes 延至 `v0.24.0`，故風險只能靠 diff 稽核補齊）。但本視窗是**歷來最乾淨的一次**：DB `SCHEMA_VERSION`(33)、`FTS_STORAGE_VERSION`(3)、`SCHEMA_SQL`（byte-identical）、config `_config_version`(54)、Python floor、base image、`Dockerfile`、`docker/`、`docker-compose.yml`、`pyproject.toml`、`pm/lock.json`、`pnpm-lock.yaml`、`DEFAULT_CONFIG` 頂層 key 數（101）、prompt-surface snapshot —— **全部未變**。衝突面實測 **真內容衝突 = 0**（merge-tree 僅 13 個 `.github/workflows/*` modify/delete，全數由既有 purge 機制吸收）。**沒有不可逆變更 → 回退只需換 image。**

---

## 2. 關鍵技術調整與問題排除

### 2.1 零 schema 變動：連 config migration 都不會跑

| 面向 | v0.23.3 | v0.23.4 |
|---|---|---|
| DB `SCHEMA_VERSION` | 33 | **33** |
| `FTS_STORAGE_VERSION` | 3 | **3** |
| `SCHEMA_SQL`（`_schema_ddl.py` 全檔 md5） | `f222649b1a2050ee3c3929679b7d6211` | **同值** |
| config `_config_version` | 54 | **54** |
| config `SUPPORT_FLOOR_VERSION` | 12 | **12** |
| `DEFAULT_CONFIG` 頂層 key | 101 | **101**（ADDED=[]、REMOVED=[]） |

`config_defaults.py` 只多了兩個**巢狀預設值**：`display.program_status: True`（OSC 7501 終端狀態序列，容器無 TTY 無視覺影響）與 `skills.index_desc_limit: 60`。後者會縮短 skill index 描述 → **既有 session 的 prompt cache 會 miss 一次**（一次性、預期內，不需處理）。

### 2.2 衝突面 = 0 個真衝突

自訂 commits 觸及 91 檔 × 上游變更 1,316 檔 → `comm -12` 交集 13 檔。其中 12 檔是 `.github/workflows/*`（上游 v0.23.4 有 49 個 workflow，我們只留 `ghcr-publish.yml`），第 13 檔 `hermes_cli/models_catalog_static.py` 的 hunk 位置不重疊（上游改 Gemini 4 三處，我們改 MiniMax 兩處）→ 自動合併。

決定性證據：

```bash
git merge-tree --write-tree --name-only upstream-v0.23.4 my-config-v0.23.3
# → 13 個 CONFLICT (modify/delete) 全部在 .github/workflows/
# → hermes_cli/models_catalog_static.py: Auto-merging（無 CONFLICT）
```

實測移植：**71 個自訂 commits 一次 `git cherry-pick` 完畢，exit 0，零衝突**；歷史保持線性（73 commits / 0 merge）。

### 2.3 本次**沒有 venv 輪替** → `cache/uv` 無上限增長沒有發作

v0.23.3 的遺留問題 F1（`cache/uv` 無任何 pruner 管）在本視窗**沒有重演**：

- 上游 v0.23.4 **未改 `uv.lock` / `pyproject.toml`** → PM 的 `.seeded` digest 不變 → 不 re-seed → 不需要新 venv
- 線上 staged venv 仍是 `714f77f4df6f4083b3b028c8dd760de0`（**與 v0.23.3 相同**），`/opt/data/installs` 只有 1 個 install / 1 個 env → **無殘留累積**
- v0.23.3 事後報告警告的 `⚠ ~/./cache/uv/ is 1.7 GB and outside every pruner` 在本次 doctor 中**未出現**

> ⚠️ 見 2.9 —— 這個「警告消失」的原因**不是**問題已解。

### 2.4 prompt-cache lifecycle 重構：對 MiniMax 路由仍是 no-op

上游改了 `agent/prompt_cache_routes.py`（新增 `warming_rule()`、修 `_push()` 的樣本淘汰 bug）與 `agent/prompt_cache_lifecycle/warmer.py`。但 `agent/agent_runtime_helpers.py` **上游零改動**，我們的鏈路不變：

| 步驟 | 結果 |
|---|---|
| `is_minimax_route`（provider `minimax` / host `api.minimax.io`） | ✅ True |
| anthropic wire 早退 → `return False, False`（**在 learned-route 分支之前**） | ✅ 不送 markers |
| `learned_or_catalog_markers()` 找不到註冊的 minimax `ProviderProfile`（`plugins/model_providers/` 與 `providers/` 在 v0.23.4 仍無 minimax 註冊） | ✅ 不送 markers |
| warmer 門檻 `has_cache_markers()` | ✅ 無 markers → 不 keep-alive → **無額外花費** |

### 2.5 ⚠️ 更正 v0.23.3 事後報告的一個錯誤結論

v0.23.3 報告寫「永遠沒有樣本 → `prompt_cache_routes.json` 不會被建立」。**實測是錯的** —— 該檔存在，且記錄的是 **implicit** 路由：

```json
{
  "minimax|https://api.minimax.io/anthropic|MiniMax-M3.1-Flash|implicit": {
    "reads": 2, "samples": 2, "hit_gaps": [24.7], "longest_hit": 24.7
  }
}
```

**但行為結論不變**：v0.23.4 的 `warming_rule()` 對這筆 implicit entry 求值仍回 `None` ——
`_rule(implicit)` 需要 `learned_lifetime` 成立（≥2 個**不同 session** 的 miss gap 一致），我們只有 1 筆 hit gap、0 筆 miss gap；
而 `not implicit.get("reads")` 為 False → 不會 fallback 成 `no-cache` → **不預熱、不抑制 markers、無額外花費**。

v0.23.4 的 `_push()` bug 修正（單一 session 的樣本不再擠掉另一個 session 唯一的樣本）對我們**無影響**。

### 2.6 Telegram 插件：3 檔、7 行

`adapter.py`(±3)、`telegram_flood_window.py`(±2)、`telegram_vault_code.py`(±2)。相較 v0.23.1→v0.23.2 的 46 檔大改，本輪風險實測極低。我們用到的 3 個 config key（`telegram.reactions` / `allowed_chats` / `extra.rich_messages`）**完全未動**。

### 2.7 `/v1/skills` 500：上游既有缺陷，byte-identical 證據

部署後 `errors.log` 出現 `TypeError: find_all_skills() got an unexpected keyword argument 'include_editorial'`。**逐位元組驗證**：

```
v0.23.3  gateway/platforms/api_server.py:2392  skip_disabled=False, include_editorial=True
v0.23.4  gateway/platforms/api_server.py:2392  skip_disabled=False, include_editorial=True
v0.23.3  tools/skills_tool.py:277  def find_all_skills(*, skip_disabled: bool = False)
v0.23.4  tools/skills_tool.py:277  def find_all_skills(*, skip_disabled: bool = False)
# git diff upstream-v0.23.3 upstream-v0.23.4 -- <兩個檔> → 零 diff
```

→ 上游既有缺陷，維持不修；對我們無影響（Telegram 的 `/skills` 走另一條路徑）。

### 2.8 清理：消除 2.7 G 的無主快取

升級驗證過程中，STT 測試下載了 `faster-whisper` **small** 模型（462 M blobs + 2.6 M snapshot），加上兩個**過期三個月**的 uv 預設快取。逐一核對歸屬後清除：

| 目標 | 大小 | 歸屬 | 處置 |
|---|---|---|---|
| `hub/models--Systran--faster-whisper-small/` | 2.6 M | 我的 STT 測試下載 | 🗑 刪除 |
| `hub/blobs/42/`（含 `.refs` 只指向 small 的 `3e305921…`） | 462 M | 同上 | 🗑 刪除 |
| `/opt/data/.cache/uv` | 1.2 G | uv 自己的 per-user 預設快取，mtime **2026-08-21** | 🗑 刪除 |
| `/opt/data/home/.cache/uv` | 1.1 G | 另一個 HOME 解析路徑，mtime **2026-08-21** | 🗑 刪除 |
| `/opt/data/cache/uv` | 958 M | **pm 的 hermes-owned 快取**（`pm/packages.py:uv_cache_path()`），doctor 唯一會掃的那個 | ⚠️ **保留**（刪了只會被 re-seed 回來） |

刪除前確認：`blobs/42/*.refs` 內容只有 small 模型的 sha；**base 模型的權重在自己的 snapshot 內**（145,217,532 B 實檔），不受影響。刪除後 STT 端到端複驗：兩個 venv 都能用 base 模型正確轉錄中文。

**`/opt/data`：4.8 G（升級前）→ 6.2 G（驗證高峰）→ 3.5 G（清理後）= 淨減 1.3 G。**

### 2.9 ⭐ doctor 的 `cache/uv` 警告有盲區 —— 警告不亮 ≠ 問題不存在

uv 的快取同時存在**四個**位置，doctor 只掃其中一個：

| 路徑 | 大小 | mtime | doctor 掃嗎 |
|---|---|---|---|
| `/opt/data/cache/uv` | **958 M（0.852 GiB）** | 2026-11-27 00:09 | ✅ **會掃** |
| `/opt/data/.cache/uv` | 1.2 G | 2026-08-21 | ❌ |
| `/opt/data/home/.cache/uv` | 1.1 G | 2026-08-21 | ❌ |
| `/opt/hermes/uv-cache` | 957 M | image 內唯讀 payload | ❌ |

- **doctor 的 pruner 偵測邏輯完全沒變**：`hermes_cli/doctor_state.py` 在 v0.23.3→v0.23.4 **零 diff**；`unpruned_cache_hogs()` 只掃 `hermes_home/"cache"` 一層。
- **警告消失的真實原因**：`/opt/data/cache/uv` 在 v0.23.3 的 F1.1 清理後**根本不存在** → doctor 沒東西可報。2026-11-27 00:09（升級驗證那一輪觸發的 pm sync）把它**重新 seed 回 958 M**，`.seeded` digest = `3501084a…+payload2`，**與 v0.23.3 記錄的 digest 相同** → 再次證實 uv.lock 沒變。
- **為何現在還是不亮**：門檻 `_UNPRUNED_CACHE_WARN_BYTES = 1 << 30` = **1 GiB**；目前 **0.852 GiB，差 151 MiB**。照 11/21 的成長曲線（1.7–1.9 G）**再長 151 MiB 就會重新亮起**。

> **可複用的判準**：doctor 的「outside every pruner」是**門檻型滯後指標**，且只涵蓋四個 uv 快取中的一個。**不可用它當作「問題已解」的證據**；可靠做法是每次升級後手動 `du -sh /opt/data/cache/uv`。

### 2.10 Hermes 自查報告的 4 處更正（升級後由 Hermes 自行產生的巡檢報告）

Hermes 在 Telegram 上做的 v0.23.4 巡檢，**核心判定全部正確**（版本、sessions 134、integrity ok、FTS 一致、triggers 14 未動、admissions 24、Config v54、STT 雙 venv 端到端、`/v1/skills` 是上游既有缺陷、API 44 項、22 skills、30 tools），但有 4 處需要更正：

| # | 它的說法 | 實測 | 判定 |
|---|---|---|---|
| 1 | 「部署後 ERROR 0 筆」 | **2 筆 ERROR + 19 筆 WARNING**（`00:02:54 /v1/skills failed`、`00:04:17 MiniMax API 500 Streaming failed`）—— 其中 `/v1/skills` 那筆它自己還引用為「已知缺陷」，屬自我矛盾 | ❌ 錯 |
| 2 | 「cache/uv 1.3G 仍在；doctor 的 pruner 偵測邏輯變了」 | 量的是 `/opt/data/.cache/uv`（**8/21 的舊目錄**）；doctor 邏輯 byte-identical 未變；真因見 2.9 | ❌ 錯 |
| 3 | 「messages +79（18,425）」「`/opt/data` 從 5.7G 降到 5.2G」 | 基期用錯（拿 v0.23.3 報告的 11/21 數字比，非升級前實測）。真實：messages 18,419 → 18,425 = **+6**；`/opt/data` **4.8 G → 5.2 G = +400 M** | ⚠️ 基期需更正 |
| 4 | 「huggingface +462M，沒量到是誰觸發的，不歸因」 | 來源**已知**：升級驗證自己的 STT 測試下載了 `small` 模型 → 是**測試副作用**，非升級副作用，且已清理 | ⚠️ 可歸因 |

> 教訓：**巡檢 agent 讀到舊文件當基期、量錯目錄、漏數 ERROR 等級**——這些都是它自己報告裡的自我矛盾。驗收時必須**獨立複算**，不能只讀它的結論。

---

## 3. 線上驗證結果

| 項目 | 結果 |
|---|---|
| Pod | `hermes-agent-5bd9f5c748-zbzdf`，`1/1 Running`，`RESTARTS 0`，IP `10.42.0.195` |
| imageID | `sha256:b3c78f4f…`（**與 build index digest 完全一致**） |
| 版本 | `Hermes Agent vv0.23.4 (2026.9.24) · upstream 9d96bba1` |
| 開機 log | `✓ telegram connected`、`✓ api_server connected`、`set_my_commands OK (60 cmds)` × 3 scopes |
| DB | `integrity_check = ok`、`schema_version = 33`、`sessions = 134`、`messages = 18,419` → `18,452`（含巡檢回合）、`messages_fts` = `messages_fts_trigram` = `messages`（三者恆等） |
| FTS | `fts_tool_full_content_high_water` = `'16551'` **仍保留** → **沒有重建**（`SCHEMA_SQL` byte-identical + legacy inline 佈局依設計跳過），搜尋功能正常 |
| triggers | **14**（messages 13 + sessions 1）—— 與 v0.23.3 基線相同 = **未動** |
| doctor | `✓ Config version up to date (v54)`、`✓ No deprecated config keys or env vars`、`✓ Managed scope active: 0 config key(s) pinned`、`✓ Runtime venv staged`、44 項 API 全通、22 hub skills、`Found 1 issue(s)`（缺選用 API keys，**與 v0.23.3 基線一致**） |
| 自訂層 | **15/15 marker 全數正常**（`HOME=/opt/data`、`sshd` `rsync` `tini` `tmux` `ffmpeg` `ffprobe` `rg` `node` `npm`、`en_US.utf8`+`zh_TW.utf8`、entrypoint shim、`edge_tts` `firecrawl` `lark_oapi` `exa_py` `dingtalk_stream` `faster_whisper` `av`） |
| STT | `stt.language: 'zh'` 未被洗掉；`faster_whisper 1.2.1`；**兩個 venv** 端到端中文轉錄通過（清理後複驗仍通過） |
| Telegram 往返 | 00:01:15 inbound → 00:03:08 response，14 次 API 呼叫 / 112.6s / 2,979 字 |
| 磁碟 | `/opt/data` 4.8 G → **3.5 G**（清理後）；主機 671 G / 1.8 T（39%） |

### 既有上游噪音（維持不修，與 v0.23.3 基線一致）

- `⚠ install out of sync (pnpm: not installed or outdated)` —— 上游 `pm.drift()` 缺陷
- `GET /v1/skills` → 500（`include_editorial` TypeError）—— 上游既有缺陷（見 2.7）
- `Security posture audit: SSH password authentication is ENABLED` —— 我們的 sshd 設定，非上游缺陷

---

## 4. 後續補充

| # | 發現 | 狀態 |
|---|---|---|
| F1 | ⭐ doctor 的 `cache/uv` 警告有盲區 + 1 GiB 門檻 → **不可當作「已解」的證據** | ✅ 記錄（2.9）；可靠做法是每次升級後手動量 |
| F2 | `cache/uv` 與 huggingface blob 是無上限增長點 | ✅ 本次清掉 small 模型 + 兩個 8/21 舊 uv 快取（−2.7 G）；pm 的 `cache/uv` 保留（刪了會 re-seed） |
| F3 | Hermes 巡檢報告的 4 處錯誤（ERROR 級別漏數、量錯目錄、基期用錯、漏歸因） | ✅ 記錄（2.10）；**驗收一律獨立複算** |
| F4 | `skills.index_desc_limit: 60` 新預設 → 既有 session prompt cache 一次性 miss | ✅ 預期內，不處理 |

---

## 5. 回退計畫

1. `~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag` 改回 `"v0.23.3"`，`kubectl --context n100-cf apply -k`。
2. ✅ **只需換 image，不需還原 `state.db`**：
   - DB `SCHEMA_VERSION` 同為 33、`SCHEMA_SQL` byte-identical → v0.23.3 可直接讀同一個 DB。
   - config `_config_version` 兩版皆 **54** → 降回 v0.23.3 **不會**有「written by a newer Hermes」提示。
   - 唯一不對稱：v0.23.4 新增的 `skills.index_desc_limit` 在 v0.23.3 不存在 → v0.23.3 會忽略它（其 doctor 有 deprecated-key 檢查，是否報 unknown key 需回退時實測確認）。
   - v0.23.3 的 `_migrate_to_54` 只在 `_config_version < 54` 時跑；我們是 54 → 不會跑 → `prompt_caching.cache_ttl: 5m` 原樣保留。
3. 若真要還原原檔，用 `~/backups/hermes-20261126/`（`state.db` + `-wal` + `-shm` + `config.yaml` + `.env` + `.hermes/`）。
4. 驗證 Pod `1/1 Running` 與 Telegram 往返正常。
