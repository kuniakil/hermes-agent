# Hermes Agent 升級工作表：v0.22.5 → v0.22.6

- **目標版本**：`v0.22.6`（官方 commit `f0d94882e89ab8d4098b5bb2f166adfb9ee0a0ab`，2026-11-02 發佈 / 2026-11-03 上架 GitHub Release）
- **升級前版本**：`my-config-v0.22.5`（HEAD `5301eaa488`，基於官方 `v0.22.5` = `bf0203a794`）
- **新分支**：`my-config-v0.22.6`
- **Remote**：`origin` = 官方（NousResearch）、`kuniakil` = 個人 fork（⚠️ 與 OpenClaw 相反）
- **發布模型**：`my-config-v0.22.6` 分支為 source of truth，由 `ghcr-publish.yml`（dispatch input **`tag_name`**）建置 `ghcr.io/kuniakil/hermes-agent:v0.22.6`
- **目前上線版本**：`v0.22.5`（K3s n100，pod `hermes-agent-665b4bfd7b-dfjlm`，running 9d）
- **狀態**：📋 **計畫中，等待 Go-Sign**
- **日期**：2026-11-03

---

## 0. ⚠️ 最高優先結論：776 PR 大收斂窗口、Schema 未變（可逆），但有 1 個必解的 Dockerfile 重大變革（`agent-browser` 退役）

### 0.1 官方 Release Notes 摘要（v0.22.6，2026-11-02）

> Patch release. This tag rolls up the **~776 PRs merged since v0.22.5** into a stable release for the GitHub release (CLI and installers), the Microsoft Store app, Docker and Hermes Cloud. **Full curated notes for this window ship with v0.23.0.**

官方量測（commit `f0d94882e89`）：

| 指標 | 值 |
|---|---|
| non-merge commits | **3,448** |
| changed files | **4,316** |
| 行數 | **+248,579 / −94,077** |
| merged PRs | **776** |
| closed issues | **385** |

> ℹ️ **官方再次把 curated notes 延到 v0.23.0**（與 v0.22.3/4/5 同一模式）。這次窗口規模相當於 `v0.22.2 → v0.22.4`（4,316 檔 vs 4,242 檔），屬於 776 PR 的大型收斂版，我們已直接從 git diff 與線上實測完成完整稽核（見 §1 / §2）。

官方「on purpose 列舉」的本窗口重點功能：

- **Webapp（瀏覽器版 Desktop）**：由 gateway 自身 listener 提供（`hermes webapp`），Dockerfile 新增 `webapp_build` stage 產出 `/opt/hermes/apps/desktop/dist-webapp`
- `/model reset`：清除 session 的 model pin 而不丟失對話歷史
- **per-skill locks**（`tools/skill_lock.py`）：防止自主寫入（可從 Desktop Capabilities 鎖定）
- **prepared compaction**（`compression.prepare_ahead`，`agent/prepared_compaction.py`）：opt-in 預先壓縮
- `hermes cron cancel` + per-job missed-run policy + Desktop cron Stop 按鈕
- `/delegation` 選擇會跨 session 記住到下一回
- `hermes migrate` 與 setup 支援從 Grok Bot / OpenBot 遷移
- vault key 支援 opt-in OS-keychain 儲存
- plugin catalog 的 `requires_hermes` 在 install 與 update 時強制檢查
- `text_to_speech` 支援由 agent 自選 ElevenLabs voices（`tools/tts_elevenlabs_voices.py`）
- `pre_llm_call` hook 可在 inference 前阻擋回合
- Desktop group chat（rename / disband / mentions / 貼圖）與 sidebar profile 分組
- Telegram video notes、Slack thread context emoji reactions
- PM（package manager）支援斷點續傳下載

### 0.2 核心 runtime vs 外圍變動量拆解

| 比較基準 | 檔案數 | +/− | 意義 |
|---|---|---|---|
| `v0.22.4 → v0.22.5`（上次） | 804 | +35,212 / −17,885 | 81 PR 常規窗口 |
| **`v0.22.5 → v0.22.6`（本次）** | **4,316** | **+248,579 / −94,077** | **776 PR 大型收斂窗口** |
| 其中核心 runtime（`gateway/ agent/ tools/ hermes_cli/ plugins/ cron/`） | **940** | **+52,159 / −18,896** | 其餘 ~3,376 檔為 `apps/desktop/`、`website/`、`tests/` |

### 0.3 ✅ DB Schema 完全未變（**無 DB 不可逆性**），Config Schema `51 → 52`

| 項目 | v0.22.5 | v0.22.6 | 判定 |
|---|---|---|---|
| `hermes_state_common.py: SCHEMA_VERSION` | **32** | **32** | ✅ **未變（DB 完全相容、可逆）** |
| `hermes_state_common.py: FTS_STORAGE_VERSION` | **3** | **3** | ✅ 未變 |
| config migration 階梯最高 | **51** | **52**（新增 `migrate_to_52`） | 🟡 **見 §1.3 / R2（對我們為 no-op）** |
| `hermes_state*.py` 變更 | — | 新增 `SessionPromptRefreshMixin`（無 DDL 變更） | ✅ 無表結構或欄位增減 |
| Python `requires-python` | `>=3.11,<3.15` | `>=3.11,<3.15` | ✅ 未變（容器內 `3.14.9+20261021`） |

> 🟢 **DB 結論：`SCHEMA_VERSION` 維持 32，沒有任何 SQLite table/trigger/index DDL 遷移 → 若需回滾，直接退回 `v0.22.5` image 即可，無單向鎖定。**
> 🟡 **Config 結論：`_config_version` 會在 stage2 開機時由 `51 → 52`（`migrate_to_52`）。已對線上 `/opt/data/config.yaml` 與 `.env` 唯讀實測，我們的設定不觸發任何鍵值搬移或刪除（純推進版本戳記）。但停機前仍強制執行完整備份（Phase 0）。**

### 0.4 🔴 本次升級的 4 個關鍵技術變更與風險（必讀）

| # | 變更 | 對我們的影響 | 處置與驗證方式 |
|---|---|---|---|
| **R1** | **🔴 `agent-browser` 從 `pm/lock.json` 與 `pm/packages.py` 徹底移除**（commit `1ac18d2b12`：`refactor(pm): drop the agent-browser package; Chromium is a default package in its own right`） | 我們舊版 Dockerfile 第 3 個自訂 hunk 寫了 `[ensure(name) for name in (..., "agent-browser", ...)]` 與 symlink `agent-browser`。**若原樣保留，`docker build` 會在 PM stage 直接報錯失敗！** 上游已全面改用 `browser_exec` 直接驅動 pinned `chromium`（路徑寫在 `/etc/hermes/chromium-executable-path`）。 | **移除我們 Dockerfile 的 hunk #3（不再安裝/symlink `agent-browser`）**，完全對齊上游 `chromium` 機制（保留 7 個有效自訂 hunk）。 |
| **R2** | **🟡 Config migration `51 → 52` + Left-Core 新增 `camofox` 與 `github-copilot`**（`hermes_cli/config_migrations_browser.py` + `left_core_migration.py`） | v52 將內建 Camofox backend 與 GitHub Copilot provider 移出 core 變 plugin。若 `camofox_in_use()` 或 `copilot_in_use()` 為 True，gateway 開機會自動從 catalog 安裝 plugin 並把 `browser` toolset 關掉換成 `camofox` toolset。 | **已對 n100 線上環境唯讀實測（見 §2.3）**：我們走的是 **MCP（`mcp_servers.camofox`）**，`.env` **沒有** `CAMOFOX_URL`、`config.yaml` **沒有** `browser.cloud_provider` → **`camofox_in_use()` = `False`**！`copilot_in_use()` = **`False`**！兩者皆**不會**觸發。部署後於 D8 複核。 |
| **R3** | **🟡 Dockerfile 自訂 hunk #1（apt）與 #4（`pm.build_env` extras）與上游新增項目重疊** | 上游在 apt 加入了 `tmux`，在 `pm.build_env` 加入了 `--extra fal --extra documents`，並新增 `webapp_build` stage 與 `/etc/profile.d/hermes.sh`。 | 更新我們的 Dockerfile 自訂 commit：**保留上游新增的 `tmux` 與 `--extra fal --extra documents`**，疊加我們的 `openssh-server rsync locales` 與 `--extra edge-tts firecrawl dingtalk feishu exa`。 |
| **R4** | **🟢 Python 核心依賴常規升版**（`openai 2.24.0→2.54.0`、`pydantic 2.13.4→2.14.1`、`requests 2.33.0→2.34.2`、`croniter 6.0.0→6.2.4` 等） | Base image（`debian:trixie-20261020`）、Python（`3.14.9`）、Node（`26.12.1`）、Chromium（`145.0.7632.6`）全部未變。 | D3 冒煙測試涵蓋 Python / SDK / extras 載入與 Telegram 連線驗證。 |

### 0.5 決策點（Go-Sign 時請一併回覆）

| # | 決策 | 建議 | 理由 |
|---|---|---|---|
| **A** | 目標版本 | **v0.22.6** | 官方最新 stable；修正與收斂 776 PR |
| **B** | Dockerfile 自訂 hunk #3（`agent-browser`）處置 | **移除該 hunk（隨上游退役）** | 上游 `pm/lock.json` 與 `pm/packages.py` 已刪除 `AgentBrowser`，強留必導致 CI build failure；Chromium 本體仍內建於 `/opt/hermes/tools`，且我們主力瀏覽器為 `mcp_servers.camofox` |
| **C** | **npm 漏洞**是否修 | **維持「不修」** | 3 個追蹤 issue（`#133435` / `#132924` / `#79021`）今日（2026-11-03）複查**仍全為 OPEN**；實際 runtime 暴露面 = 0（見 §6） |
| **D** | FTS layout 漂移是否順手 `optimize-storage` | **不做** | 屬 pre-existing 狀態，維持 opt-in，不與版本升級混做 |
| **E** | 舊備份 `~/backups/hermes-20261024/`（v0.22.5 升級前快照）處置 | **待本次 v0.22.6 驗證通過後再詢問是否刪除** | 升級前先建新備份 `~/backups/hermes-20261103/`；待 Phase D 驗收完畢後再依規則請示清理 `20261024` |

---

## 1. 官方 Release Notes 與機器可讀真相稽核

### 1.1 Breaking Changes / Left-Core 隱含變更盤點

| 隱含變更 | 內容 | 對我們的影響與判定 |
|---|---|---|
| 🔴 **`agent-browser` PM 套件移除** | `pm/packages.py` 刪除 `AgentBrowser`、`pm/lock.json` 移除 `agent-browser: 0.26.0`；`/etc/hermes/agent-browser-executable-path` 改名為 `/etc/hermes/chromium-executable-path`；內建瀏覽器工具統一為 `browser_exec` 直接驅動 Chromium | 🔴 **必須調整我方 Dockerfile hunk #3**（移除 `agent-browser` 的 `pm.ensure` 與 `/usr/local/bin/agent-browser` symlink）；冒煙測試改驗 `/etc/hermes/chromium-executable-path` |
| 🟡 **Camofox built-in backend 移出 core → `camofox` catalog plugin**（`left_at=52`） | 舊版內建的 `tools/browser_camofox.py` 移出 core。若 `camofox_in_use()` 為真，v52 migration 會標記 `_left_core_used: ["camofox"]`，並在開機時自動安裝 `camofox` plugin、同時把 `browser` toolset 關閉換成 `camofox` | 🟢 **完全不影響我們**：我們在 2026-10-24 已將 Camofox 改為標準 MCP server（`mcp_servers.camofox` → `http://camofox-mcp.camofox.svc.cluster.local:8080/mcp`），不走內建 `CAMOFOX_URL` backend（見 §2.3 實測證明） |
| 🟡 **GitHub Copilot provider 移出 core → `github-copilot` catalog plugin** | 若 `copilot_in_use()` 為真（路由經過 `copilot` / `github-copilot` / `models.github.ai`），開機自動裝 plugin（注意：`.env` 單純有 `GITHUB_TOKEN` **不算** in_use，程式碼明寫 `A GH_TOKEN in .env alone is not use`） | 🟢 **我們不觸發**：我們的 model provider 為 `minimax`（`MiniMax-M3`），無任何 copilot 路由 |
| 🟢 **`docker/profile-hermes-path.sh` 新增** | 安裝於 `/etc/profile.d/hermes.sh`，確保 login shell（含 `ssh`、`bash -l`）自動將 `/opt/hermes/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin` 放回 `PATH` | 🟢 與我們 `stage2-hook.sh` 的 `.bashrc`/`.profile` PATH 設定相容且互補 |
| 🟢 **`Dockerfile` 新增 `webapp_build` stage** | 編譯 `apps/desktop/dist-webapp` 供 `hermes webapp` 使用 | 🟢 在 GitHub Actions CI 內建置，不影響我們自訂層 |

### 1.2 機器可讀真相（Dependency / Runtime 稽核）

| 項目 | v0.22.5 | v0.22.6 | 判定 |
|---|---|---|---|
| `pyproject.toml` `requires-python` | `>=3.11,<3.15` | `>=3.11,<3.15` | ✅ 不變 |
| Base image (`Dockerfile` 兩個 `FROM`) | `debian:trixie-20261020@sha256:4c252754...` | **`debian:trixie-20261020@sha256:4c252754...`** | ✅ **完全相同（零變動）** |
| `pm/lock.json` Python / Node / npm / uv / ffmpeg / ripgrep / chromium | Python `3.14.9+20261021`、Node `26.12.1`、npm `12.0.2`、uv `0.13.5`、chromium `1208+145.0.7632.6` | **完全相同**（僅刪除 `agent-browser` 條目） | ✅ 工具鏈版本零變動 |
| `openai` | `2.24.0` | **`2.54.0`** | 🟡 核心 SDK 升版 → D3 冒煙驗證 |
| `pydantic` | `2.13.4` | **`2.14.1`** | 🟢 常規升版 |
| `requests` / `python-dotenv` / `truststore` / `rich` / `tenacity` / `croniter` / `packaging` / `Markdown` | `2.33.0` / `1.2.2` / `0.10.4` / `14.3.3` / `9.1.4` / `6.0.0` / `26.0` / `3.10.2` | **`2.34.2` / `1.2.4` / `0.10.5` / `14.3.4` / `9.2.1` / `6.2.4` / `26.3` / `3.11.2`** | 🟢 常規 patch/minor 升版 |
| `Dockerfile` `pm.build_env` 預設 extras | `all messaging otlp anthropic bedrock azure-identity matrix google-chat` | 新增 **`--extra fal --extra documents`** | 🟢 我們合併保留上游這 2 個 extra + 我們的 5 個 extra |
| `docker/stage2-hook.sh` | `48eb36f5a9` | `b87d8b5b4c`（改用 `/etc/hermes/chromium-executable-path` + `selected_config_backend_name` 檢查） | 🟢 **與我們的 SSH / npm-cache hunk 自動合併零衝突**（`git merge-tree` 已證） |
| `docker/entrypoint-dispatch.sh` | 存在 | **存在，零 diff** | 🟢 `entrypoint-ssh.sh` 依賴有效 |
| `scripts/write_install_stamp.py` | 存在 | **存在，零 diff** | 🟢 `ghcr-publish.yml` 依賴有效 |
| `AGENTS.md` | 存在 | **零 diff** | 🟢 Mac host 保護規則直接帶過去 |

### 1.3 Schema / 不可逆性判定

> **判定：DB 層完全非不可逆（`SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3` 均未變）。Config 層 `_config_version` 由 `51 → 52`，但對我方線上 `config.yaml` 為純版本號推進（不刪改任何設定鍵）。**

---

## 2. Diff 與衝突面稽核（`upstream-v0.22.5 → upstream-v0.22.6`）

### 2.1 `git merge-tree` 實測衝突報告

執行指令：
```bash
git merge-tree --write-tree --merge-base=upstream-v0.22.5 upstream-v0.22.6 my-config-v0.22.5
```

| 類別 | 檔案數 | 明細與處置 |
|---|---|---|
| **Modify/Delete 衝突（`.github/workflows/*`）** | **9 檔** | `bootstrap-installer-build.yml`、`deploy-site.yml`、`e2e-desktop-core.yml`、`install-e2e-macos-run.yml`、`install-e2e.yml`、`js-tests.yml`、`lint.yml`、`tests-os.yml`、`tests.yml` → **依 Purge 規則全數刪除，只留 `ghcr-publish.yml`（零人工解衝成本）** |
| **Content 衝突（`Dockerfile`）** | **1 檔** | 共 3 處重疊：<br>① apt 清單：上游加 `tmux`，我們加 `openssh-server rsync locales` + sshd/locale 初始化 → **合併兩者**<br>② PM 安裝清單：上游刪 `agent-browser` 並改寫 `/etc/hermes/chromium-executable-path`，我們舊版加了 `agent-browser` → **採用上游（淘汰 hunk #3）**<br>③ `pm.build_env`：上游加 `--extra fal --extra documents`，我們加 `--extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa` → **合併兩者** |
| **自動合併無衝突（Auto-merged cleanly）** | **全部其餘自訂檔** | `docker/stage2-hook.sh`、`.env.example`、`AGENTS.md`、`docker-compose.yml`、`docker/entrypoint-ssh.sh`、以及 `docs/` 下所有歷史工作表與測試報告 |

### 2.2 `stage2-hook.sh` 與我們自訂 `.bashrc` 的互動檢查

上游在 `docker/stage2-hook.sh` 的變動：
1. 不再將 `AGENT_BROWSER_EXECUTABLE_PATH` 寫入 `/run/s6/container_environment`，改為僅檢查 `/etc/hermes/chromium-executable-path` 是否存在且可執行（因為 `hermes_cli/browser_runtime.py` 會自己讀 `/etc/hermes/chromium-executable-path`）。
2. 在跑 `docker_config_migrate.py` 前先透過 `selected_config_backend_name` 檢查是否為 `remote` backend（我們是預設 local file，故照常執行 `docker_config_migrate.py`）。

我們的 `stage2-hook.sh` 自訂區塊（SSH 啟動 + `.bashrc`/`.profile` 產生 + `/tmp/.npm-cache`）位於第 76–150 行與第 487 行，與上游修改區塊（第 730–790 行）相距超過 250 行，`git merge-tree` 實測 **100% 自動合併零衝突**。

### 2.3 🟡 R2 深入勘查：v52 Config Migration 與 Left-Core（Camofox / Copilot）線上實測

我們對目前運行中的 n100 Pod（`hermes-agent-665b4bfd7b-dfjlm`）進行了唯讀勘查，逐一對照 `migrate_to_52`（`hermes_cli/config_migrations_browser.py`）與 `LEFT_CORE`（`hermes_cli/left_core_migration.py`）的觸發條件：

| 檢查項目 | 程式碼觸發條件 | 線上 `/opt/data` 實測值（2026-11-03） | 判定 |
|---|---|---|---|
| `migrate_to_52`: `browser.backend` | `"backend" in browser` | `browser` 僅含 `inactivity_timeout`, `command_timeout`, `record_sessions`, `allow_private_urls`, `engine`, `auto_local_for_private_urls`, `cdp_url`, `dialog_policy`, `dialog_timeout_s`, `camofox` — **無 `backend` 鍵** | 🟢 不觸發 |
| `migrate_to_52`: `browser.extension_control` | `"extension_control" in browser` | **無 `extension_control` 鍵** | 🟢 不觸發 |
| `migrate_to_52`: `move_agent_browser_env` | `.env` 含 `AGENT_BROWSER_*` 變數 | `.env` **零 `AGENT_BROWSER_*` 變數** | 🟢 不觸發 |
| **`camofox_in_use()`**（`left_at=52`） | `browser.cloud_provider == "camofox"` 或 `.env` / process env 有 `CAMOFOX_URL`（註：程式碼明寫 `browser.camofox settings never selected it: a leftover block without an address ran browser_exec`） | `browser.cloud_provider` **不存在**；`.env` **無 `CAMOFOX_URL`**（我們的 Camofox 走 `mcp_servers.camofox.url = http://camofox-mcp.camofox.svc.cluster.local:8080/mcp`） | 🟢 **`False`（絕不觸發自動裝 plugin，也不會把 `browser` toolset 關掉）** |
| **`copilot_in_use()`** | `model` / `fallback_providers` / `delegation` / `cron` 路由選用 `copilot` 或 `github-copilot`（`.env` 單純有 `GITHUB_TOKEN` 不算） | `model.provider = "minimax"`、`fallback_providers = []`、`delegation.provider = ""`、`auth.json` `providers = []` | 🟢 **`False`（不觸發）** |
| 其餘 `LEFT_CORE` 列（`homeassistant` / `spotify` / `langfuse` / `mcp-serve` / `singularity` / `agent-importers`） | 與 v0.22.5 相同 | 與 v0.22.5 相同，全數未啟用 | 🟢 **`False`（不觸發）** |

> ✅ **結論：v52 migration 在開機時只會把 `/opt/data/config.yaml` 的 `_config_version` 從 `51` 更新為 `52`，不會改動任何設定結構，也不會在 gateway 啟動時觸發任何 catalog plugin 下載。我們的 `mcp_servers.camofox` 100% 獨立運作、不受影響。**

---

## 3. 需攜帶的自定義補丁清單

### 3.1 Dockerfile 自訂層（由 8 個 hunk 精簡為 **7 個有效 hunk**）

| # | 位置 | 內容 | v0.22.6 處置 |
|---|---|---|---|
| 1 | `runtime_base` apt | 在上游 apt 清單（含新加的 `tmux`）加上 `openssh-server` `rsync` `locales`；建立 `/var/run/sshd` + `ssh-keygen -A`；產生 `C.UTF-8` / `en_US.UTF-8` / `zh_TW.UTF-8` locale 並寫入 `/etc/default/locale`、`/etc/profile`、`.bashrc` | ✅ **保留並合入上游 `tmux`** |
| 2 | `useradd` | `RUN useradd -u 10000 -m -d /opt/data -s /bin/bash hermes` | ✅ **保留** |
| ~~3~~ | ~~PM `ensure`~~ | ~~舊版加入 `"agent-browser"` 與 `/usr/local/bin/agent-browser` symlink~~ | 🔴 **移除（上游已將 `agent-browser` 自 `pm/lock.json` 與 `pm/packages.py` 移除，改由 `chromium` 獨立提供）** |
| 3 (原4) | `python_deps` `pm.build_env` | 在上游 extras（含新加的 `--extra fal --extra documents`）後方加上 `--extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa` | ✅ **保留並合入上游 `fal` + `documents`** |
| 4 (原5) | `runtime` `/tmp/.npm-cache` | `RUN mkdir -p /tmp/.npm-cache && chmod 1777 /tmp/.npm-cache` | ✅ **保留** |
| 5 (原6) | `runtime` `/root/.npm` | `RUN mkdir -p /root/.npm /root/.cache && chown -R 10000:10000 /root/.npm /root/.cache` | ✅ **保留** |
| 6 (原7) | `runtime` `ENV HOME` | `ENV HOME=/opt/data` | ✅ **保留** |
| 7 (原8) | `runtime` entrypoint shim | `COPY --chmod=0755 docker/entrypoint-ssh.sh /opt/hermes/docker/entrypoint-ssh.sh` | ✅ **保留** |

### 3.2 自訂 Commits 攜帶計畫（`upstream-v0.22.5..my-config-v0.22.5`，共 27 個 commits）

在 `my-config-v0.22.6`（基於 `upstream-v0.22.6`）上依序處理：

| 順序 | 原 Commit | 類別 | 說明 | 處置方式 |
|---|---|---|---|---|
| 1 | `f3f9e262a1` | CI Purge | `chore(ci): purge official CI workflows; retain only ghcr-publish.yml` | 🔁 **重新執行 `find .github/workflows ! -name 'ghcr-publish.yml' -delete` 並取回 `ghcr-publish.yml`** |
| 2 | `525149ec3e` | Docker | `fix(docker): restore docker/entrypoint-ssh.sh for Zeabur backward compatibility` | ✅ `git cherry-pick`（無衝突） |
| 3 | `b2c1cdc689` | Docker | `chore: carry forward my-config docker-compose.yml (uses HERMES_IMAGE env, TZ=Asia/Taipei)` | ✅ `git cherry-pick`（無衝突） |
| 4 | `fb932d5ef9` | Docs/Rule | `chore: re-append Mac host resource constraint rule to AGENTS.md (v0.21.6)` | ✅ `git cherry-pick`（無衝突） |
| 5 | `50ae081e39` | Docker | `feat(docker): restore custom SSH setup and npm cache handling in stage2-hook.sh` | ✅ `git cherry-pick`（自動合併無衝突） |
| 6 | `4f42a128e9` | Docker | `feat(docker): re-port custom layer (SSH, locales, extras, perms) onto v0.22.6` | 🔧 **cherry-pick 時解 3 處重疊（合入 `tmux`、`fal`/`documents`，移除已退役的 `agent-browser`），產出乾淨的 7 hunk** |
| 7 | `aa6697402b` | Env | `chore(env): document HERMES_IMAGE in .env.example (k8s pins newTag, not .env)` | ✅ `git cherry-pick`（自動合併無衝突） |
| 8 | `2fd00e7040` ~ `5301eaa488`（20 個 commits） | Docs | v0.22.2 / v0.22.4 / v0.22.5 升級工作表、post-mortem、以及 Camofox MCP 跨 Agent 測試報告 | ✅ `git cherry-pick`（全為 `docs/` 獨立檔案，零衝突） |

---

## 4. 執行步驟 Checklist（待收到 Go-Sign 後依序執行）

### Phase 0 — 停機前盤點 + 備份（MANDATORY）

- [ ] 0.1 確認無使用中：查 24h 內訊息數與最後一則時間（2026-11-03 08:42 預檢：`msgs_24h = 0`，最後一則為 `2026-10-24 22:24:39`）
- [ ] 0.2 記錄升級前基線（部署後不得下降）：
  - **2026-11-03 預檢基線**：`sessions = 132`、`messages = 18,023`、`state.db = 176MB`、`integrity = ok`
  - `session_admissions = 8`、`worker_executions = 0`、`worker_receipts = 0`、`runtime_epoch = 1`
- [ ] 0.3 記錄 FTS 現況：`fts_optimize_available = 1`、`fts_storage_version` 不存在（維持 opt-in，本次不動）
- [ ] 0.4 記錄 config 基線：`_config_version: 51`、`terminal.backend: local`、`sessions.auto_prune: false`、`security.allow_lazy_installs: true`、`toolsets: [hermes-cli]`、`mcp_servers.camofox` 存在
- [ ] 0.5 **備份 DB（`.db` + `.db-wal` + `.db-shm`，缺一不可）**：
  ```bash
  POD=$(kubectl get pod -n hermes -l app=hermes-agent -o jsonpath='{.items[0].metadata.name}')
  mkdir -p ~/backups/hermes-20261103
  kubectl cp -n hermes $POD:/opt/data/state.db      ~/backups/hermes-20261103/state.db
  kubectl cp -n hermes $POD:/opt/data/state.db-wal  ~/backups/hermes-20261103/state.db-wal
  kubectl cp -n hermes $POD:/opt/data/state.db-shm  ~/backups/hermes-20261103/state.db-shm
  ```
- [ ] 0.6 驗證備份完整性：`sqlite3 ~/backups/hermes-20261103/state.db "SELECT COUNT(*) FROM messages; PRAGMA integrity_check;"` → 應為 `18023` + `ok`
- [ ] 0.7 盤點既有備份並記錄：
  - 本機 `~/backups/hermes-20261024/`（v0.22.5 升級前快照，176MB）— 暫留，待 Phase E 驗證通過後請示使用者是否清理
  - 本機 `~/kubernetes/hermes/backups/` — 空

### Phase A — 建立分支 + Purge Workflows + 移植自訂 Commits

- [ ] A0. **取得使用者 Go-Sign**（確認 §0.5 決策 A/B/C/D/E）
- [ ] A1. `git fetch origin refs/tags/v0.22.6:refs/tags/upstream-v0.22.6 --no-tags`（✅ 已完成，commit `f0d94882e89`）
- [ ] A2. `git checkout -b my-config-v0.22.6 upstream-v0.22.6`
- [ ] A3. Purge 官方 workflows，僅保留 `ghcr-publish.yml`：
  ```bash
  find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete
  git checkout my-config-v0.22.5 -- .github/workflows/ghcr-publish.yml
  git add .github/workflows
  git commit -m "chore(ci): purge official CI workflows; retain only ghcr-publish.yml"
  ```
- [ ] A4. Cherry-pick 基礎自訂 commits：`525149ec3e`（`entrypoint-ssh.sh`）、`b2c1cdc689`（`docker-compose.yml`）、`fb932d5ef9`（`AGENTS.md`）、`50ae081e39`（`stage2-hook.sh`）
- [ ] A5. 移植 `4f42a128e9`（Dockerfile 自訂層）：合入上游 `tmux` 與 `--extra fal --extra documents`、移除已退役的 `agent-browser` hunk，確認 `git diff upstream-v0.22.6 HEAD -- Dockerfile | grep -c '^@@'` = **7**
- [ ] A6. Cherry-pick `aa6697402b`（`.env.example`）與 20 個 `docs/` 歷史文檔 commits（含本工作表）
- [ ] A7. **tracked-but-ignored 遺失偵測**：
  ```bash
  comm -23 <(git ls-tree -r my-config-v0.22.5 --name-only | sort -u) \
           <(git ls-tree -r my-config-v0.22.6 --name-only | sort -u) \
    | git check-ignore --stdin --no-index 2>/dev/null
  ```
  期望：**空輸出**
- [ ] A8. 確認 `git log --oneline upstream-v0.22.6..HEAD` 完全線性（無 merge commit）

### Phase B — 本地輕量驗證（嚴禁跑重型測試或本機 docker build）

- [ ] B1. `git status` 乾淨
- [ ] B2. Dockerfile 7 個自訂標記全數存在且含上游新加項：`openssh-server` `rsync` `locales` `tmux` `en_US.UTF-8` `zh_TW.UTF-8` `ssh-keygen -A` `-s /bin/bash` `edge-tts` `firecrawl` `fal` `documents` `uv-cache` `/etc/hermes/chromium-executable-path`（且**不含** `agent-browser`）
- [ ] B3. `.github/workflows/` 僅有 `ghcr-publish.yml`
- [ ] B4. 驗證關鍵檔案完整性：`docker/entrypoint-ssh.sh`、`docker/stage2-hook.sh`、`docker/entrypoint-dispatch.sh`、`docker/profile-hermes-path.sh`、`docker-compose.yml`、`AGENTS.md`、`ghcr-publish.yml`
- [ ] B5. 確認 `ghcr-publish.yml` dispatch input 為 **`tag_name`**
- [ ] B6. 確認 `hermes_state_common.py` 的 `SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3`
- [ ] B7. 確認 `hermes_cli/config_migrations.py` 最高版本為 **52**
- [ ] B8. 確認 `.env` 仍在 working tree 且未被 git track

### Phase C — 推送 Fork + 觸發 GHCR Build

- [ ] C1. 推送分支至個人 fork（**注意 remote 是 `kuniakil`，絕不可推 `origin`**）：
  ```bash
  git push -u kuniakil my-config-v0.22.6
  ```
- [ ] C2. 手動觸發 workflow（由分支建置，input 為 `tag_name`）：
  ```bash
  gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent \
    --ref my-config-v0.22.6 -f tag_name=v0.22.6 -f platforms=all
  ```
- [ ] C3. 驗證觸發的 run：`event=workflow_dispatch`、`headBranch=my-config-v0.22.6`、`headSha` = **我方 commit**（絕非 `f0d94882e89`）
  - ⚠️ 若遇 `HTTP 422 "Actions has been disabled for this repository"`，立即停止並請使用者至 `https://github.com/kuniakil/hermes-agent/actions` 點擊橫幅重新啟用
- [ ] C4. **派背景子代理監控 `gh run watch <run_id> --repo kuniakil/hermes-agent`**（預計 10–15 分鐘，主迴圈保持可回應）
- [ ] C5. 驗證 multi-arch image tags 產出：`ghcr.io/kuniakil/hermes-agent:v0.22.6` 與 `latest`

### Phase D — K3s 部署 + 全方位驗證

- [ ] D1. 更新 `~/kubernetes/hermes/overlays/n100/kustomization.yaml`：`newTag: "v0.22.5"` → `"v0.22.6"`
- [ ] D2. 執行 `kubectl apply -k ~/kubernetes/hermes/overlays/n100`，並**派背景子代理等待 `kubectl rollout status deployment/hermes-agent -n hermes`**
- [ ] D3. 冒煙測試（對照 v0.22.5 基線）：
  - Python `3.14.9` + `ruamel.yaml.clib` C 加速可用 + `openai 2.54.0`
  - Node.js `v26.12.1` + npm `12.0.2`
  - Debian base = `trixie`
  - 3 種 locale（`C.utf8` / `en_US.utf8` / `zh_TW.utf8`）
  - `sshd` + `rsync` + `tini` + `tmux` + `ffmpeg` + `/etc/profile.d/hermes.sh`
  - Chromium binary 存在且可執行（`cat /etc/hermes/chromium-executable-path` → `--version`）
  - Python extras（`edge-tts` / `firecrawl` / `dingtalk_stream` / `lark_oapi` / `exa_py` / `fal_client` / `pypdf` / `docx`）
  - Telegram connected、**0 ERROR**
- [ ] D4. **版本確認**：`hermes --version` 顯示 `v0.22.6` 且 `upstream <我方 commit sha>`
- [ ] D5. **DB Schema 檢查**：`state.db` `schema_version` 仍為 **32**；`PRAGMA integrity_check` = `ok`
- [ ] D6. **資料完整性**：`sessions` ≥ 132、`messages` ≥ 18,023（零損失）
- [ ] D7. **Config v52 遷移驗證**：`/opt/data/config.yaml` 的 `_config_version` 升為 **52**；確認 `mcp_servers.camofox` 原封不動、`browser` toolset 未被關閉、無 `_left_core_used` 誤標
- [ ] D8. **Left-Core 開機驗證**：確認 gateway 開機 log **沒有**自動下載/安裝 `camofox` 或 `github-copilot` plugin；刪 Pod 強制重啟一次確認 `RESTARTS = 0`
- [ ] D9. **Delegation 與 Camofox MCP 驗證**：確認 `plugins/delegation/default` 正常載入，且 `mcp_servers.camofox` 探針連線正常
- [ ] D10. 真實 Telegram 訊息往返驗證

### Phase E — 收尾與文件歸檔

- [ ] E1. 更新本工作表所有 checkbox 與實測數據（Run ID、image digest、驗證結果）
- [ ] E2. Commit 並推送 `~/kubernetes/hermes/overlays/n100/kustomization.yaml`
- [ ] E3. 彙整證據向使用者報告，並**詢問是否刪除舊備份 `~/backups/hermes-20261024/`（176MB）**（收到明確同意才刪）

---

## 5. 風險總結表

| 風險項目 | 等級 | 緩解與驗證措施 |
|---|---|---|
| **`agent-browser` 在 PM 中被移除導致舊 Dockerfile hunk #3 失敗**（R1） | 🔴 高（不改必敗） | 已於事前 diff 抓出！Phase A5 直接移除 hunk #3，改驗 `/etc/hermes/chromium-executable-path` |
| **Config v51→v52 與 Left-Core `camofox` / `github-copilot` 遷移**（R2） | 🟡 中 | 已對線上 `/opt/data` 實測證明 `camofox_in_use() = False`、`copilot_in_use() = False`；Phase D7/D8 部署後複核 |
| **Dockerfile apt 與 `pm.build_env` 與上游新增項衝突**（R3） | 🟡 中 | Phase A5 合併上游新增的 `tmux` 與 `--extra fal --extra documents` |
| **776 PR 大收斂窗口 + `openai` SDK `2.24.0 → 2.54.0`**（R4） | 🟡 中 | DB `SCHEMA_VERSION = 32` 未變，萬一異常可秒級無損退回 `v0.22.5` image；Phase D3/D9/D10 完整驗證 |
| **DB Schema / FTS 不可逆遷移** | 🟢 **無** | `SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3` 零變化 |
| **npm 漏洞** | 🟢 無（既有決策） | 3 個官方 issue 仍為 OPEN；容器 runtime 暴露面 = 0，維持「不修」 |

---

## 6. npm 漏洞決策複查（2026-11-03）

| 檢查項目 | 2026-11-03 實測結果 |
|---|---|
| ① 觸發條件 Issue 狀態 | `#133435` **OPEN**、`#132924` **OPEN**、`#79021` **OPEN** → 條件未成立，**維持「不修」** |
| ② 上游 `package.json` `overrides` 變化 | 上游自行小幅升版 `mermaid 11.16.1→11.17.2`、`katex 0.18.4→0.19.0`、`nanoid@^6 6.0.0→6.0.2`；其餘維持不變 |
| ③ 實際 K3s runtime 暴露面 | Photon sidecar 未啟用、Electron desktop 不部署 → **暴露面 = 0** |

---

## 7. Go-Sign 確認區

- [ ] §0.5 決策 **A**：目標版本 = **`v0.22.6`**
- [ ] §0.5 決策 **B**：Dockerfile **移除 `agent-browser` hunk #3**，並合入上游 `tmux` 與 `fal`/`documents` extras
- [ ] §0.5 決策 **C**：npm 漏洞 = **維持不修**
- [ ] §0.5 決策 **D**：FTS layout = **維持不動**
- [ ] §0.5 決策 **E**：先建 `20261103` 新備份，待驗證完成後再請示清理 `20261024` 舊備份
- [ ] 使用者回覆「**Go**」後啟動 Phase 0 → A → B → C → D → E
