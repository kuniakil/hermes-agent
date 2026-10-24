# Hermes Agent 升級紀錄：v0.22.4 → v0.22.5

- **升級日期**：2026-10-24
- **目標版本**：`v0.22.5`（官方 commit `bf0203a794a07aac3ff764972ab9087baa4e4f4e`，2026-10-22 發佈）
- **升級前版本**：`v0.22.4`（基於官方 `v0.22.4` = `4d04303818`）
- **新分支**：`my-config-v0.22.5`
- **Image source SHA**：`505335bfebd6bdf76ee564ca0a8eb4945109edf0`（= `hermes --version` 顯示的 `upstream 505335bf`）
- **GHCR index digest**：`sha256:8fb00e4665e888ed3ce199269355cc0d596e1399f52f148c21403b06b0fb1660`
  - amd64：`sha256:9a86a3db598446147a87300a04ae0e854bb866fce641610ccc9d600112f882d8`
  - arm64：`sha256:5106ebf26039b25b2a38f7d404e4847354cb13d88ef85c60afe1dce27bc3eddf`
- **GH Actions Run**：`40067788285`（prepare / build-and-push amd64 / build-and-push arm64 / merge 全 success）
- **部署環境**：K3s n100，pod `hermes-agent-665b4bfd7b-dv54g`
- **schema_version**：32 → **32**（**未變**）
- **備份**：`~/backups/hermes-20261024/state.db`（176,078,848 bytes，integrity ok，messages 17,702）

---

## 1. 一句話總結

> 這是 Hermes 歷次升級中**衝突面最小、schema 風險最低**的一次：81 個 PR 的正常 patch 窗口、
> `git merge-tree` 實測**唯一衝突是 8 個 workflow 檔**（Purge 規則直接消化）、
> `SCHEMA_VERSION` / `FTS_STORAGE_VERSION` / config migration 階梯**三項全部未變** →
> **沒有 DB 遷移、回滾路徑完整**（與 v0.22.4 那次「ledger 回歸導致回滾單向」完全不同）。

---

## 2. 官方 Release Notes 稽核

### 2.1 官方量測

| 指標 | 值 |
|---|---|
| non-merge commits | 231 |
| changed files | 804 |
| 行數 | +35,212 / −17,885 |
| merged PRs | **81** |
| closed issues | 30 |

> 官方 Release Notes 原文：*"Patch release. This tag rolls up the ~81 PRs merged since v0.22.4… **Full curated release notes for this window ship with v0.23.0.**"*
>
> → **官方再次把 curated notes 延到 v0.23.0**（與 v0.22.3/4 同一模式）。但本窗口僅 81 PR，
> 盤點成本與風險都低一個量級（對照 v0.22.4 升級窗口是 ~620 PR / 4,242 檔）。

### 2.2 官方「on purpose 不逐條列出」的內容（稽核線索）

Nous sign-in 重做（純 device login / guest 交棒 / connectors 提供 sign-in）、
`hermes update` 扣住拒絕的 stable release、Windows `hermes update` launcher 修復、
usage-window plan 支援（plan gauges / limit cards / model-switch 復原）、
**pluggable delegation backends**、plugin slash command 選項、
`hermes import-agent` / OpenClaw migration / `hermes mcp serve` / Singularity backend **移出 core 進 plugin**、
Desktop drag-to-pin + one-click plugin install、**Electron 44**、Pillow 13、dependency security bumps、
working folder 消失提示、`hermes update` 救回 damaged `.git` 的 paused gateway、
Claude DirectSDK 長回答不再被 stall timer 截斷、Desktop group chat bot 狀態、
實驗性 webhook-mode MCP events client。

### 2.3 對我們的影響判定

| 項目 | 影響 | 判定 |
|---|---|---|
| Nous sign-in 重做 | `auth.json providers = {}`、容器 env 無 `NOUS_*` | 🟢 不受影響 |
| `hermes update` 行為 | 我們是 image-based 部署（kustomize 釘 `newTag`），容器不跑 `hermes update` | 🟢 不受影響 |
| usage-window plan | 我們不用 Nous 帳號 | 🟢 不受影響 |
| **pluggable delegation backends** | 新增 bundled `plugins/delegation/default`（`kind: backend`）。`delegation/` **不在** bundled 排除清單 → 自動被發現 | 🟢 已實測（D9） |
| `mcp serve` / Singularity / agent-import / OpenClaw migration 移出 core | 我們不用這些（`terminal.backend: local`） | 🟢 不受影響 |
| Electron 44 / Desktop | 不部署 Electron desktop | 🟢 不受影響 |
| Pillow 13 / aiohttp 3.14.5 / certifi 2026.10.19 | 安全 bump | 🟢 正面 |
| **`hermes update` 修 damaged `.git`** | 我們不用 `hermes update` | 🟢 不受影響 |

---

## 3. Schema / 不可逆性判定

| 項目 | v0.22.4 | v0.22.5 | 判定 |
|---|---|---|---|
| `SCHEMA_VERSION` | 32 | **32** | ✅ 未變 |
| `FTS_STORAGE_VERSION` | 3 | **3** | ✅ 未變 |
| config migration 階梯 | 51 | **51** | ✅ 未變（`config_migrations.py` 位元組完全相同） |
| `hermes_state_*.py` | — | 僅 `hermes_state_local.py` +4/−1 | ✅ 極小 |

> **判定：非不可逆。無 DB 遷移、無 schema 宣告變更。**
> **回滾路徑完整** —— 直接退回 v0.22.4 image 即可，**不依賴 DB 備份**。
>
> 對照 v0.22.4 升級：那次 `SCHEMA_VERSION` 31→32 且 gateway runtime ledger 重新啟用，
> 使得「降級回 v0.22.2」會被 `sessions_runtime_ledger_delete_guard` 單向鎖死 → 那次回滾才需要靠備份。
> **本次沒有這個問題。**

唯一的 schema 相關改動：`hermes_state_local.py` 的 `client_request()` 多一行
`request.pop('desktop_local', None)` —— 只影響 desktop local 請求欄位正規化，我們不部署 desktop。

---

## 4. 衝突面稽核（`git merge-tree` 實測）

```
git merge-tree --write-tree --merge-base=upstream-v0.22.4 \
                upstream-v0.22.5 my-config-v0.22.4
```

| 指標 | 值 |
|---|---|
| 我們自訂 commit 觸及 | 74 檔（含 57 個 workflow + 8 個歷史文檔） |
| 上游 v0.22.4→v0.22.5 變更 | 804 檔 |
| 重疊 | 10 檔 |
| **實際 CONFLICT** | **8 檔 — 全部是 `.github/workflows/*`（modify/delete）** |
| 自動合併無衝突 | `Dockerfile`、`.env.example`、`AGENTS.md`、`docker-compose.yml`、`docker/entrypoint-ssh.sh`、`docker/stage2-hook.sh`、5 個歷史文檔 |

> ✅ 唯一衝突由 Purge 規則直接消化（`find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete`），
> **零人工解決成本**。實測 cherry-pick 17 個自訂 commit **全部零衝突**。

---

## 5. 攜帶的自定義補丁（8 個 Dockerfile hunk，全數保留）

| # | 內容 | 部署後實測 |
|---|---|---|
| 1 | apt：`openssh-server` `rsync` `locales`；`/var/run/sshd` + `ssh-keygen -A`；`locale-gen`（`C.UTF-8` / `en_US.UTF-8` / `zh_TW.UTF-8`） | ✅ sshd / rsync / tini / 3 種 locale / host keys 全在 |
| 2 | `useradd ... -s /bin/bash hermes` | ✅ `hermes` shell = `/bin/bash` |
| 3 | pm ensure + symlink 加入 **`agent-browser`** | ✅ `/usr/local/bin/agent-browser` → `/opt/hermes/tools/agent-browser-0.26.0-linux-x64` |
| 4 | `build_env --extra edge-tts firecrawl dingtalk feishu exa` | ✅ 5 個 extra 全可 import |
| 5 | `/tmp/.npm-cache`（sticky bit 1777） | ✅ `1777 root:root` |
| 6 | `/root/.npm` `/root/.cache` chown 10000 | ✅ `755 hermes:hermes` |
| 7 | `ENV HOME=/opt/data` | ✅ `HOME=/opt/data` |
| 8 | `COPY docker/entrypoint-ssh.sh`（Zeabur 相容 shim） | ✅ `/opt/hermes/docker/entrypoint-ssh.sh` 在位（上游 `entrypoint-dispatch.sh` 零 diff → shim 仍有效） |

---

## 6. 關鍵實測數據

| 檢查 | 升級前 | 升級後 | 判定 |
|---|---|---|---|
| `hermes --version` | `vv0.22.4 … upstream 621915ab` | **`vv0.22.5 … upstream 505335bf`** | ✅ 我方 commit，非官方 `bf0203a79` |
| `sessions` | 127 | **127** | ✅ 零損失 |
| `messages` | 17,702 | **17,702** | ✅ 零損失 |
| `schema_version` | 32 | **32** | ✅ 未變（**不得變 33**） |
| `PRAGMA integrity_check` | ok | **ok** | ✅ |
| `session_admissions` | 2 | 2（測試 session 刪除後歸零） | ✅ |
| `worker_executions` / `worker_receipts` | 0 / 0 | 0 / 0 | ✅ |
| `runtime_epoch` | 1 | 1 | ✅ |
| `sessions.transcript_revision` | present | **present** | ✅ |
| `session_turn_leases` / `session_model_usage` / `async_delegations` | present | **present** | ✅ |
| `messages_fts` DDL | `fts5(content)` | **`fts5(content)`** | ✅ **未自動重建** |
| `fts_storage_version` | 不存在 | **仍不存在** | ✅ 維持 opt-in |
| `fts_optimize_available` | 1 | 1 | ✅ |
| `_config_version` | 51 | **51** | ✅ **無 migration 執行** |
| `sessions.auto_prune` | false | **false** | ✅ 未被開啟 |
| `terminal.backend` | local | **local** | ✅ |
| Pod restarts | 0 | **0**（刪 pod 強制重啟後仍 0） | ✅ |
| 升級後 ERROR level 筆數 | — | **0** | ✅ |
| 升級後 Traceback 筆數 | — | **0** | ✅ |
| left-core 自動安裝觸發 | — | **0 次** | ✅ 見 §7 |
| Gateway 平台 | telegram + api_server | **telegram ✓ + api_server ✓** | ✅ |

---

## 7. 🟡 R1 實測：left-core 自動安裝沒有觸發

v0.22.5 新增 `hermes_cli/left_core_migration.py`，並在
`gateway/run_bootstrap.py:809`（**runner 載入 platform config 之前**）呼叫
`recover_left_core_at_gateway_start()` —— 若 home「有在用」任何離開 core 的功能
（Home Assistant / Spotify / Langfuse / `mcp serve` / Singularity / agent-importers），
且 `security.allow_lazy_installs: true`，gateway 開機會**自動從 catalog 安裝 plugin**。

**我們的 8 項觸發條件唯讀勘查（升級前）**：

| 觸發條件 | 我們的實測值 | 判定 |
|---|---|---|
| `.env` 有 `HASS_TOKEN` | ❌ 無 | 🟢 |
| `auth.json` `providers.spotify` 有登入 | ❌ `providers = {}` | 🟢 |
| `terminal.backend` = `singularity` | ❌ `local` | 🟢 |
| top-level `toolsets:` 含 `homeassistant`/`spotify` | ❌ `toolsets: [hermes-cli]` | 🟢 |
| `platform_toolsets.<platform>` 含 `homeassistant`/`spotify` | ❌ `platform_toolsets.cli` 只有 browser/clarify/code_execution/computer_use/connections/cronjob/delegation/file/image_gen/memory/session_search/skills/terminal/todo/tts/video_gen/vision/web | 🟢 |
| `plugins.enabled` 含 langfuse 等 | ❌ config 無 `plugins:` 區塊 | 🟢 |
| `mcp-serve` | ❌ `in_use` 恆為 `False`（設計如此） | 🟢 |
| Nous sign-in / free-tier guest | ❌ `auth.json` 零 `nous` 鍵；容器 env 無 `NOUS_*` | 🟢 |

**部署後實測**：`grep -icE 'left.core|left_core|Installing plugin' gateway.log` = **0**
（升級後 + 強制重啟後兩次開機皆為 0）。

> ✅ 結論：left-core 機制對我們**完全不生效**，gateway 開機路徑沒有新增網路安裝延遲。

---

## 8. delegation 機制遷移實測（v0.22.5 新增 pluggable backends）

| 檢查 | 結果 |
|---|---|
| `hermes plugins list` | ✅ `default`（description = "Default delegation strategy…"）= **enabled** / source **bundled** |
| `agent.delegation_registry` | ✅ 可載入，暴露 `DEFAULT_BACKEND` / `ProviderRegistry` / `get_active_provider` / `configured_backend` |
| `agent.delegation_backends` | ✅ 可載入，暴露 `DelegationBackends` / `get_session_backend` / `backend_status` |
| **真實 `delegate_task`** | ✅ 成功：子代理用 terminal 算出 `137*23 = 3151` 並回報，19s / 7 messages |

> ℹ️ 首次委派時出現一次 `Task 0 output_schema invalid` → 自動重試後成功。
> 這是 child-run 的 schema 收斂行為，非失敗（第二次 `Delegate 1x` 直接完成）。

---

## 9. session 刪除路徑實測（D10）

```
刪除前：sessions=129  messages=17713  admissions(sid)=1
$ hermes sessions delete --yes local-d79f924493ee63d83c181393f67d7d48983400455ce5606ce89b886bf735a4fd
→ Deleted session 'local-d79f924493ee63d83c181393f67d7d48983400455ce5606ce89b886bf735a4fd'.
刪除後：sessions=127  messages=17702  admissions(sid)=0  integrity=ok
```

→ **精確回到升級前基線**（127 / 17,702），ledger 對應列歸零，integrity ok。
→ v0.22.4 建立的 ledger retirement 路徑在 v0.22.5 **維持有效**（未被 regress）。

---

## 10. 環境變更實測（R2 / R3）

| 項目 | v0.22.4 | v0.22.5 | 實測 |
|---|---|---|---|
| Base image | `debian:13.4@sha256:e2d08da6…` | **`debian:trixie-20261020@sha256:4c252754…`** | ✅ `Debian GNU/Linux 13 (trixie)`、`glibc 2.41-12+deb13u4` |
| Node.js | `v26.7.0` | **`v26.12.1`** | ✅ `node v26.12.1` / `npm 12.0.2` |
| Python | 3.14.x | 不變 | ✅ `3.14.9` |
| sqlite3 | — | — | ✅ `3.53.1` |
| `ruamel.yaml.clib` C 加速 | 有 | 有 | ✅ `from _ruamel_yaml import CParser` 成功 |

---

## 11. npm 漏洞決策複查（決策 C）

| 檢查 | 結果（2026-10-24） |
|---|---|
| 根 `package-lock.json` `overrides` v0.22.4 → v0.22.5 | 皆為 **空 / None** → 前提成立 |
| 觸發條件 issue 狀態 | **#133435 OPEN、#132924 OPEN、#79021 OPEN** → 條件未成立 → 維持「不修」 |
| 關鍵套件是否惡化 | undici 7.30.0 → 7.30.0、axios 1.20.0 → 1.20.0、js-yaml 4.3.2 → 4.3.2 → **零變化** |
| 上游是否自行修掉部分 | 🟢 `package.json` overrides 移除 `electron@40.10.2` 條目（Electron 改由 `apps/desktop` 管理，v44.9.3） |
| 我們的實際 runtime 暴露面 | photon sidecar 未啟用、Electron desktop 不部署 → **暴露面 = 0** |
| `hermes doctor` 實測 | root 1 / web 1 / ui-tui 2 = **4 個 npm 議題**（與升級前同一組，非本次新增） |

---

## 12. `hermes doctor` 結果

4 個 issue，**全部是既有狀態**（與 v0.22.4 基線同一組）：

1. `hermes setup` 補缺少的 API key（a2a / browser-cdp / computer_use / discord / hermes-yuanbao / image_gen / x_search 缺 key 或系統依賴）
2. root npm 1 個漏洞
3. web workspace npm 1 個漏洞
4. ui-tui workspace npm 2 個漏洞

> 其餘檢查全綠：toolsets（skills / terminal / todo / tts / video / video_gen / vision / kanban / web search / web extract）、Skills Hub（22 個 hub skill）、Memory Provider（built-in）。

---

## 13. 執行時間線

| 時間 | 動作 | 結果 |
|---|---|---|
| 13:45 | 官方 Release Notes + diff + merge-tree 衝突稽核 + n100 唯讀勘查完成，產出工作表 | ✅ |
| 13:47 | 使用者回覆「Go」（A/B/C/D/E 依建議） | ✅ |
| 13:48 | 備份：pod 內 `sqlite3.Connection.backup()` 一致快照 → `kubectl exec -- cat` 落地 | ✅ 176,078,848 bytes，messages 17,702，integrity ok |
| 13:49 | `git checkout -b my-config-v0.22.5 upstream-v0.22.5` | ✅ `bf0203a794a` |
| 13:49 | Purge 官方 workflows（57 → 1）+ 還原 `ghcr-publish.yml` | ✅ |
| 13:49 | cherry-pick 17 個自訂 commit（含 v0.22.5 工作表） | ✅ **全部零衝突**、線性歷史（0 merge commit） |
| 13:50 | Phase B 輕量驗證（B1–B13） | ✅ 全數通過，Dockerfile 8 hunk 保持 |
| 13:49 | `git push -u kuniakil my-config-v0.22.5` + dispatch | ✅ run **40067788285**（headSha = `505335bfeb`） |
| 13:58 | Build 完成（prepare / amd64 / arm64 / merge 全 success） | ✅ digest `sha256:8fb00e46…` |
| 14:07 | `newTag: v0.22.5` + `kubectl apply -k` | ✅ successfully rolled out |
| 14:08–14:12 | 冒煙測試 + DB 驗證 + delegation 實測 + session 刪除實測 | ✅ |
| 14:10 | 刪 pod 強制重啟驗證 gateway 開機 | ✅ 0 restarts、0 ERROR、telegram ✓ + api_server ✓ |
| 14:15 | `hermes doctor` | ✅ 4 issues（皆既有） |

---

## 14. 備份盤點

| 路徑 | 來源 | schema | sessions | messages | integrity |
|---|---|---|---|---|---|
| `~/backups/hermes-20261024/state.db` | **本次升級前快照** | **32** | 127 | **17,702** | ok |
| `~/backups/hermes-20261022/state.db` | 上次升級前快照（v0.22.2→v0.22.4） | 31 | 127 | 17,671 | ok |
| `~/kubernetes/hermes/backups/` | — | — | — | — | **已空**（20261015 那份於 2026-10-22 刪除） |
| n100 主機 | — | — | — | — | **無任何 DB 備份**（`/data/services/hermes/data` 對 SSH 使用者無權限 → 一律走 `kubectl cp`） |

> 🔴 兩份備份**不可互換**：
> `20261022` 是 schema 31（v0.22.4 升級**前**）的快照 → 那是「退到 v0.22.2 時代」才需要的；
> `20261024` 是 schema 32（v0.22.5 升級**前**）的快照 → 是「退到 v0.22.4」需要的。
> 本次 schema 未變 → **直接退回 v0.22.4 image 即可，不依賴任何備份**；備份只是多一層保險。

---

## 15. Post-Mortem / 教訓

### 15.1 官方 curated notes 延後到 v0.23.0 已成常態

v0.22.3、v0.22.4、v0.22.5 **連續三個 window** 都把 curated notes 推到 v0.23.0。
→ 從現在起，**每個 Hermes 升級都必須自己做 diff 盤點**（本 skill Phase 1 §3/§4 就是這件事）。
好消息是窗口愈來愈小（~620 PR → 81 PR），盤點成本可控。

### 15.2 `git merge-tree --write-tree` 是最有效的衝突預判工具

在 Go-Sign 之前就能把「會不會衝突」從猜測變成事實：

```bash
git merge-tree --write-tree --merge-base=<old-upstream> <new-upstream> <our-branch>
```

輸出 `CONFLICT (modify/delete): …` 清單 → 直接對照 Purge 規則消化。
本次它告訴我們：**唯一衝突是 8 個 workflow 檔** → 零人工解決成本。
（v0.22.4 那次同樣的方法告訴我們重疊 54 檔、全是 workflows → 同一結論。）

### 15.3 「離開 core」機制（left-core）會自動在開機路徑裝 plugin —— 這是新的隱性風險面

v0.22.5 起，若一個 home 用了任何離開 core 的功能，**gateway 開機會自己去 catalog 裝 plugin**。
對我們目前無影響（8 項條件全綠），但**未來若我們啟用了 Spotify / Home Assistant / Langfuse / Singularity**，
就要重新評估：

- 開機會多一次網路往返（我們是 K3s 受管 pod，開機時間敏感）
- `security.allow_lazy_installs: true` 讓它**自動同意**依賴安裝
- pod 內若無外網或 catalog 不可達，開機會有失敗重試（官方有 1h→1週的退避，但第一次仍會拖慢開機）

> 📌 建議未來若要啟用這些功能：**先手動 `hermes plugins install <name>` 裝好並釘版**，
> 讓 left-core 的 `in_use` 偵測命中「已安裝」路徑，而不是讓它在開機時才裝。

### 15.4 `hermes doctor` 的 npm 議題數是上游 lockfile 的快照，不是我們的暴露面

本次實測 doctor 報 4 個 npm 議題（root 1 / web 1 / ui-tui 2）—— 這是 **上游 lockfile 的現況**，
與我們的 runtime 暴露面無關（我們不跑 ui-tui/web 的 node 服務、不部署 Electron、不啟用 photon sidecar）。
判斷依據仍是一次只查根 `package-lock.json` 的 `overrides` + 觸發 issue 狀態。

### 15.5 冒煙測試腳本要對照「實際部署路徑」寫

本次自訂層驗證唯一一次誤報：`agent-browser` 我寫成查 `/opt/hermes/bin/agent-browser`，
實際 symlink 在 **`/usr/local/bin/agent-browser`**（Dockerfile patch 指定的 symlink 目標）。
→ 冒煙腳本的檢查路徑應從 **Dockerfile 的 symlink 宣告**反推，不要猜目錄慣例。

---

## 16. 待辦

- [ ] **D14 真實 Telegram 訊息往返**：本地 `hermes chat --oneshot` 已證明 agent turn 正常（delegate_task 端到端 19s、模型回覆 3151），
      但 Telegram 端仍需使用者送一則訊息做最終確認（gateway log 顯示 `✓ telegram connected`、`getUpdates progressing`）。
- [ ] **備份處置**：`~/backups/hermes-20261024/`（176MB）+ `~/backups/hermes-20261022/`（175MB）— 驗證通過，等使用者明確同意才刪。
