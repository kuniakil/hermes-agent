# Hermes Agent 升級工作表：v0.22.4 → v0.22.5

- **目標版本**：`v0.22.5`（官方 commit `bf0203a794a07aac3ff764972ab9087baa4e4f4e`，2026-10-22 發佈 / 2026-10-23 上架 GitHub Release）
- **升級前版本**：`my-config-v0.22.4`（HEAD `ccfb86106d`，基於官方 `v0.22.4` = `4d04303818`）
- **新分支**：`my-config-v0.22.5`
- **Remote**：`origin` = 官方（NousResearch）、`kuniakil` = 個人 fork（⚠️ 與 OpenClaw 相反）
- **發布模型**：`my-config-v0.22.5` 分支為 source of truth，由 `ghcr-publish.yml`（dispatch input **`tag_name`**）建置 `ghcr.io/kuniakil/hermes-agent:v0.22.5`
- **目前上線版本**：`v0.22.4`（K3s n100，pod `hermes-agent-5656b5d479-6rnjx`，0 restarts，46h）
- **狀態**：📋 **計畫中，等待 Go-Sign**
- **日期**：2026-10-24

---

## 0. ⚠️ 最高優先結論：這是「低風險 patch 升級」，但有 3 個必須在部署後驗證的行為變更

### 0.1 官方 Release Notes 摘要（v0.22.5，2026-10-22）

> Patch release. This tag rolls up the **~81 PRs merged since v0.22.4** into a stable release for the GitHub release (CLI and installers), the Microsoft Store app, Docker and Hermes Cloud. **Full curated notes for this window ship with v0.23.0.**

官方量測（commit `bf0203a794a`）：

| 指標 | 值 |
|---|---|
| non-merge commits | **231** |
| changed files | **804** |
| 行數 | **+35,212 / −17,885** |
| merged PRs | **81** |
| closed issues | **30** |

> ℹ️ **官方再次把 curated notes 延到 v0.23.0**（與 v0.22.3/4 同一模式）。本窗口的人讀版变更說明同樣不存在 → 我們自己從 diff 盤點（見 §2）。
> 但這次窗口比 v0.22.3/4 小得多（81 PR vs ~620 PR），盤點成本與風險都低一個量級。

官方「on purpose 不逐條列出」的內容（我們照抄作稽核線索）：

- Nous sign-in 重做（每次 sign-in 都是純 device login；free-tier guest 交棒給你的帳號；結果顯示誰登入；connectors 提供 sign-in 而非開 guest）
- `hermes update` 會**扣住**它拒絕的 stable release，而不是照樣提供
- Windows `hermes update` 在 Python repin 後不再卡在舊 launcher
- usage-window plan 支援（plan gauges、limit cards、window-based plan 的 model-switch 復原）
- **pluggable delegation backends**（依 model map 或 profile 路由 subagent，可 per-session 切換）
- plugin slash command 可讓使用者挑選選項
- `hermes import-agent`、OpenClaw migration、`hermes mcp serve`、Singularity backend **移出 core 進 plugin**
- Desktop sidebar drag-to-pin、one-click plugin install + tier badge
- **Electron 44 升級**、Pillow 13、一批 dependency security bumps
- chat 的 working folder 不見時給清楚訊息
- `hermes update` 在 `.git` 損壞後能救回 paused gateway
- Claude DirectSDK 長回答不再被 stall timer 截斷
- Desktop group chat 顯示哪個 bot 在工作
- 實驗性的 webhook-mode MCP events client

### 0.2 ✅ 這次的 diff 幅度是「常規模板」，不是收斂版

| 比較基準 | 檔案數 | +/− | 意義 |
|---|---|---|---|
| `v0.22.3 → v0.22.4`（上次） | 82 | +1,475 / −3,022 | 純 patch |
| **`v0.22.4 → v0.22.5`（本次）** | **804** | **+35,212 / −17,885** | **81 PR 的正常 patch 窗口** |
| `v0.22.2 → v0.22.4`（上上次，巨型收斂） | 4,242 | +361,206 / −66,783 | ~620 PR 收斂 |

→ 對照組：**上次的 v0.22.4 升級是 4,242 檔的巨型收斂**；本次只有 804 檔，且其中 **~530 檔是 `apps/desktop/`（Electron）與 `website/`（文件）**，與我們的容器 runtime 完全無關。

核心 runtime 實際變動量（`gateway/ agent/ tools/ hermes_cli/ tui_gateway/`）：

```
212 files changed, 8448 insertions(+), 3462 deletions(-)
```

### 0.3 ✅ Schema 完全未變（**無不可逆性**）

| 項目 | v0.22.4 | v0.22.5 | 判定 |
|---|---|---|---|
| `hermes_state_common.py: SCHEMA_VERSION` | **32** | **32** | ✅ **未變** |
| `hermes_state_common.py: FTS_STORAGE_VERSION` | **3** | **3** | ✅ 未變 |
| config migration 階梯最高 | **51** | **51** | ✅ 未變（`config_migrations.py` 兩個版本**位元組完全相同**） |
| `hermes_state_*.py` 變更 | — | 僅 `hermes_state_local.py` +4/−1 | ✅ 極小 |
| Python `requires-python` | `>=3.11,<3.15` | `>=3.11,<3.15` | ✅ 未變 |

> 🟢 **這是本次最重要的結論：沒有 schema 變更 → 沒有 DB 遷移 → 回滾不需要靠 DB 備份救。**
> 與 v0.22.4 那次「ledger 回歸導致回滾變單向」的情況**完全不同**。

**唯一 schema 相關的改動**：`hermes_state_local.py` 的 `client_request()` 多一行 `request.pop('desktop_local', None)` — 只影響 desktop local 請求欄位的正規化，我們不部署 desktop → 🟢 無影響。

### 0.4 🟡 三個必須在部署後驗證的行為變更（本次唯一實質風險）

| # | 變更 | 對我們的影響 | 驗證方式 |
|---|---|---|---|
| **R1** | **`recover_left_core_at_gateway_start()` 在 gateway 開機路徑上新增**（`gateway/run_bootstrap.py:809`，**在 runner 載入 platform config 之前**） | 若 home「有在用」任何離開 core 的功能，gateway 開機會嘗試**自動從 catalog 安裝 plugin**（我們的 `security.allow_lazy_installs: true`）→ 可能拖慢/卡住開機 | **已唯讀勘查確認我們不會觸發**（見 §2.3）；D7/D8 開機驗證複核 |
| **R2** | **Node.js runtime `v26.7.0 → v26.12.1`**（`pm/lock.json`，容器內 Node） | 容器內 Node 小版本前進（ui-tui / web / agent-browser 前端 bundle 用） | D3 冒煙測試涵蓋 node 版本列印 |
| **R3** | **基礎映像 `debian:13.4` → `debian:trixie-20261020`**（同 digest family，Debian 13 trixie 的日期快照） | libc/openssl patch level 前進；我們的 apt 補丁層要在新 base 上重編 | D3 冒煙測試 + 8 個自訂 apt 補丁逐一驗證 |

### 0.5 決策點（Go-Sign 時請一併回覆）

| # | 決策 | 建議 | 理由 |
|---|---|---|---|
| **A** | 目標版本 | **v0.22.5** | 官方最新 stable；81 PR 的正常 patch 窗口 |
| **B** | 是否等到 **v0.23.0**（官方才會補齊 v0.22.0 起的 curated notes） | **不等** | 本窗口風險低（§0.2/§0.3 已完整盤點）；v0.23.0 是大版本，風險量級不同 |
| **C** | **npm 漏洞**是否修 | **維持「不修」** | 3 個觸發 issue 今日複查**仍全為 OPEN**；實際 runtime 暴露面 = 0（見 §6） |
| **D** | FTS layout 漂移是否順手 `optimize-storage` | **不做** | 屬 pre-existing 狀態，非本次升級造成；另開專案處理 |
| **E** | 是否保留 v0.22.4 的 DB 備份 | **保留**（不刪） | 本次 schema 未變、備份成本低；刪除決策沿用上次流程（使用者明確同意才刪） |

---

## 1. 官方 Release Notes 稽核

### 1.1 Breaking Changes / Deprecations

**v0.22.5 Release Notes 沒有 `Breaking Changes` 或 `Deprecations` 章節。** 但 diff 中有幾個「離開 core」的隱含變更，必須自己盤點：

| 隱含變更 | 內容 | 等級 |
|---|---|---|
| ⚠️ **Left-core 機制**（新） | `hermes_cli/left_core_migration.py` + `gateway/run_startup.py` 新增。離開 core 的功能（Home Assistant / Spotify / Langfuse / `mcp serve` / Singularity / agent-importers）在 home「有在用」時會自動安裝 catalog plugin | 🟡 **我們不觸發**（§2.3 已證） |
| ⚠️ `hermes_cli/claw.py`、`hermes_cli/agent_import.py`、`hermes_cli/agent_import_sync.py`、`hermes_cli/subcommands/claw.py`、`hermes_cli/subcommands/import_agent.py`、`mcp_serve.py`、`tools/environments/singularity.py` | **從 core 刪除**，改由 catalog plugin 提供（`hermes mcp serve` → `hermes mcp-serve`；`hermes import-agent` → `hermes agent-import`） | 🟢 我們不用這些指令 |
| ⚠️ `optional-skills/migration/openclaw-migration/` | **從 core 刪除** → 移到 plugin | 🟢 我們不用 OpenClaw migration |
| ⚠️ `tools/environments/singularity.py` 刪除 | Singularity backend 改由 plugin 提供 | 🟢 我們 `terminal.backend: local` |
| ✅ `plugins/delegation/default/`（**新增 bundled plugin**） | delegation backend 機制化；`delegation/` **不在** bundled 排除清單（排除的是 `memory` / `context_engine` / `model-providers` / `cron_providers` / `computer_use`）→ **自動被發現，預設行為不變** | 🟢 預設仍繼承 parent model |
| ✅ `plugin-catalog/advanced-delegation.yaml`、`meshy.yaml` 新增；`agent-importers.yaml`、`cua-spaces.yaml` 更新 | catalog 資料 | 🟢 不自動安裝 |

### 1.2 機器可讀真相（Dependency / Runtime 稽核）

| 項目 | v0.22.4 | v0.22.5 | 判定 |
|---|---|---|---|
| `pyproject.toml` `requires-python` | `>=3.11,<3.15` | `>=3.11,<3.15` | ✅ 不變 |
| `certifi` | `2026.5.20` | **`2026.10.19`** | 🟢 CA trust bump；新增 `exclude-newer-package = { certifi = false }` 豁免（官方明說：撤銷受信任 CA 的版本必須當天進 lock） |
| `Pillow` | `12.3.0` | **`13.0.0`** | 🟢 **安全 bump**（GHSA-8g5g-8vmr-9782 等 13.0.0 advisory set）；新增 `override-dependencies = ["Pillow==13.0.0"]` 壓過 browser-harness 的 `pillow==12.3.0` 硬 pin |
| `aiohttp` | `3.14.3` | **`3.14.5`** | 🟢 安全 bump（GHSA-9xw5-w5jj-pvcg 等 family） |
| `edge-tts` | `7.2.7` | **`7.3.1`** | 🟢 我們有裝這個 extra → 需冒煙驗證 |
| `mistralai` | `2.4.8` | **`2.10.1`** | 🟢 我們不用（lazy extra） |
| `opentelemetry-sdk` / `exporter` | `1.39.1` | **`1.45.1`** | 🟢 我們不用 OTLP |
| `kittentts` / `piper` / `stt-whisper` / `google-meet` | — | 新增 `sys_platform != 'android'` 條件 | 🟢 只影響 Android；我們用 `faster-whisper`（`stt-whisper` extra，`voice` extra） |
| `Dockerfile` blob | `e3d11031c8` | **`d23df9a55e`** | 🔴 **上游改了**（base image + COPY 行）→ 但我們的 8 個補丁 hunk **自動合併無衝突**（§3） |
| `docker/stage2-hook.sh` | — | **零 diff** | 🟢 我們的 SSH + npm cache 補丁原樣套用 |
| `docker/entrypoint-dispatch.sh` | 存在 | **存在，零 diff** | 🟢 `entrypoint-ssh.sh` 的 exec 目標仍有效 |
| `scripts/write_install_stamp.py` | 存在 | **存在，零 diff** | 🟢 我們的 workflow 依賴它 |
| `pm/lock.json` Node.js | `v26.7.0` | **`v26.12.1`** | 🟡 R2 |
| `uv.lock` 行數 | 7,311 | 7,331 | 🟢 隨上述變更 |
| 根 `package-lock.json` `overrides` | `{}`（None） | `{}`（None） | ✅ 「不修」決策前提成立 |
| `package.json` `overrides` | `electron@40.10.2: true` | **移除該條**（Electron 44 改由 `apps/desktop` 管理） | 🟢 不影響容器 runtime |
| 根 `package-lock.json` 關鍵套件 | undici 7.30.0 / axios 1.20.0 / js-yaml 4.3.2 | **完全相同** | 🟢 無惡化 |

### 1.3 Schema / 不可逆性判定

> **判定：非不可逆。SCHEMA_VERSION 32 → 32，FTS_STORAGE_VERSION 3 → 3，config migration 階梯 51 → 51（檔案位元組相同）。**

- 沒有 DB 遷移、沒有 schema 宣告變更、沒有新增 guard trigger。
- **回滾路徑完整**：直接退回 v0.22.4 image 即可，**不依賴 DB 備份**（與 v0.22.4 那次「回滾變單向」不同）。
- 但備份仍列為 **MANDATORY**（理由見 §4 Phase 0，成本 175MB / 數分鐘）。

---

## 2. Diff 稽核（`upstream-v0.22.4 → upstream-v0.22.5`）

### 2.1 關鍵路徑

| # | 路徑 | 上游變更 | 影響 |
|---|---|---|---|
| 1 | **`Dockerfile`** | **3 個 hunk**：base image `debian:13.4` → `debian:trixie-20261020`（sqlite_build + runtime_base 兩處）、`COPY scripts/build/node-deps.mjs` → `COPY scripts/build/node-deps.mjs scripts/build/electron-runtime.mjs scripts/build/` | 🟡 R3；我們的 8 hunk **自動合併無衝突** |
| 2 | `docker/stage2-hook.sh` | **零 diff** | 🟢 SSH + npm cache 補丁原樣套用 |
| 3 | `docker/entrypoint-dispatch.sh` | 存在、零 diff | 🟢 `entrypoint-ssh.sh` 依賴有效 |
| 4 | `AGENTS.md` | **零 diff** | 🟢 我們的 Mac host 保護區塊直接帶過去 |
| 5 | `.env.example` | 上游改 terminal backend 說明（singularity 移出 core） | 🟢 **與我們的 hunk 不同區**（我們在檔頭加 HERMES_IMAGE 區塊）→ 自動合併無衝突 |
| 6 | `docker-compose.yml` | 上游有，但我們覆寫 | 🟢 沿用我們的 |
| 7 | `.github/workflows/` | 57 檔（8 個上游有改） | 🟢 依 Purge 規則全刪，只留我們的 `ghcr-publish.yml` |
| 8 | `gateway/` | 28 檔 / +966 / −73。新增 `platforms/webhook_mcp_events.py`、`plugin_command_choice.py`、`session_onboarding.py` | 🟡 我們的 Telegram gateway 主路徑有動（`run_turn*`、`session_*`） |
| 9 | `agent/` | 30 檔 / +2,123 / −89。新增 `delegation_backends.py`、`delegation_provider.py`、`delegation_registry.py`、`plan_limits.py`、`plan_snapshot_sync.py`、`usage_gauges.py`、`onboarding_session.py`、`chat_completion_headers.py` | 🟡 delegation 改走 plugin backend 機制（預設行為不變） |
| 10 | `tools/` | 41 檔 / +1,357 / −479。刪 `environments/singularity.py`；新增 `delegate_tool_routes.py`、`delegate_tool_tuning.py`、`mcp_tool_events.py` | 🟢 singularity 不用；delegation routing 新增 |
| 11 | `plugins/platforms/telegram/adapter.py` | 修改（model picker 加 plan suffix） | 🟢 純 UI 文字，非 Nous 帳號不顯示 |
| 12 | `plugins/delegation/default/` | **新增** bundled plugin（`kind: backend`） | 🟢 預設繼承 parent model，行為不變 |
| 13 | `hermes_cli/` | 大量修改（auth 重做、`left_core_migration.py` 新增、`claw.py`/`agent_import.py`/`mcp_serve.py` 刪除） | 🟡 見 R1 |
| 14 | `apps/desktop/`、`ui-tui/`、`web/`、`website/` | 數百檔（Electron 44、i18n 20 語系新增） | 🟢 不影響容器 runtime |
| 15 | `hermes_state_local.py` | +4 / −1（`desktop_local` 欄位正規化） | 🟢 我們不部署 desktop |

### 2.2 衝突面計算（**已用 `git merge-tree` 實測**）

```
git merge-tree --write-tree --merge-base=upstream-v0.22.4 \
                upstream-v0.22.5 my-config-v0.22.4
```

| 指標 | 值 |
|---|---|
| 我們自訂 commit 觸及 | 74 檔（含 57 個 workflow + 8 個歷史文檔） |
| 上游 v0.22.4→v0.22.5 變更 | 804 檔 |
| **重疊** | **10 檔** |
| **實際衝突（CONFLICT）** | **8 檔 — 全部是 `.github/workflows/*`（modify/delete）** |
| **自動合併無衝突** | `Dockerfile`、`AGENTS.md`、`docker-compose.yml`、`docker/entrypoint-ssh.sh`、`docker/stage2-hook.sh`、`.env.example`、5 個歷史文檔 |
| **非重疊的自訂檔（零風險）** | `Dockerfile` 的 8 個 hunk、`docker/entrypoint-ssh.sh`、`docker-compose.yml`、`AGENTS.md` |

> ✅ **結論：唯一衝突是 8 個 workflow 檔，而 Purge 規則本來就是全刪 → 零人工解決成本。**
> 這是 Hermes 歷次升級中**衝突面最小的一次**（對照 v0.22.4 升級：重疊 54 檔）。
> 驗證方式（升級後複驗）：`git diff upstream-v0.22.5 HEAD -- Dockerfile | grep -c '^@@'` = **8**。

### 2.3 🟡 R1 深入勘查：left-core 自動安裝是否會影響我們？

`recover_left_core_at_gateway_start()` 在 `gateway/run_bootstrap.py:809` 被呼叫，**位置在 runner 載入 platform config 之前** → 是 gateway 開機的關鍵路徑。若觸發會嘗試自動安裝 catalog plugin。

**LEFT_CORE 表涵蓋的功能**（`hermes_cli/left_core_migration.py:239`）：`homeassistant`、`spotify`、`langfuse`、`mcp-serve`、`singularity`、`agent-importers`、`openclaw-migration`。

**我們的 home 唯讀勘查（2026-10-24 實測）**：

| 觸發條件 | 我們的實測值 | 判定 |
|---|---|---|
| `.env` 有 `HASS_TOKEN` | ❌ 無 | 🟢 不觸發 |
| `auth.json` `providers.spotify` 有登入 | ❌ `providers = {}` | 🟢 不觸發 |
| `terminal.backend` = `singularity` | ❌ `local`（config.yaml:28） | 🟢 不觸發 |
| top-level `toolsets:` 含 `homeassistant`/`spotify` | ❌ `toolsets: [hermes-cli]`（config.yaml:5-6） | 🟢 不觸發 |
| `platform_toolsets.<platform>` 含 `homeassistant`/`spotify` | ❌ `platform_toolsets.cli` 只有 browser/clarify/code_execution/computer_use/connections/cronjob/delegation/file/image_gen/memory/session_search/skills/terminal/todo/tts/video_gen/vision/web | 🟢 不觸發 |
| `plugins.enabled` 含 langfuse 等 | ❌ config 無 `plugins:` 區塊 | 🟢 不觸發 |
| `mcp-serve` | ❌ `in_use` 恆為 `False`（設計如此） | 🟢 不觸發 |
| Nous sign-in / free-tier guest | ❌ `auth.json` 零 `nous` 鍵；容器 env 無 `NOUS_*` | 🟢 不受影響 |
| `HERMES_DISABLE_LAZY_INSTALLS` | 空字串（lazy install **允許**） | ⚠️ 若真的觸發會去裝 plugin → 所以上面 8 項全綠是關鍵 |

> ✅ **結論：我們不會觸發任何 LEFT_CORE 列 → `recover_left_core_at_gateway_start()` 是 no-op。**
> ⚠️ 但這是**部署後必須複核**的項目（D8）：確認 gateway 開機 log **沒有** `left-core:` 相關訊息、且開機耗時沒有異常。

### 2.4 拓撲（可安全跳版）

```
git merge-base --is-ancestor upstream-v0.22.4 upstream-v0.22.5  → YES
```

→ v0.22.5 是 v0.22.4 的直系後代 → **不需要中間跳板，直接 v0.22.4 → v0.22.5**。

---

## 3. 需攜帶的自定義補丁

我們的 Dockerfile 對上游的差異共 **8 個 hunk**（對 `upstream-v0.22.4` 已驗證；對 `upstream-v0.22.5` 為 11 個 hunk，因為 base 的 3 處上游變更也被計入 → **merge-tree 實測無衝突**）：

| # | 內容 | v0.22.5 是否仍適用 |
|---|---|---|
| 1 | apt：`openssh-server` `rsync` `locales`；`mkdir /var/run/sshd` + `ssh-keygen -A`；`locale-gen`（`C.UTF-8` / `en_US.UTF-8` / `zh_TW.UTF-8`）+ `/etc/default/locale` + `/etc/profile` + `.bashrc` | ✅ 適配新 base（trixie 同為 Debian 13） |
| 2 | `useradd ... -s /bin/bash hermes` | ✅ |
| 3 | pm ensure + symlink 加入 **`agent-browser`** | ✅ |
| 4 | `build_env --extra edge-tts firecrawl dingtalk feishu exa`（保留上游 `--cache /opt/hermes/uv-cache`） | ✅ |
| 5 | `/tmp/.npm-cache`（sticky bit 1777） | ✅ |
| 6 | `/root/.npm` `/root/.cache` chown 10000 | ✅ |
| 7 | `ENV HOME=/opt/data` | ✅ |
| 8 | `COPY docker/entrypoint-ssh.sh`（Zeabur 相容 shim） | ✅（上游 `entrypoint-dispatch.sh` 零 diff → shim 仍有效） |

自訂 commit 清單（`upstream-v0.22.4..my-config-v0.22.4`，17 個）：

| # | commit | 說明 | 處置 |
|---|---|---|---|
| 1 | `d5916b96f3` | `chore(ci)`:purge 官方 CI，只留 `ghcr-publish.yml` | 🔁 **重做**（在新分支 purge） |
| 2 | `13e0fafadf` | `fix(docker)`:還原 `docker/entrypoint-ssh.sh` | ✅ cherry-pick |
| 3 | `a305a0a3c3` | `chore`:帶入 `docker-compose.yml` | ✅ |
| 4 | `ee9ca7b47f` | `chore`:Mac host 資源限制規則 → AGENTS.md | ✅ |
| 5 | `ca4e57967a` | `feat(docker)`:stage2 SSH 設定 + npm cache | ✅ |
| 6 | `9fd2e4ce38` | `feat(docker)`:re-port custom layer（8 處補丁） | ✅ **可整顆 cherry-pick**（merge-tree 已實測無衝突） |
| 7 | `13fb994c23` | `chore(env)`:`.env.example` 記錄 `HERMES_IMAGE` | ✅（自動合併無衝突） |
| 8 | `99c9c16a76` ~ `ccfb86106d`（10 個） | v0.22.2 / v0.22.4 的 worksheet / upgrade log / post-mortem | ✅ 歷史文檔保留 |

> 📌 `.env` 風險持續解除：commit `27c377fdb4`（v0.22.1 時期）已把 `.env` untrack 並 gitignore；Phase A7 會再跑一次「tracked-but-ignored 遺失偵測」確認。

### 3.1 上游 AGENTS.md 是否有新規則需合併

- [x] §3.1 檢查完畢：`git diff upstream-v0.22.4 upstream-v0.22.5 -- AGENTS.md` **零 diff**；我們的 Mac host 保護區塊原樣帶過去。

---

## 4. 執行步驟 checklist

### Phase 0 — 停機前盤點 + 備份（MANDATORY）

- [ ] 0.1 確認無使用中：`kubectl exec ... -- python3` 查 24h 內訊息數與最後一則時間
- [ ] 0.2 記錄基線（部署後不得下降）
  - **現行基線（2026-10-24 實測）**：`sessions = 127`、`messages = 17,702`、`state.db = 175MB`、`integrity = ok`
  - `session_admissions = 2`、`worker_executions = 0`、`worker_receipts = 0`、`runtime_epoch = 1`
- [ ] 0.3 記錄 FTS 現況：`fts_optimize_available = 1`、`fts_storage_version` 不存在、`messages_fts` = 舊 layout（維持 opt-in，本次不動）
- [ ] 0.4 記錄 config 基線：`_config_version: 51`、`terminal.backend: local`、`sessions.auto_prune: false`、`security.allow_lazy_installs: true`、`toolsets: [hermes-cli]`
- [ ] 0.5 **備份 DB（.db + .db-wal + .db-shm，缺一則不完整）**
  ```bash
  POD=$(kubectl get pod -n hermes -o jsonpath='{.items[0].metadata.name}')
  mkdir -p ~/backups/hermes-20261024
  kubectl cp -n hermes $POD:/opt/data/state.db      ~/backups/hermes-20261024/state.db
  kubectl cp -n hermes $POD:/opt/data/state.db-wal  ~/backups/hermes-20261024/state.db-wal
  kubectl cp -n hermes $POD:/opt/data/state.db-shm  ~/backups/hermes-20261024/state.db-shm
  ```
- [ ] 0.6 驗證備份：`sqlite3 ~/backups/hermes-20261024/state.db "SELECT COUNT(*) FROM messages"` → **17702**
- [ ] 0.7 盤點既有備份並回報使用者
  - `~/backups/hermes-20261022/`（v0.22.4 升級前快照，schema 31，messages 17,671）— **仍在**
  - `~/kubernetes/hermes/backups/` — **已空**（20261015 那份於 2026-10-22 刪除）
  - n100 主機 — **無任何 DB 備份**（`/data/services/hermes/data` 對 SSH 使用者無權限 → 一律走 `kubectl cp`）
- [ ] 0.8 確認 `sessions.auto_prune: false`、`_config_version: 51` 未變

### Phase A — 建分支 + Purge + 攜帶自訂

- [ ] A0. **Go-Sign 確認** → §0.5 決策 A/B/C/D/E
- [ ] A1. `git fetch origin refs/tags/v0.22.5:refs/tags/upstream-v0.22.5 --no-tags`（✅ 已完成，commit `bf0203a794a`）
- [ ] A2. `git checkout -b my-config-v0.22.5 upstream-v0.22.5`
- [ ] A3. Purge 官方 workflows，只留我們的 `ghcr-publish.yml`
  ```bash
  find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete
  git checkout my-config-v0.22.4 -- .github/workflows/ghcr-publish.yml
  ```
- [ ] A4. cherry-pick commit #2 #3 #4 #5 #6 #7（**預期全部零衝突**，merge-tree 已實測）
- [ ] A5. cherry-pick 10 個歷史文檔 commit（v0.22.2 / v0.22.4 worksheet、upgrade log、post-mortem）
- [ ] A6. 複驗 `git diff upstream-v0.22.5 HEAD -- Dockerfile | grep -c '^@@'` = **8**
- [ ] A7. 複驗 Dockerfile 仍含上游 `--cache /opt/hermes/uv-cache` 與 `--record-selection`
- [ ] A8. **tracked-but-ignored 遺失偵測**（承 v0.22.1 教訓）
  ```bash
  comm -23 <(git ls-tree -r my-config-v0.22.4 --name-only | sort -u) \
           <(git ls-tree -r my-config-v0.22.5 --name-only | sort -u) \
    | git check-ignore --stdin --no-index 2>/dev/null
  ```
  期望：**空輸出**
- [ ] A9. 確認 `git log --oneline upstream-v0.22.5..HEAD` 為**線性**（無 merge commit）

### Phase B — 本地輕量驗證（不做重測 / 不本機 build）

- [ ] B1. `git status` 乾淨
- [ ] B2. Dockerfile 8 個自訂標記全數存在：`openssh-server` `rsync` `locales` `en_US.UTF-8` `zh_TW.UTF-8` `ssh-keygen -A` `-s /bin/bash` `agent-browser` `edge-tts` `firecrawl` `uv-cache`
- [ ] B3. `.github/workflows/` 僅 `ghcr-publish.yml`
- [ ] B4. blob 雜湊比對：`docker/entrypoint-ssh.sh`（自製）、`docker/stage2-hook.sh`、`docker/entrypoint-dispatch.sh`、`docker-compose.yml`、`AGENTS.md`、`ghcr-publish.yml` → 應 6/6 SAME
- [ ] B5. dispatch input 仍為 **`tag_name`**（不是 `tag`）
- [ ] B6. 確認 `hermes_state_common.py` 的 `SCHEMA_VERSION` = **32**、`FTS_STORAGE_VERSION` = **3**
- [ ] B7. 確認 config migration 階梯最高 = **51**（`hermes_cli/config_migrations.py`，與 v0.22.4 位元組相同）
- [ ] B8. 確認 `plugins/delegation/default/plugin.yaml` 存在且 `kind: backend`
- [ ] B9. 確認 `scripts/write_install_stamp.py` 存在且 CLI 參數不變（我們的 workflow 依賴它）
- [ ] B10. 確認新 base image 為 `debian:trixie-20261020@sha256:4c252754...`（兩個 FROM 一致）
- [ ] B11. 確認 `scripts/build/electron-runtime.mjs` 存在（上游 COPY 依賴它）
- [ ] B12. npm 決策複驗：根 `package-lock.json` 的 `overrides` 仍為空 → 維持「不修」
- [ ] B13. `.env` 仍在 working tree 且未被刪

### Phase C — 推送 + 建置

- [ ] C1. `git push -u kuniakil my-config-v0.22.5`
- [ ] C2. dispatch：**`gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v0.22.5 -f tag_name=v0.22.5 -f platforms=all`**
- [ ] C3. 驗證 run：`event=workflow_dispatch`、`headBranch=my-config-v0.22.5`、`headSha` = **我方 commit**（絕非 `bf0203a794a`）
- [ ] C4. `gh run watch` → prepare / linux-amd64 / linux-arm64 / merge 全 success
      ⭐ **必須派給背景子代理**（10+ 分鐘），主迴圈不得 blocking
- [ ] C5. image tags 存在：`v0.22.5`、`latest`
- [ ] C6. **未 force-push 版本 tag**（發布模型由分支建置，tag 與 build 無關）
- [ ] C7. 若出現 `HTTP 422 "Actions has been disabled for this repository"` → **停止並走 `/actions` 橫幅重新啟用**（不要重試、 不要清 cache、不要改 settings）

### Phase D — 部署 + 驗證

- [ ] D1. `~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag: "v0.22.4"` → `"v0.22.5"`
- [ ] D2. `kubectl kustomize .` render 正確；`kubectl apply -k` 後 `kubectl rollout status` **successfully rolled out**
- [ ] D3. 冒煙測試（對照 v0.22.4 基線）：
  - Python 3.14.x + `ruamel.yaml.clib` C 加速可用
  - **Node.js `v26.12.1`**（R2）
  - **Debian base = trixie**（`cat /etc/os-release`）（R3）
  - locale 3 種（`C.utf8` / `en_US.utf8` / `zh_TW.utf8`）
  - sshd + rsync + tini + ffmpeg + agent-browser
  - extras（edge-tts 7.3.1 / firecrawl / dingtalk_stream / lark_oapi / exa_py）
  - Telegram connected、**0 ERROR**
- [ ] D4. **版本確認**：`hermes --version` 應顯示 `v0.22.5` 且 `upstream <我方 commit sha>`
- [ ] D5. **schema 檢查**：`state.db` `schema_version` 實測仍為 **32**（**不得變 33**）；`session_admissions` / `worker_executions` / `worker_receipts` / `runtime_epoch` 表存在
- [ ] D6. **資料完整性**：`sessions` / `messages` 計數**不得下降**（基線 127 / 17,702）；`PRAGMA integrity_check` = ok
- [ ] D7. **🔴 開機驗證**：刪 pod 強制重啟，確認 gateway 在新 PID 下正常啟動、`RESTARTS` 歸零後不迴圈
- [ ] D8. **🔴 left-core 檢查（R1）**：開機 log **不得**出現 `left-core` / `Installing plugin` / catalog 自動安裝相關訊息；gateway 開機耗時與 v0.22.4 持平
- [ ] D9. **🔴 delegation 檢查**：`delegate_task` 仍可用（預設 backend 繼承 parent model）；確認 `plugins/delegation/default` 已被發現
- [ ] D10. **🔴 session 刪除測試**：抽 1 個帶 ledger 歷史的 session 實測 `hermes sessions delete` → 應**能刪**（刪後 `session_admissions` 對應列歸零）
- [ ] D11. **FTS 檢查**：`state_meta.fts_storage_version` 應**仍不存在**、`fts_optimize_available` = 1；確認**沒有**在 open 時自動重建（`messages_fts` DDL 仍是 `fts5(content)`）
- [ ] D12. **auto-prune 檢查**：`sessions.auto_prune` 仍為 `false`、`_config_version` 仍 51、**沒有**任何 migration 紀錄被寫入
- [ ] D13. 部署 60s 後 **0 restart**、log 無 ERROR/Traceback
- [ ] D14. 真實訊息往返（Telegram 收 → 模型 → 工具 → 送出）→ **待使用者送一則訊息**

### Phase E — 收尾

- [ ] E1. 產出 `UPGRADE_LOG_v0.22.4_to_v0.22.5.md`
- [ ] E2. 在 post-mortem 加入「v0.22.5 是 81 PR 正常 patch 窗口、官方 curated notes 仍延到 v0.23.0」
- [ ] E3. 本工作表同步實際執行結果（image digest / run id / 實測數字）
- [ ] E4. `~/kubernetes` kustomization 變更 commit + push
- [ ] E5. 備份處置：**已提示使用者，等明確同意才刪**（`~/backups/hermes-20261024`）

---

## 5. 風險總結

| 風險 | 等級 | 緩解 |
|---|---|---|
| **left-core 自動安裝在 gateway 開機路徑上**（R1） | 🟡 中 | §2.3 已用 8 項條件唯讀勘查證實不會觸發；D8 部署後複核 |
| **Node runtime v26.7.0 → v26.12.1**（R2） | 🟡 中 | D3 冒煙測試驗證 node + 前端 bundle 相容 |
| **base image `debian:13.4` → `debian:trixie-20261020`**（R3） | 🟡 中 | 同為 Debian 13 trixie 家族；D3 驗證 8 個自訂 apt 補丁 |
| delegation 改走 plugin backend 機制 | 🟡 中 | 預設 bundled plugin 行為等價；D9 實測 `delegate_task` |
| `edge-tts` 7.2.7 → 7.3.1 | 🟢 低 | 我們有裝這個 extra → D3 冒煙涵蓋 |
| **Pillow 12.3.0 → 13.0.0**（安全 bump，有 override 處理 browser-harness 硬 pin） | 🟢 低 | 官方已加 `override-dependencies = ["Pillow==13.0.0"]`；vision 相關功能我們有在用 → D3 冒煙 |
| `certifi` 2026.10.19 + `exclude-newer-package` 豁免 | 🟢 低 | TLS 憑證更新，容器用 OS trust store；冒煙涵蓋 |
| 804 檔 diff（其中 ~530 檔是 desktop/website） | 🟢 低 | 容器 runtime 實際變動 212 檔；核心 gateway/agent 變動量可控 |
| 官方仍無 curated notes（延到 v0.23.0） | 🟢 低 | 本窗口僅 81 PR，已完整盤點 |
| **Schema / FTS / config migration** | 🟢 **無** | 三者全部未變；回滾路徑完整，不依賴 DB 備份 |
| **Dockerfile 補丁衝突** | 🟢 **無** | `git merge-tree` 實測 **0 衝突**（唯一 8 個 workflow 衝突由 Purge 規則消化） |
| ~57 個 workflow 衝突 | 🟢 **無** | Purge 規則直接刪除 |
| Python 版本 / requires-python | 🟢 **無** | `>=3.11,<3.15` 不變，容器 3.14.x 相容 |
| npm 漏洞 | 🟢 無（既有決策） | 3 個觸發 issue 今日仍 OPEN；關鍵套件版本零變化；暴露面 = 0 |
| `pm/lock.json` Node bump | 🟡 中 | R2；D3 覆蓋 |
| Nous sign-in 重做 | 🟢 無 | 我們不用 Nous 帳號（`providers = {}`、無 `NOUS_*` env） |

---

## 6. npm 漏洞決策複查（承 v0.22.0 / v0.22.2 / v0.22.4 §6）

| 檢查 | 結果（2026-10-24） |
|---|---|
| ① 根 `package-lock.json` `overrides` v0.22.4 → v0.22.5 | 皆為 **空 / None** → **「不修」決策前提成立** |
| ② 觸發條件 issue 狀態 | **#133435 OPEN、#132924 OPEN、#79021 OPEN** → 條件**未成立** → 維持「不修」 |
| ③ 關鍵套件是否惡化 | undici 7.30.0 → 7.30.0、axios 1.20.0 → 1.20.0、js-yaml 4.3.2 → 4.3.2 → **零變化** |
| ④ 上游是否自行修掉部分 | 🟢 有：`package.json` overrides 移除 `electron@40.10.2` 條目（Electron 改由 `apps/desktop` 管理，Electron 44.9.3）；根層無新增 override |
| ⑤ 我們的實際 runtime 暴露面 | photon sidecar 未啟用、Electron desktop 不部署 → **暴露面 = 0**（沿用 v0.22.0 實測結論） |

---

## 7. 專案特定備註（Hermes）

- **Fork remote**：`kuniakil`；**Upstream remote**：`origin`（⚠️ 與 OpenClaw 相反，先跑 `git remote -v` 確認）
- **Workflow**：`ghcr-publish.yml`（上游**沒有**這個檔，純自訂）
- **dispatch input**：**`tag_name`**（**不是** `tag`；傳錯會被靜默忽略，只會產出 `latest`）
- **k8s overlay**：`~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag` → `v0.22.5`
- **資料路徑**：pod `/opt/data` = hostPath `/data/services/hermes/data`（n100，**SSH 使用者無權限讀取** → 備份走 `kubectl cp`）
- **Host 保護**：本機**不**跑 pytest / docker build / 全面 typecheck；僅 `git diff` / `git status` + 單檔語法檢查；編譯與完整測試交由 GitHub Actions
- **⏳ 長等待必派子代理**：`gh run watch` / `kubectl rollout status` 一律背景子代理，主迴圈保持可回應

---

## 8. Go-Sign

- [ ] §0.5 決策 **A**：目標版本 = **v0.22.5**
- [ ] §0.5 決策 **B**：不等 v0.23.0
- [ ] §0.5 決策 **C**：npm 漏洞 = **維持不修**
- [ ] §0.5 決策 **D**：FTS layout 漂移 = **本次不處理**
- [ ] §0.5 決策 **E**：v0.22.4 備份**保留**（不刪）
- [ ] 使用者回覆「Go」→ Phase 0 → A → B → C → D → E 依序執行

---

## 9. 附錄：2026-10-24 n100 實地勘查（唯讀）

### 9.1 部署現況

```
hermes-agent-5656b5d479-6rnjx   1/1 Running   0 restarts   46h   node=n100
image : ghcr.io/kuniakil/hermes-agent:v0.22.4
```

### 9.2 DB 勘查（`/opt/data/state.db`，唯讀 `mode=ro`）

| 項目 | 值 |
|---|---|
| `sessions` | **127** |
| `messages` | **17,702** |
| `PRAGMA integrity_check` | **ok** |
| `session_admissions` | **2**（正常運作後的 ledger 資料，非殘留） |
| `worker_executions` / `worker_receipts` | **0 / 0** |
| `runtime_epoch` | 1 |
| `fts_optimize_available` | 1 |
| `fts_storage_version` | **不存在**（未 settle，維持 opt-in） |
| 新表（v0.22.4 引入） | `session_turn_leases`、`session_model_usage`、`async_delegations` 均存在 |

### 9.3 config 勘查（決定 R1 是否觸發的關鍵）

```
_config_version: 51
toolsets: [hermes-cli]                       （config.yaml:5-6）
terminal.backend: local                      （config.yaml:28）
sessions.auto_prune: false                   （config.yaml:507）
security.allow_lazy_installs: true           （config.yaml:455）
platform_toolsets.cli: browser, clarify, code_execution, computer_use, connections,
                      cronjob, delegation, file, image_gen, memory, session_search,
                      skills, terminal, todo, tts, video_gen, vision, web
                                        （config.yaml:549+ — 無 spotify / homeassistant）
auth.json providers: {}                       （無 spotify 登入）
容器 env: 無 NOUS_* 、無 HASS_* 、無 SPOTIFY_*、無 TERMINAL_ENV
HERMES_DISABLE_LAZY_INSTALLS: （空）
```

### 9.4 工具鏈現況

| 項目 | 現況 | v0.22.5 變化 |
|---|---|---|
| Python | 3.14.x | 不變（`>=3.11,<3.15`） |
| Node.js | `v26.7.0` | **`v26.12.1`**（R2） |
| Base image | `debian:13.4` | **`debian:trixie-20261020`**（R3） |
| SSH | sshd + host key（hostPath 掛載） | 不變 |
| 本機 runtime | **未使用** | 不變 |
