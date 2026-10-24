# Hermes Agent 升級工作表：v0.22.2 → v0.22.4

- **目標版本**：`v0.22.4`（commit `4d04303818`，2026-10-21 發佈）
- **中間版本**：`v0.22.3`（commit `5b147ab036`，2026-10-21 發佈，**已被 v0.22.4 包含**，不需單獨升）
- **升級前版本**：`my-config-v0.22.2`（HEAD `aa29838bec`，基於官方 `v0.22.2` = `d923a5eb48`）
- **新分支**：`my-config-v0.22.4`
- **Remote**：`origin` = 官方（NousResearch）、`kuniakil` = 個人 fork（⚠️ 兩者名稱與 OpenClaw 相反）
- **發布模型**：`my-config-v0.22.4` 分支為 source of truth，由 `ghcr-publish.yml`（dispatch input **`tag_name`**）建置 `ghcr.io/kuniakil/hermes-agent:v0.22.4`
- **目前上線版本**：`v0.22.2`（K3s n100，pod `hermes-agent-c84ddfc-lvjm8`，0 restarts）
- **狀態**：✅ **已完成升級並部署**（2026-10-22）
- **最終 HEAD**：本分支最新 commit（升級紀錄 commit；`git log -1 my-config-v0.22.4`）
- **GHCR digest**：`sha256:079618425a6ded8c63b7733c8bf848087eeb3eb4efe5120be5e7547c88b25d1c`
- **GH Actions Run**：`39733973873`（prepare / linux-amd64 / linux-arm64 / merge 全部 success）
- **資料完整性**：sessions 127 / messages 17,671（升級前後一致，integrity ok）
- **schema_version**：31 → **32**（additive，無資料遷移）
- **備份**：`~/backups/hermes-20261022/state.db`（175,075,328 bytes，integrity ok）
  - 🔴 **已於 2026-10-24 14:21 刪除**（使用者明確指示；由 `~/backups/hermes-20261024/` 取代）。
- **日期**：2026-10-22

---

## 0. ⚠️ 最高優先結論：這次是「巨型收斂版」，不是小 patch

先講清楚三件事，因為它們決定了這次升級的風險等級：

### 0.1 v0.22.3 是 2,911 commits / 4,206 檔的巨型收斂版

官方 v0.22.3 Release Notes 原文：

> Patch release. This tag rolls up the **~620 PRs merged since v0.22.2** into a stable release…
> **Full curated release notes for this window ship with v0.23.0.**

| 比較基準 | 檔案數 | +/− | 意義 |
|---|---|---|---|
| `v0.22.2 → v0.22.3` | 4,206 | +360,278 / −64,308 | **約 620 個 PR 的收斂** |
| `v0.22.3 → v0.22.4` | 82 | +1,475 / −3,022 | 純 patch（Desktop / plugin / dashboard 修補） |
| **`v0.22.2 → v0.22.4`** | **4,242** | **+361,206 / −66,783** | **本次實際升級幅度** |

> 🔴 **官方把這個 window 的 curated release notes 延到 v0.23.0**。
> 換句話說：**v0.22.3/v0.22.4 的「人讀版变更說明」不存在**，我們必須自己從 diff 盤點（見 §2）。
> 這是本次升級最大的「資訊落差」，不是程式碼風險。

**拓撲已驗證（可安全跳版）**：

```
git merge-base --is-ancestor upstream-v0.22.3 upstream-v0.22.4  → YES
git merge-base --is-ancestor upstream-v0.22.2 upstream-v0.22.4  → YES
```

→ **v0.22.4 是 v0.22.3 的後代、v0.22.2 的後代 → 直接跳 v0.22.2 → v0.22.4 合法，不需要中間跳板。**

### 0.2 🔴 gateway runtime ledger 機制「正確版」回來了（v0.22.2 是臨時回滾版）

v0.22.2 是官方為了撤回錯誤出貨的 v0.22.1 而做的**臨時回滾版**（我們上一張工作表的 §0）。v0.22.4 則是**把整套 gateway runtime 以修正版重新落地**：

| 項目 | v0.22.2（現行） | v0.22.4（目標） | 判定 |
|---|---|---|---|
| `hermes_state_common.py: SCHEMA_VERSION` | **31** | **32** | ⚠️ +1 |
| `runtime_epoch` / `session_admissions` / `worker_executions` / `worker_receipts` | 表存在但**無人寫入**（v0.22.1 殘留） | **重新寫入 + 有刪除路徑** | 🔴 見下 |
| `hermes_state_mutation_retirement.py` 等 18 個 ledger 模組 | ❌ 不存在 | ✅ **全部回來** | |
| `sessions_runtime_ledger_delete_guard` trigger | ❌ 不存在 | ✅ **新增** | |
| `sessions` 新增欄位 | — | `transcript_revision` 等 3 欄 | ✅ additive |
| `FTS_STORAGE_VERSION` | **3** | **3** | ✅ 未變 |

**對我們的實際意義（兩面）**：

| 面 | 影響 |
|---|---|
| 🟢 **v0.22.2 那個「session 刪不掉」的老問題** | v0.22.4 的刪除路徑**會先清 ledger 再刪 session**（`mutation_retirement` 回來了）→ **問題不會復發** |
| 🔴 **回滾變成單向** | v0.22.4 一旦跑起來就會**重新寫入 `session_admissions`**；此時再退回 v0.22.2 image，那個「刪不掉」限制會**再次生效且無法用 v0.22.2 解決** → **本次備份是 MANDATORY，且升級後回滾等於「不倒退」** |
| 🟡 `sessions_runtime_ledger_delete_guard` trigger | 會被寫進我們的 `state.db`；若日後**降級**到 v0.22.2，該 trigger 會攔截刪除（這正是官方設計的護欄） |

**既有 ledger 現況（n100 實測，2026-10-22）**：

```
session_admissions  : 0   ← v0.22.2 升級時已清乾淨（Phase D9.2）
worker_executions   : 0
worker_receipts     : 0
runtime_epoch       : 1
```

→ 起升前是**乾淨起點**，v0.22.4 會從 0 重新長 ledger，這是預期行為。

### 0.3 FTS：我們的 DB 停在舊版 layout，v0.22.4 讓它「被看見」但仍不自動動

v0.22.4 新增 FTS layout registry（`FTS_VTABLE_LAYOUTS`）與結構化偵測（doctor / update notice / optimize-storage 共用 `fts_layout_drift()`）。

我們生產 DB 的實測 layout（唯讀）：

```
messages_fts          :: CREATE VIRTUAL TABLE messages_fts USING fts5( content )
messages_fts_trigram  :: CREATE VIRTUAL TABLE messages_fts_trigram USING fts5( content, tokenize='trigram' )
state_meta.fts_optimize_available = 1        （v0.22.2 時代就已經標記「有優化工作」）
state_meta.fts_storage_version      = （不存在）
```

| 判定 | 說明 |
|---|---|
| 🟡 **屬於舊 layout**（在 registry 的舊清單內） | v0.22.4 會報「layout drift」，doctor / 更新提示會看見它 |
| 🟢 **不會在 open 時自動重建** | `base_index_realigned_on_open()` 要求 base index 含 `tool_name` 且無 `messages_fts_src`；我們的 base index 沒有 `tool_name` → **不是 on-open realign** |
| 🟢 **維持 opt-in** | 仍由 `optimize-storage` 手動觸發；本次升級**不執行**（175MB / 17,671 則，重建耗時且會改寫索引） |
| ℹ️ 既有行為 | v0.22.2 早已把 `fts_optimize_available=1` 寫進 state_meta → **這不是本次新增的問題**，只是 v0.22.4 讓它「講得更清楚」 |

### 0.4 決策點（Go-Sign 時請一併回覆）

| # | 決策 | 建議 | 理由 |
|---|---|---|---|
| **A** | 目標版本 | **v0.22.4**（不單獨停 v0.22.3） | v0.22.4 ⊇ v0.22.3，且含 Desktop/plugin/dashboard 修補 |
| **B** | 是否等到 **v0.23.0**（官方才會補齊 620 PR 的 curated notes） | **不等** | 我們已用 diff 完成盤點（§2、§3）；v0.22.4 是目前最新穩定版；等 v0.23.0 意味著繼續停在臨時回滾版 v0.22.2 |
| **C** | **npm 漏洞**是否修 | **維持「不修」** | 觸發條件 #133435 / #132924 / #79021 **今日複查仍全為 OPEN**；實際 runtime 暴露面 = 0（見 §6） |
| **D** | FTS layout 漂移是否在本次順手 `optimize-storage` | **不做** | 屬 pre-existing 狀態，非本次升級造成；重建 175MB 索引需停機且有風險，另開一次專案處理 |

---

## 1. 官方 Release Notes 稽核

### 1.1 v0.22.4（2026-10-21）

> Patch release. Desktop stops showing suggestion pills above the composer, plus small plugin and dashboard fixes.

| 項目 | 對我們 | 判定 |
|---|---|---|
| Desktop 不再顯示 composer 上方的 suggestion pills（`#142559`） | 我們不部署 Electron desktop | 🟢 無影響 |
| Plugins 沒有依賴時跳過 dependency consent（`#142569`） | 我們不用 plugin 安裝 | 🟢 |
| Dashboard: WhatsApp 登出後可安全 re-pair（`#142439`） | 我們不用 WhatsApp | 🟢 |
| Desktop plugin review: surface lint 不再標 prototype writes（`#142586`） | 同上 | 🟢 |
| Desktop approval-mode chip 跟隨 active profile（`#142565`） | 同上 | 🟢 |
| Release builds: desktop bundle pre-build 檢查有足夠時間驗證 archived inputs（`#142623`） | 同上 | 🟢 |
| Plugin catalog 新增：bubblewrap、Singularity/Apptainer、mcp-serve、agent-importers、inbox、workflow-record；Telegram Business 移到 community tier | catalog 資料更新 | 🟢 不自動安裝 |

### 1.2 v0.22.3（2026-10-21）— 官方刻意不列細節

官方在 Release Notes 中「on purpose」不逐條列出的內容（我們照抄原文重點，作為稽核線索）：

- MCP progress notifications 以 live tool progress 串流
- 經典 CLI 版面重做（glyph transcript、composer 下方 status line、兩行 header）
- **Plugin 可宣告 OAuth client**，Hermes 負責簽入與 refresh
- `hermes plugins update` 提供所有可用的 plugin 更新 + git 安裝 plugin 的 Update 按鈕
- Desktop 可 steering / 編輯已排隊的 prompt
- Desktop 引導式 subagent model / provider 選擇器
- CLI / TUI 的 `/loop` live countdown 列
- 選用的 Telegram DM topic 轉移
- `post_compaction` plugin hook
- capabilities catalog
- Microsoft Store build 在 release 發佈時自動上架
- **session auto-prune 回到 opt-in，並在磁碟吃緊時一次性提示**
- 本機 runtime 的 Nemotron 3.5 Bolt 與 one-slot DFlash drafts
- 數十個新的 plugin catalog 条目

> 🔴 其中 **「session auto-prune 回到 opt-in」直接影響我們的 config**：我們 `sessions.auto_prune: false`（config.yaml:507）→ 維持關閉，**不會**被開；但「磁碟吃緊時的一次性提示」是新提示面，部署後需確認不會在 Telegram 亂發訊息。

### 1.3 Breaking Changes / Deprecations 稽核

**兩份 Release Notes 都沒有 `Breaking Changes` 或 `Deprecations` 章節。** 但因為 v0.22.3 是 620 PR 的收斂，隱含行為變更必須自行盤點（§2、§3 已做）。

| 隱含變更 | 說明 | 等級 |
|---|---|---|
| ❌ gateway runtime ledger 重新啟用 | v0.22.2 的「臨時回滾」結束；`session_admissions` 重新寫入 | 🔴 高 |
| ❌ `SCHEMA_VERSION` 31 → 32 | 宣告形狀變更；官方註明 **no data migration**（additive + idempotent） | 🟡 |
| ⚠️ 新增 `sessions_runtime_ledger_delete_guard` trigger | 降級後會攔截 session 刪除（官方設計的護欄） | 🟡 |
| ⚠️ 新增 FTS layout registry 與 doctor 偵測 | 我們的 DB 會被標記為 layout drift（既有狀態，非新增） | 🟡 |
| ⚠️ `sessions_runtime_ledger_delete_guard` + `messages_transcript_revision_update` trigger | `sessions.transcript_revision` 新欄位，message 更新時遞增 | 🟢 additive |
| ⚠️ config migration 階梯回到 51 | 我們 config 已是 **51** → **不會有任何 migration 執行**（同 v0.22.2 的情況） | 🟢 |

### 1.4 機器可讀真相（Dependency / Runtime 稽核）

| 項目 | v0.22.2 | v0.22.4 | 判定 |
|---|---|---|---|
| `pyproject.toml` `requires-python` | `>=3.11,<3.15` | `>=3.11,<3.15` | ✅ 不變（容器 Python 3.14.7 相容） |
| `pyproject.toml` 新依賴 | — | **`ruamel.yaml.clib==0.2.15`**（py≥3.14 且 linux x86_64/aarch64） | 🟡 **新增 C 加速**，官方註明：原本純 Python 解析 YAML 讓 gateway 開機慢 ~5s → **對我們 K3s 開機有正收益** |
| ↳ cp314 wheel 可用性 | — | cp314 manylinux2014 **x86_64** ✅ / **aarch64** ✅ | ✅ 兩種架構都有 wheel，amd64 + arm64 build 都不會掛 |
| `PyJWT` | 2.13.0 | **2.15.1**（+GHSA-ffc3-869f-jxw9、GHSA-42vr-xj54-vc7v） | 🟢 安全 bump |
| `urllib3` | `>=2.7.0,<3` | **`>=2.8.0,<3`**（GHSA-8988/ gh4c / vxq7） | 🟢 安全 bump |
| `uv.lock` blob | `765bf23d7c` | `579494c2dd` | ✅ 隨上述變更 |
| `pm/lock.json` | `800fdda389` | `780b8d195a` | 🟢 僅 `llamacpp` b11370→b11671（**本機模型** runtime，我們不用） |
| `Dockerfile` blob | `e3d11031c8` | **`e3d11031c8`** | ✅ **位元組相同** → 我們 8 處補丁零衝突 |
| `docker/stage2-hook.sh` blob | `48eb36f5a9` | **`48eb36f5a9`** | ✅ 位元組相同 |
| `docker/entrypoint-dispatch.sh` | 存在 | 存在 | ✅ 我們的 `entrypoint-ssh.sh` 依賴它，仍可用 |
| `scripts/write_install_stamp.py` | 存在 | 存在，**零 diff** | ✅ 我們的 workflow 呼叫簽章不變 |
| `hermes_state_common.py: SCHEMA_VERSION` | 31 | **32** | ⚠️ +1（additive） |
| `hermes_state_common.py: FTS_STORAGE_VERSION` | 3 | **3** | ✅ 未變 |
| config migration 最高階梯 | 50 | **51** | 🟢 我們 stamp = 51 → 不執行任何 migration |
| 根 `package-lock.json` `overrides` | `{}`（None） | `{}`（None） | ✅ 維持「不修」決策的前提成立 |
| `plugins/platforms/photon/sidecar/package-lock.json` | undici 7.29.0 | **undici 7.30.0**（新增 `overrides`） | 🟢 上游修了 undici advisory；photon 我們未啟用 |

### 1.5 Schema / 不可逆性判定

> **官方原始碼註解（`hermes_state_common.py` v0.22.4）**：
> `v32 (#140315): no data migration. … its catch-up is the declarative executescript(SCHEMA_SQL) + _reconcile_columns() every writable open already runs (additive, idempotent). The bump only records that the declared shape changed; a new table or column needs no bump.`

**判定：schema 變更是 additive + idempotent，無需人工 DB 遷移。**

但仍列為 **MANDATORY 備份**，理由不是 schema 遷移，而是：

1. **回滾會被 ledger 單向鎖死**（§0.2）：v0.22.4 寫入 ledger 後，退回 v0.22.2 image 會讓帶 ledger 歷史的 session 刪不掉 → 沒有備份就等於沒有回滾路徑。
2. v0.22.2 本身是官方承認的臨時回滾版；我們連續兩版都處在「官方自己也說不是最終形態」的狀態。
3. 成本極低（175MB，`kubectl cp` 數分鐘）。

**判定：非不可逆，但備份列為 MANDATORY。**

---

## 2. Diff 稽核（`upstream-v0.22.2 → upstream-v0.22.4`）

### 2.1 關鍵路徑

| # | 路徑 | 上游變更 | 影響 |
|---|---|---|---|
| 1 | **`Dockerfile`** | **零 diff（blob 相同）** | 🟢 8 處自訂補丁可原樣套用 |
| 2 | `docker/stage2-hook.sh` | 零 diff（blob 相同） | 🟢 我們的 SSH + npm cache 補丁可原樣套用 |
| 3 | `docker/entrypoint-dispatch.sh` | 存在 | 🟢 `entrypoint-ssh.sh` 的 exec 目標仍有效 |
| 4 | `docker-compose.yml` | 上游有，但我們覆寫 | 🟢 沿用我們的 |
| 5 | `AGENTS.md` | **零 diff** | 🟢 我們的 Mac host 保護區塊直接帶過去 |
| 6 | `.github/workflows/` | 54 → **約 55 檔**（新增 `catalog-tests.yml`、`windows-desktop-attach-e2e.yml`、`docs-search-monitor.yml` 等） | 🟢 依 Purge 規則全刪，只留我們的 `ghcr-publish.yml` |
| 7 | `hermes_state_*.py` | **+18 個 ledger/runtime 模組回來**、+170 行 `hermes_state_common.py`、+120 行 `hermes_state_schema.py` | 🔴 §0.2 |
| 8 | `hermes_state_fts.py` | +117 行（layout registry、`fts_layout_drift`、`_stamp_settled_fts_layout`） | 🟡 §0.3 |
| 9 | `gateway/` | **256 檔 / +43,748 / −17,198** | 🔴 核心部署路徑（`status.py` 重寫、新增 `status_lock_dir.py` / `status_scoped_locks.py` / `session_worker_*.py`） |
| 10 | `agent/` | 新增 40+ 檔（compression automation、memory context、model metadata cache、LSP、tool progress relay…） | 🟡 |
| 11 | `acp_adapter/` | 全新 22 檔（ACP 協定） | 🟢 我們未使用 |
| 12 | `tools/mcp_tool*` | 新增 per-tool cost / per-chat spend limit | 🟢 預設關閉 |
| 13 | `hermes_cli/update_downgrade_guard.py` | **存在**（v0.22.2 沒有） | 🟢 官方護欄，不影響我們的 image 發布模型 |
| 14 | `apps/desktop/`、`ui-tui/`、`web/` | 大量變更 | 🟢 不影響容器 runtime |
| 15 | `plugin-catalog/` | 新增 6 個 catalog 條目 | 🟢 僅資料 |

### 2.2 衝突面計算（已驗證）

```
我們自訂 commit 觸及：   63 檔
上游 v0.22.2→v0.22.4：  4,242 檔
重疊：                   54 檔  ← 全部是 .github/workflows/*（Purge 規則直接刪除，不需解決）
```

> ✅ **結論：唯一重疊是 workflows，其餘 Dockerfile / docker/ / docker-compose.yml / AGENTS.md / .env.example 零重疊。**
> 這是「自訂補丁面」與「上游變更面」完全正交的一次升級——因為我們的 8 處 Dockerfile 補丁對上游 Dockerfile blob 仍是 8 個 hunk（`git diff upstream-v0.22.4 my-config-v0.22.2 -- Dockerfile | grep -c '^@@'` = **8**，已驗證）。

---

## 3. 需攜帶的自定義補丁

我們的 Dockerfile 對上游的差異共 **8 個 hunk**（已驗證）：

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

自訂 commit 清單（`upstream-v0.22.2..my-config-v0.22.2`，12 個）：

| # | commit | 說明 | 處置 |
|---|---|---|---|
| 1 | `4d357b09a7` | `chore(ci)`:purge 官方 CI，只留 `ghcr-publish.yml` | 🔁 **重做**（在新分支 purge） |
| 2 | `1a4b19dc56` | `fix(docker)`:還原 `docker/entrypoint-ssh.sh` | ✅ cherry-pick |
| 3 | `546b50ca14` | `chore`:帶入 `docker-compose.yml`（`HERMES_IMAGE` / `TZ=Asia/Taipei`） | ✅ |
| 4 | `931b5155bd` | `chore`:Mac host 資源限制規則 → AGENTS.md | ✅ |
| 5 | `252c101541` | `feat(docker)`:stage2 SSH 設定 + npm cache | ✅ |
| 6 | `37440326bf` | `feat(docker)`:re-port custom layer（8 處補丁） | ✅ **可整顆 cherry-pick**（Dockerfile blob 相同 → 預期零衝突） |
| 7 | `6b44a28d7b` | `chore(env)`:`.env.example` 記錄 `HERMES_IMAGE` | ✅ |
| 8 | `26575c8a21` `78e0781c5e` `137c46cda1` `aa29838bec` | v0.22.2 的 worksheet / upgrade log / post-mortem | ✅ 歷史文檔保留 |

> 📌 `.env` 風險持續解除：commit `27c377fdb4`（v0.22.1 時期）已把 `.env` untrack 並 gitignore；Phase A8 會再跑一次「tracked-but-ignored 遺失偵測」確認。

### 3.1 上游 AGENTS.md 是否有新規則需合併

- [x] §3.1 檢查完畢：`git diff upstream-v0.22.2 upstream-v0.22.4 -- AGENTS.md` **零 diff**；我們的 Mac host 保護區塊原樣帶過去（`git grep -c 'Local Resource Constraint' = 1`）

---

## 4. 執行步驟 checklist

### Phase 0 — 停機前盤點 + 備份（MANDATORY）

> ⚠️ **n100 上無免密 sudo**（`sudo -n` 失敗），資料目錄 `/data/services/hermes/data` 對 SSH 使用者 `kuniaki` **Permission denied** → **備份一律走 `kubectl cp`**（沿用 v0.22.2 做法）。

- [x] 0.1 確認無使用中：`kubectl exec ... -- python3` 查 24h 內訊息數與最後一則時間
- [x] 0.2 記錄基線（部署後不得下降）：`sessions` / `messages` 計數
  - **現行基線（2026-10-22 實測）**：`sessions = 127`、`messages = 17,671`、`state.db = 175.1MB`
- [x] 0.3 記錄 ledger 現況（起升前乾淨度）：`session_admissions = 0`、`worker_executions = 0`、`worker_receipts = 0`、`runtime_epoch = 1`
- [x] 0.4 記錄 FTS 現況：`messages_fts` = 舊 layout、`fts_storage_version` 不存在、`fts_optimize_available = 1`
- [x] 0.5 **備份 DB（.db + .db-wal + .db-shm，缺一則不完整）**
  ```bash
  POD=$(kubectl get pod -n hermes -o jsonpath='{.items[0].metadata.name}')
  mkdir -p ~/backups/hermes-20261022
  kubectl cp -n hermes $POD:/opt/data/state.db      ~/backups/hermes-20261022/state.db
  kubectl cp -n hermes $POD:/opt/data/state.db-wal  ~/backups/hermes-20261022/state.db-wal
  kubectl cp -n hermes $POD:/opt/data/state.db-shm  ~/backups/hermes-20261022/state.db-shm
  ```
- [x] 0.6 驗證備份：`sqlite3 ~/backups/hermes-20261022/state.db "SELECT COUNT(*) FROM messages"` → **17671**
- [x] 0.7 盤點既有備份並回報使用者（`ls -d ~/backups/hermes-*`；目前**無** hermes 備份）
- [x] 0.8 確認 `sessions.auto_prune: false` 仍在 config.yaml:507、`_config_version: 51`

### Phase A — 建分支 + Purge + 攜帶自訂

- [x] A0. **Go-Sign 確認** → §0.4 決策 A/B/C/D
- [x] A1. `git fetch origin refs/tags/v0.22.4:refs/tags/upstream-v0.22.4 --no-tags`（✅ 已完成，commit `4d04303818`）
- [x] A2. `git checkout -b my-config-v0.22.4 upstream-v0.22.4`
- [x] A3. Purge 官方 workflows，只留我們的 `ghcr-publish.yml`
  ```bash
  find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete
  git checkout my-config-v0.22.2 -- .github/workflows/ghcr-publish.yml
  ```
  ⚠️ 注意：v0.22.4 的 purge 目標檔名是 **`ghcr-publish.yml`**（Hermes 專屬），不是 `docker-release.yml`
- [x] A4. cherry-pick commit #2 #3 #4 #5 #6（**預期全部零衝突**；Dockerfile blob 相同）
- [x] A5. 複驗 `git diff upstream-v0.22.4 HEAD -- Dockerfile | grep -c '^@@'` = **8**
- [x] A6. 複驗 Dockerfile 仍含上游 `--cache /opt/hermes/uv-cache` 與 `--record-selection`
- [x] A7. **tracked-but-ignored 遺失偵測**（承 v0.22.1 教訓）
  ```bash
  comm -23 <(git ls-tree -r my-config-v0.22.2 --name-only | sort -u) \
           <(git ls-tree -r my-config-v0.22.4 --name-only | sort -u) \
    | git check-ignore --stdin --no-index 2>/dev/null
  ```
  期望：**空輸出**
- [x] A8. 提交歷史文檔（v0.22.2 worksheet / upgrade log / post-mortem）

### Phase B — 本地輕量驗證（不做重測 / 不本機 build）

- [x] B1. `git status` 乾淨
- [x] B2. Dockerfile 8 個自訂標記全數存在：`openssh-server` `rsync` `locales` `en_US.UTF-8` `zh_TW.UTF-8` `ssh-keygen -A` `-s /bin/bash` `agent-browser` `edge-tts` `firecrawl` `uv-cache`
- [x] B3. `.github/workflows/` 僅 `ghcr-publish.yml`
- [x] B4. blob 雜湊比對：`docker/entrypoint-ssh.sh`（自製）、`docker/stage2-hook.sh`、`docker-compose.yml`、`AGENTS.md`、`ghcr-publish.yml` → 應 5/5 SAME
- [x] B5. dispatch input 仍為 **`tag_name`**（不是 `tag`）
- [x] B6. 確認 ledger 模組已回來：`hermes_state_mutation_retirement.py`、`hermes_state_worker_lifecycle.py`、`hermes_state_runtime.py`、`agent/managed_worker.py`、`acp_adapter/` 皆存在
- [x] B7. 確認 `hermes_state_common.py` 的 `SCHEMA_VERSION` = **32**、`FTS_STORAGE_VERSION` = **3**
- [x] B8. 確認 config migration 階梯最高 = **51**（`hermes_cli/config_migrations.py`）
- [x] B9. `.env` 仍在 working tree 且未被刪（`ls -la .env`）
- [x] B10. `scripts/write_install_stamp.py` 存在且 CLI 參數不變（我們的 workflow 依賴它）
- [x] B11. npm 決策複驗：根 `package-lock.json` 的 `overrides` 仍為空 → 維持「不修」

### Phase C — 推送 + 建置

- [x] C1. `git push -u kuniakil my-config-v0.22.4`
- [x] C2. dispatch：**`gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v0.22.4 -f tag_name=v0.22.4 -f platforms=all`**
- [x] C3. 驗證 run：`event=workflow_dispatch`、`headBranch=my-config-v0.22.4`、`headSha` = **我方 commit**（絕非 `4d04303818`）
- [x] C4. `gh run watch` → prepare / linux-amd64 / linux-arm64 / merge 全 success
- [x] C5. image tags 存在：`v0.22.4`、`latest`
- [x] C6. **未 force-push 版本 tag**（發布模型由分支建置，tag 與 build 無關）
- [x] C7. 若出現 `HTTP 422 "Actions has been disabled for this repository"` → **停止並走 `/actions` 橫幅重新啟用**（不要重試、 不要清 cache、不要改 settings）

### Phase D — 部署 + 驗證

- [x] D1. `~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag: "v0.22.2"` → `"v0.22.4"`
- [x] D2. `kubectl kustomize .` render 正確；`kubectl apply -k` 後 `kubectl rollout status` **successfully rolled out**
- [x] D3. 冒煙測試：Python 3.14.7（含 `ruamel.yaml.clib` C 加速）、locale 3 種、sshd+rsync+tini、ffmpeg+agent-browser、edge_tts+dingtalk_stream+lark_oapi+firecrawl、Telegram connected、**0 ERROR**
- [x] D4. **版本確認**：`hermes --version` 應顯示 `v0.22.4` 且 `upstream <我方 commit sha>`
- [x] D5. **🔴 schema 檢查**：`state.db` `schema_version` 實測 = **32**；新增 `session_admissions` / `worker_executions` / `worker_receipts` / `runtime_epoch` 表與 `sessions.transcript_revision` 欄位存在
- [x] D6. **🔴 資料完整性**：`sessions` / `messages` 計數**不得下降**（基線 127 / 17,671）
- [x] D7. **🔴 開機驗證（本次重點）**：刪 pod 強制重啟，確認 gateway 在新 PID 下正常啟動、`RESTARTS` 歸零後不迴圈
  > 理由：v0.22.4 的 `gateway/status.py` 重寫 + 新增 `status_lock_dir.py` / `status_scoped_locks.py`；且 v0.22.3/4 有多筆 gateway ownership / startup stamp / restart-loop 修補。我們是 supervised（K3s pod）部署，直接命中這條路徑。
- [x] D8. **🔴 session 刪除測試**：抽 1 個帶 ledger 歷史的 session 實測 `hermes sessions delete` → v0.22.4 應**能刪**（刪前先清 ledger）
  > 驗證方式：刪除後 `SELECT COUNT(*) FROM session_admissions WHERE target_session_id=<sid>` 應為 0，且 `sessions` 表少 1
- [x] D9. **FTS 檢查**：`state_meta.fts_storage_version` 應**仍不存在**（我們維持 opt-in），`fts_optimize_available` = 1；確認 **沒有** 在 open 時自動重建（開機後 `messages_fts` 的 DDL 仍是 `fts5(content)`）
- [x] D10. **auto-prune 檢查**：確認 `sessions.auto_prune` 仍為 `false`、config stamp 仍 51、**沒有**任何 migration 紀錄被寫入
- [x] D11. 部署 60s 後 **0 restart**、log 無 ERROR/Traceback
- [ ] D12. 真實訊息往返（Telegram 收 → 模型 → 工具 → 送出）→ **待使用者送一則訊息**

### Phase E — 收尾

- [x] E1. 產出 `UPGRADE_LOG_v0.22.2_to_v0.22.4.md`（務必記錄：**ledger 機制回歸、回滾變單向**）
- [x] E2. 在 post-mortem 加入「v0.22.3/4 是 620 PR 收斂版、官方 curated notes 延到 v0.23.0」與「FTS layout drift 是既有狀態」
- [x] E3. 本工作表同步實際執行結果（image digest / run id / 實測數字）
- [x] E4. `~/kubernetes` kustomization 變更 commit + push
- [x] E5. 備份處置：~~等明確同意才刪~~ → ✅ **已於 2026-10-24 14:21 刪除**（使用者明確指示；由 `~/backups/hermes-20261024/` 取代）

---

## 5. 風險總結

| 風險 | 等級 | 緩解 |
|---|---|---|
| **620 PR 的巨型收斂，官方無 curated notes** | 🔴 高 | §1–§3 以 diff 完成盤點；Phase D 全面冒煙 + 資料完整性檢查 |
| **ledger 機制回歸 → 回滾變單向** | 🔴 高 | Phase 0.5–0.6 MANDATORY 備份；升級後若要回退，必須用備份 DB 而非直接降 image |
| **gateway runtime 大改（256 檔）影響 supervised 部署** | 🔴 高 | D7 強制重啟驗證 + D11 0 restart 檢查 |
| FTS layout drift 被標記 | 🟡 中 | 確認不自動重建（D9）；維持 opt-in，另案處理 |
| 新增 `ruamel.yaml.clib` C 依賴（cp314 wheel） | 🟡 中 | 已確認 x86_64 + aarch64 wheel 皆存在；D3 冒煙測試涵蓋 |
| `pm/lock.json` llamacpp 版本 bump | 🟢 無 | 我們不用本機模型 runtime |
| Dockerfile / docker/ 補丁衝突 | 🟢 **無** | 上游 blob 位元組相同，8 hunk 可原樣套用 |
| ~55 個 workflow 衝突 | 🟢 無 | Purge 規則直接刪除 |
| config migration | 🟢 **無** | 階梯最高 51 = 我們 stamp → 不執行任何 migration |
| Python 版本 / requires-python | 🟢 無 | `>=3.11,<3.15` 不變，容器 3.14.7 相容 |
| npm 漏洞 | 🟢 無（既有決策） | 3 個觸發 issue 今日仍 OPEN；實際 runtime 暴露面 = 0；上游 photon 已補 undici override |

---

## 6. npm 漏洞決策複驗（承 v0.22.0 / v0.22.2 §6）

| 檢查 | 結果（2026-10-22） |
|---|---|
| ① 根 `package-lock.json` `overrides` v0.22.2 → v0.22.4 | 皆為空 → **「不修」決策前提成立** |
| ② 觸發條件 issue 狀態 | **#133435 OPEN、#132924 OPEN、#79021 OPEN** → 條件**未成立** → 維持「不修」 |
| ③ 上游是否自行修掉部分 advisory | 🟢 有：`photon/sidecar` 新增 `overrides: undici 7.30.0`（GHSA 相關）；根目錄未動 |
| ④ 我們的實際 runtime 暴露面 | photon sidecar **未啟用**、Electron desktop 不部署 → **暴露面 = 0**（沿用 v0.22.0 實測結論） |
| ⑤ lockfile 整體 diff | 根 +60/−60、website +153/−153（例行 bump） |

---

## 7. 專案特定備註（Hermes）

- **Fork remote**：`kuniakil`；**Upstream remote**：`origin`（⚠️ 與 OpenClaw 相反，先跑 `git remote -v` 確認）
- **Workflow**：`ghcr-publish.yml`（上游**沒有**這個檔，純自訂）
- **dispatch input**：**`tag_name`**（**不是** `tag`；傳錯會被靜默忽略，只會產出 `latest`）
- **k8s overlay**：`~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag` → `v0.22.4`
- **資料路徑**：pod `/opt/data` = hostPath `/data/services/hermes/data`（n100，**SSH 使用者無權限讀取** → 備份走 `kubectl cp`）
- **Host 保護**：本機**不**跑 pytest / docker build / 全面 typecheck；僅 `git diff` / `git status` + 單檔語法檢查；編譯與完整測試交由 GitHub Actions

---

## 8. Go-Sign

- [x] §0.4 決策 **A**：目標版本 = **v0.22.4**（不等 v0.23.0）
- [x] §0.4 決策 **C**：npm 漏洞 = **維持不修**
- [x] §0.4 決策 **D**：FTS layout 漂移 = **本次不處理**
- [x] 使用者回覆「Go」→ Phase 0 → A → B → C → D → E 依序執行

---

## 9. 附錄：2026-10-22 n100 實地勘查（唯讀）

### 9.1 部署現況

```
hermes-agent-c84ddfc-lvjm8   1/1 Running   0 restarts   3d22h   node=n100
image : ghcr.io/kuniakil/hermes-agent:v0.22.2
hermes --version → Hermes Agent vv0.22.2 (2026.9.24) · upstream 26575c8a
```

### 9.2 DB 勘查（`/opt/data/state.db`，175.1MB，唯讀 `mode=ro`）

| 項目 | 值 |
|---|---|
| `sessions` | **127** |
| `messages` | **17,671** |
| `session_admissions` | **0**（v0.22.2 清場後乾淨） |
| `worker_executions` / `worker_receipts` | **0 / 0** |
| `runtime_epoch` | 1 |
| `state_meta` 鍵 | `ghost_session_prune_v1`、`orphaned_compression_finalize_v1`、`fts_optimize_available=1`、`fts_tool_full_content_high_water=16551`、`db_file_generation`、`message_uid_backfill=1` + 3 個 `gateway.admission.result.v1.*` |
| `fts_storage_version` | **不存在**（未 settle，維持 opt-in） |
| `messages_fts` DDL | `fts5(content)` ← 舊 layout |
| `messages_fts_trigram` DDL | `fts5(content, tokenize='trigram')` ← 舊 layout |
| `sessions` 欄位 | 已含 `handoff_state` / `auto_archived` / `runtime_revision` / `runtime_generation`（v0.22.1 時代殘留，v0.22.4 會再加 `transcript_revision`） |
| `messages` 欄位 | 已含 `active` / `display_order` / `message_uid` / `tool_call_uids` ✅ |

### 9.3 config 勘查

```
_config_version: 51                      （= v0.22.4 migration 階梯最高階梯 → 不會有任何 migration 執行）
sessions.auto_prune: false               （config.yaml:507 → 維持關閉，不會被開）
sessions.retention_days: 90
checkpoints.auto_prune: true             （config.yaml:72，與 sessions 無關）
```

### 9.4 工具鏈現況（Phase D 冒煙測試對照組）

| 項目 | 現況 |
|---|---|
| Python | 3.14.7（v0.22.4 將額外載入 `ruamel.yaml.clib` cp314 wheel） |
| SSH | sshd + 3 種 host key（hostPath 掛載） |
| 本機 runtime | **未使用**（`pm/lock.json` 的 llamacpp bump 與我們無關） |

---

## 10. 執行結果（2026-10-22 實際跑完）

### 10.1 時間線

| 時間 | 動作 | 結果 |
|---|---|---|
| 13:42 | 官方 Release Notes + diff + 拓撲 + n100 唯讀勘查完成，產出工作表 | ✅ |
| 14:03 | 使用者回覆「Go」（A/C/D 依建議） | ✅ |
| 14:05 | 備份：pod 內 `sqlite3.Connection.backup()` 一致快照 → `kubectl exec -- cat` 落地 | ✅ 175,075,328 bytes，integrity ok，messages 17,671 |
| 14:20 | `git checkout -b my-config-v0.22.4 upstream-v0.22.4` | ✅ `4d04303818` |
| 14:22 | Purge 官方 workflows（57 → 1）+ 還原 `ghcr-publish.yml` | ✅ |
| 14:24 | cherry-pick 6 個自訂 commit + 5 個歷史文檔 commit | ✅ **全部零衝突**、線性歷史 |
| 14:26 | Phase B 輕量驗證（B1–B11） | ✅ 全數通過，Dockerfile 8 hunk 保持 |
| 14:26 | `git push -u kuniakil my-config-v0.22.4` + dispatch | ✅ run **39733973873**（headSha = 我方 commit） |
| 14:40 | Build 完成（prepare / amd64 / arm64 / merge 全 success） | ✅ |
| 14:45 | `newTag: v0.22.4` + `kubectl apply -k` | ✅ successfully rolled out |
| 14:46–14:56 | 冒煙測試 + DB 驗證 + 強制刪 pod 重啟測試 | ✅ |
| 14:58 | ledger 寫入/刪除路徑實測（建立 → 刪除 → ledger 歸零） | ✅ |
| 15:05 | `hermes doctor` 健康檢查 | ✅ 3 issues（皆為既有） |

### 10.2 關鍵實測數據

| 檢查 | 升級前 | 升級後 | 判定 |
|---|---|---|---|
| `sessions` | 127 | **127** | ✅ 零損失 |
| `messages` | 17,671 | **17,671** | ✅ 零損失 |
| `schema_version` | 31 | **32** | ✅ additive |
| `PRAGMA integrity_check` | ok | **ok** | ✅ |
| `session_admissions` | 0 | 0（測試後已清） | ✅ |
| `worker_executions` / `worker_receipts` | 0 / 0 | 0 / 0 | ✅ |
| `sessions.transcript_revision` | — | **present** | ✅ |
| `session_turn_leases` / `session_model_usage` / `async_delegations` | — | **present** | ✅ |
| `sessions_runtime_ledger_delete_guard` trigger | — | **present** | ✅（設計如此） |
| `messages_fts` DDL | `fts5(content)` | `fts5(content)` | ✅ 未自動重建 |
| `fts_storage_version` | 不存在 | **仍不存在** | ✅ 維持 opt-in |
| `_config_version` | 51 | **51** | ✅ 無 migration 執行 |
| `sessions.auto_prune` | false | **false** | ✅ 未被開啟 |
| Pod restarts | 0 | **0**（刪 pod 重啟後仍 0） | ✅ |
| 升級後 ERROR level 筆數 | — | **0** | ✅ |
| 升級後 Traceback 筆數 | — | **0** | ✅ |

### 10.3 自訂層實測

`hermes --version` → `Hermes Agent vv0.22.4 (2026.9.24) · upstream 621915ab`（我方 commit，非官方 `4d04303818`）

Dockerfile 8 個自訂標記全數存在 ✅ · locale `C.utf8/en_US.utf8/zh_TW.utf8` ✅ · sshd+rsync+tini ✅ ·
`agent-browser` ✅ · extras（edge-tts / firecrawl / dingtalk_stream / lark_oapi / exa_py）✅ ·
`HOME=/opt/data` + npm cache 權限 ✅ · `entrypoint-ssh.sh` blob 未變 ✅ ·
`ruamel.yaml.clib` C 加速可用（`from _ruamel_yaml import CParser` OK）✅

### 10.4 🔴 Ledger 路徑實測（本次升級最關鍵的驗證）

```
$ hermes chat --oneshot -q "回覆 OK 即可" --pass-session-id
→ Session: local-6c0ff960080d9e27f54a88c21ed87ed004f39a24b28d60ea8867898bb5ed5bd2
→ session_admissions: 1 (status=terminal, outcome=completed)   ← ledger 重新寫入 ✅

$ hermes sessions delete --yes local-6c0ff960080d9e27f54a88c21ed87ed004f39a24b28d60ea8867898bb5ed5bd2
→ Deleted session 'local-6c0ff960080d9e27f54a88c21ed87ed004f39a24b28d60ea8867898bb5ed5bd2'.

sessions: 128 → 127   messages: 17,673 → 17,671   session_admissions: 1 → 0   integrity: ok
```

→ **v0.22.2 的「session 刪不掉」問題已確認消失**：v0.22.4 先 retire ledger 再刪 session。
→ 同時確認 **回滾已變成單向**（見 UPGRADE_LOG §2.2）。

### 10.5 剩餘待辦

- [ ] **D12 真實 Telegram 訊息往返**：本地 `hermes chat --oneshot` 已證明 agent turn 路徑正常（模型回覆「OK」，15s），但 Telegram 端需使用者送一則訊息做最終確認。
- [x] **備份處置**：`~/backups/hermes-20261022/`（175MB）— ✅ **已於 2026-10-24 14:21 刪除**（使用者明確指示）。
      取代者：`~/backups/hermes-20261024/`（schema 32，v0.22.5 升級前快照）。

---

## 11. 備份盤點（2026-10-22 全機 + pod + n100 主機掃描）

> 依 `docker-image-rebuild` skill 硬性規則 9「開始時就要先盤點並告知既有備份」。

| 路徑 | 來源 | schema | sessions | messages | `session_admissions` | integrity |
|---|---|---|---|---|---|---|
| `~/backups/hermes-20261022/state.db` | **本次升級前快照** | **31** | 127 | **17,671** | **0** | ok | 🔴 **已於 2026-10-24 14:21 刪除** |
| `~/kubernetes/hermes/backups/20261015/state.db` | **上次升級殘留**（v0.22.1→v0.22.2，2026-10-15 19:47） | 31 | 127 | 17,657 | **3** | ok |
| `~/hermes/data/state.db` | 本機開發用 live DB（非備份） | — | — | — | — | — |
| `/opt/data/backups/config/`（pod） | config 備份 184K（非 DB） | — | — | — | — | — |
| `/opt/data/.curator_backups/`（pod） | skills curator 備份（非 DB） | — | — | — | — | — |
| n100 主機 | **無任何 DB 備份**（`/data/services/hermes/data` 對 SSH 使用者無權限，歷次升級皆走 `kubectl exec -- cat`） | — | — | — | — | — |

**結論**：

1. ✅ **上次升級（20261015）的備份還在** → `~/kubernetes/hermes/backups/20261015/`，且被 `~/kubernetes/.gitignore` 的 `backups/` 規則排除，未進 git。
2. 🔴 **兩份 DB 備份不可互換**：20261015 那份帶著 **3 列 v0.22.1 殘留 ledger**（當時造成「session 刪不掉」的那 3 列，清場前的狀態）；本次 20261022 那份 **ledger 為空** → **回滾 v0.22.2 image 必須用 20261022 那份**。
   - 🔴 **20261022 那份已於 2026-10-24 14:21 刪除**（使用者明確指示，由 `~/backups/hermes-20261024/` 取代）。
3. ℹ️ 本次備份是**升級前**快照（`schema_version = 31`）—— 這正是回滾所需的正確形態，升級後 DB 已升到 32。
