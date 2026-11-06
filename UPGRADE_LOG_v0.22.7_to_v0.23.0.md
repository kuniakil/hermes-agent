# Hermes Agent 升級紀錄：v0.22.7 → v0.23.0

- **升級日期**：2026-11-06
- **目標版本**：`v0.23.0`（官方 commit `2bd378ed1b8d6bf2192cb26e0a55ff3091e6bd19`，2026-11-05 發佈，*"The Hearth Release"*）
- **升級前版本**：`v0.22.7`（基於官方 `v0.22.7` = `b200f5bc60e3`）
- **新分支**：`my-config-v0.23.0`（基底 = **`upstream-v0.23.0`**，非本地 `v0.23.0` tag）
- **Image source SHA**：`3d6cda5e0d84799eb0d30f02661086db4d457f3b`（= `hermes --version` 顯示的 `upstream 3d6cda5e`）
- **GH Actions Run**：[`42129150541`](https://github.com/kuniakil/hermes-agent/actions/runs/42129150541)（prepare / build-and-push amd64 / build-and-push arm64 / merge 全 success，總耗時 11m 55s）
- **發布映像**：`ghcr.io/kuniakil/hermes-agent:v0.23.0`（與 `latest`），雙架構 multi-arch index
  - index digest：`sha256:3aeff98bdf226fdd65bd2d6f03783295a9737a5fa619fefc7f3f426cd365f2ee`
  - `linux/amd64` → `sha256:7f27da89288c42a1b1bb7e3608718b116cec566a14a81f538b89c47a4d2dcab7`
  - `linux/arm64` → `sha256:bd8ecb549804c80166ca0748ddf9296f3a99a5ea3655ff399da137c373c3b6a8`
- **部署環境**：K3s n100，pod `hermes-agent-f9496b576-wcxg8`（舊 pod `hermes-agent-58b98d987d-5nhh7` 已移除）
- **schema_version**：32 → **32**（**未變，DB 零遷移**）
- **config_version**：52 → **52**（**未變，Config 零遷移**）
- **備份**：`~/backups/hermes-20261106/`（176MB，integrity ok，messages 18,044）
- **工作表**：`docs/worksheet-upgrade-hermes-v0.23.0-20261106.md`

---

## 1. 一句話總結

> 這是本系列**至今最大的功能性版本**（808 commits / 1,223 檔 / +42,358 / −11,117），官方稱為 *"The Hearth Release"*，把 v0.22.1–v0.22.7 的七個 patch 完整收斂。
>
> 對我們而言是**架構級升級、資料面零風險**的一次：
> 1. **三重 schema 全部零變化**：`SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3`、`_config_version = 52` 皆未動，`hermes_state_*.py`、`config_migrations.py`、`left_core_migration.py` 對上游 diff = **0 行** → **完全可逆**；
> 2. **自訂層 100% 零衝突**：上游本窗口對 `Dockerfile` 只動 2 個 hunk 且**全是註解**，我們 7 個自訂 hunk 原樣移植，`git merge-tree` 實測**程式碼 / Dockerfile / 設定 0 content conflict**；
> 3. **兩個真正的架構變更都實測通過**：單 gateway 所有權（B1）與 s6 監督樹重構（B2）—— 後者還是上游的**權限強化安全修正**（per-profile gateway slot 從 root scandir 搬到 hermes 擁有的 `/run/hermes-service/`）；
> 4. **線上全面檢查全綠**：Telegram connected、6 個 API 端點全通、真實 agent 回合成功、DB 零損失、**排除我方探測後 0 ERROR / 0 CRITICAL**。

---

## 2. 官方 Release Notes 稽核

### 2.1 官方量測

| 指標 | 值 |
|---|---|
| non-merge commits（v0.22.7 → v0.23.0） | **808** |
| changed files | **1,223** |
| 行數 | **+42,358 / −11,117** |
| 核心 runtime（`gateway/` `agent/` `tools/` `hermes_cli/`） | 170 檔 / +6,606 / −1,223 |

> 官方 Release Notes 標題下的「~10,080 commits / ~1,950 merged PRs / ~8,720 files / +725,200 / −201,400 / ~850 issues closed / 666 contributors」是**自 v0.22.0 起**的累計（含 v0.22.1–v0.22.7）。我們的實際升級落差是 v0.22.7 → v0.23.0 = 808 commits / 1,223 檔。

### 2.2 官方重點功能盤點（依對我們的相關性分級）

**直接相關：**

- **One gateway owns every conversation**（#106742, #140334）— CLI / TUI / Desktop / API / ACP / bots / cron 全部 attach 到同一個 gateway，一場對話只有一條佇列、一份歷史。本輪修完 v0.22.0 以來殘留的 slash command、`/retry`、`/refine`、`/review`、clarify card、reasoning 顯示、usage、ACP session 與 config 變更傳不到 resumed session 等問題（#139149, #139577, #139884, #140249, #140595, #141916, #144005, #138719）。
- **所有訊息平台 adapter 變成 bundled 外掛**（#139843, #140168）— Signal / Weixin / BlueBubbles / QQ / Yuanbao / WhatsApp Cloud 等移出 core；Telegram 亦同。
- **省 token / 省快取**：cron job 共用 prompt cache key、one-shot 每次少 1,570 prompt tokens、4 個 tool schema 少 319 tokens、gateway 在 closed session 後釋放記憶體。
- **CLI / TUI 終端機內嵌圖片**（#147293, #148874）、**`/rewind`** 回捲對話（#144937, #148880）。
- **built-in skills 58 → 44**（Word / PowerPoint / Excel 合併為單一 `microsoft-office`）；`hermes curator lock` 可鎖定手動整理過的 skill。
- **外掛自我更新**（`hermes plugins update` + opt-in Auto-update）、catalog 從 ~600 暴增到 **>1,050** 筆。
- **左核心遷移**：Camofox、`mcp serve`→`mcp-serve`、Singularity、agent-importers、GitHub Copilot 移出 core 變成一鍵安裝的外掛。

**與我們環境無關（快速篩除）：** Webapp、Desktop 全系列（Electron 40→44）、Bot Mode Group Chats、付費 MCP 工具計價、`advanced-delegation` 外掛、Meshy / ElevenLabs / X Chat / REA / bubblewrap、密碼管理器 + keychain、`hermes cron cancel`（我們無 job）、Kanban worker、`/usage` 計費窗、`agent.daybreak`、Microsoft Store / Nix / 安裝器、`--cpu-profile`。

### 2.3 官方 Upgrade notes 5 條 — 逐條對我們的環境判定

| 官方條目 | 我們的環境 | 判定 |
|---|---|---|
| **舊的內建 browser 工具被移除**（只剩 `browser_exec`） | `toolsets.py` 在兩個 tag **都只有 `browser_exec`**；我們的 `browser` toolset 早已是 `browser_exec` | ✅ **本次無影響**（v0.22.6 已完成） |
| **Desktop 需要 macOS 13+ / 64-bit Windows**（Electron 40→44） | 我們**不部署 Desktop**（K3s 僅 server 容器） | ✅ N/A |
| **`hermes mcp serve` → `hermes mcp-serve`**（移入外掛） | 我們**不使用** Hermes 作為 MCP server；`~/kubernetes/hermes/` 內 grep `mcp serve` = 0 筆 | ✅ N/A |
| **Word/PPT/Excel 合併為 `microsoft-office`** | 上游內建 skills 兩個 tag **完全相同（44 = 44）**；但 PVC 上 `/opt/data/skills` 有 181 個 `SKILL.md` 含舊版殘留副本 | ⚠️ **低風險、非本次引入**（v0.22.7 已是相同現況）→ 決策 F：本次不動，另開議題 |
| **Webapp 預設關閉**（`webapp.enabled`） | 我們 config 無 `webapp` 鍵 → 預設關閉 | ✅ N/A |

### 2.4 機器可讀真相對照

| 項目 | v0.22.7 | v0.23.0 | 判定 |
|---|---|---|---|
| Base image（兩個 `FROM`） | `debian:trixie-20261020@sha256:4c252754…` | **完全相同** | 🟢 零變動 |
| `requires-python` | `>=3.11,<3.15` | `>=3.11,<3.15` | 🟢 |
| `nemo-relay` | `>=0.11,<0.12` | `>=0.11,<0.12` | 🟢 |
| Python build pins | `pypdf 6.21.2` / `pyasn1 0.6.4` / `setuptools 83.0.0` | `pypdf 6.21.4` / `pyasn1 0.6.5` / `setuptools 84.1.0`（GHSA-xmj3-9gf7-h52w） | 🟡 隨 build 生效 |
| `zod`（resolved） | 4.6.5 | **4.6.7** | 🟢 上游修補 |
| `undici`（resolved / overrides） | 6.29.0 / 7.30.0 | **6.29.1 / 7.30.1** | 🟢 上游修補 |
| `fast-uri` | 3.1.8 | **3.1.9** | 🟢 上游修補 |
| Electron | 40 | **44** | ⚪ Desktop only |
| 新增 `HERMES_*` 環境變數 | — | `HERMES_FORK_SERVER_ONLY` / `HERMES_TEST_FORKSERVER`（**皆為測試用**） | 🟢 N/A |
| 新增 / 變更 config 預設鍵 | — | 新增 `aux.group_router`、`display.inline_images`、`delegation.prefix_stagger_seconds`、`bot_loop_guard.max_hops`；**移除** `aux.skills_hub` 預設值 | 🟢 選擇性，`_config_version` 不變 |

---

## 3. 關鍵技術調整與解決

### 3.1 自訂層 7 個 Hunk：零衝突原樣移植

上游本窗口對 `Dockerfile` 的改動**只有 2 個 hunk、11 行，且全部是 `#` 註解**（`s6-rc.d` 說明與 `/run/hermes-service/` 說明的改寫）——過濾掉註解行後 diff 為空 → **零功能性變更**。我們的 7 個自訂 hunk 位於上游 Dockerfile 第 78 / 175 / 302 / 380 / 397 / 490 / 515 行附近，**與上游零位置重疊**：

| # | 位置 | 內容 |
|---|---|---|
| 1 | `runtime_base` apt | `openssh-server` `rsync` `locales` + `mkdir -p /var/run/sshd` + `ssh-keygen -A` + `C.UTF-8` / `en_US.UTF-8` / `zh_TW.UTF-8` locale 生成與 `/etc/default/locale`、`/etc/profile`、`.bashrc` 寫入 |
| 2 | `useradd` | `RUN useradd -u 10000 -m -d /opt/data -s /bin/bash hermes` |
| 3 | `pm.build_env` | 上游 extras 後追加 `--extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa` |
| 4 | `runtime` `/tmp/.npm-cache` | `mkdir -p /tmp/.npm-cache && chmod 1777` |
| 5 | `runtime` `/root/.npm` | `mkdir -p /root/.npm /root/.cache && chown -R 10000:10000` |
| 6 | `runtime` `ENV HOME` | `ENV HOME=/opt/data` |
| 7 | `runtime` entrypoint shim | `COPY --chmod=0755 docker/entrypoint-ssh.sh /opt/hermes/docker/entrypoint-ssh.sh` |

hunk 位置因上游 +2 行而平移（`@@ -490→492`、`@@ -515→517`），其餘不變。

**建置日誌實錘**（非僅 diff 推論）：build log 內 13 個標記直接命中（`openssh-server` / `rsync` / `ssh-keygen -A` / `zh_TW.UTF-8` / `en_US.UTF-8` / `useradd -u 10000` / `--extra edge-tts` / `firecrawl` / `dingtalk` / `feishu` / `exa` / `/tmp/.npm-cache` / `entrypoint-ssh.sh`）；第 14 個 `ENV HOME=/opt/data` 因 Dockerfile 的 `ENV` 指令不會被 echo 成 build step，改以 `docker buildx imagetools inspect --format '{{json .Image}}'` 直接驗證 published image config → **amd64 與 arm64 的 `Env` 清單皆含 `HOME=/opt/data`** ✅

**install stamp** 確認為我們的 commit：`[write_install_stamp] wrote install-stamp.json -> 3d6cda5e0d84 (my-config-v0.23.0)`，stamp 的 `commit` 欄位與 build provenance 的 `vcs:revision` / `github_workflow_sha` 全部一致（`scripts/write_install_stamp.py` 的 CLI flags 在兩個 tag 逐位元組相同，workflow 不需修改）。

### 3.2 CI Workflow Purge

上游 **58 個** workflow → 保留 **1 個**（`ghcr-publish.yml`，自 `my-config-v0.22.7` 檢入，dispatch input 為 **`tag_name`**）。commit `2a529f1e39`（59 files changed, **+154 / −13,404**）。

`git merge-tree` 實測的 12 個 modify/delete 衝突全部落在 `.github/workflows/*` → **依 Purge 規則全數刪除，零人工解衝成本**。程式碼 / Dockerfile / 設定 **0 content conflict**。

### 3.3 B2 — s6 監督樹重構（上游 commit `c08c485305`）

> *fix(docker): supervise profile gateways outside the root s6 scandir*

這不是單純的重構，而是**權限強化**。上游原本的 `02-reconcile-profiles` 會 `chown /run/service` 給 hermes，`015-supervise-perms` 會把靜態服務的 `supervise/` 與 `event/` 樹 chown 給 hermes —— 等於**讓非特權 hermes 使用者取得對 root supervisor 所執行內容的控制權**。

修正後的模型：

| 面向 | v0.22.7 | v0.23.0 |
|---|---|---|
| per-profile gateway slot 路徑 | `/run/service/`（root scandir） | **`/run/hermes-service/`**（nested s6-svscan，以 hermes 身分執行） |
| 靜態服務 `supervise/` 樹 | chown 給 hermes | **維持 root-owned**，只給 group hermes 對 status/lock 的讀取與 control FIFO 的寫入 |
| `S6_DYNAMIC_SCANDIR` | — | 指向 gateway scandir（`/run/hermes-service`） |
| `S6_STATIC_SCANDIR` | — | 指向 root scandir（`/run/service`） |
| `hermes doctor` | 直接探 scandir | 新增 `s6_service_up()` helper 探靜態服務 |

涉及檔案：`docker/cont-init.d/015-supervise-perms`（99 行改寫）、`docker/cont-init.d/02-reconcile-profiles`（48 行）、`docker/s6-rc.d/profile-gateways/*`（新增 longrun）、`docker/s6-rc.d/main-hermes/run`、`hermes_cli/{container_boot,doctor_platform,gateway,gateway_multiplex_s6,service_manager}.py`，加上 8 個測試檔與 6 份文件。

**我們的實測覆蓋（D8）**：pod 內行程樹已切換到新架構 — `s6-supervise profile-gateways` (pid 30)、**`s6-svscan /run/hermes-service`** (pid 185)、`s6-supervise gateway-default` (pid 199)、`s6-supervise main-hermes` (pid 33)；`s6-svstat /run/service/main-hermes` 以 hermes 使用者查詢 → `up (pid 186 pgid 186)`（**無 EACCES**）；`hermes doctor` → `s6 Supervision ✓ Host gateway: the host gateway (PID 202) serving profiles default`。

> `dashboard` slot 顯示 `down (exitcode 0)` 是**設計如此** —— `HERMES_DASHBOARD` 未設時 run script 乾淨退出、finish script 回 125 → slot 永久 down。非故障。

### 3.4 B1 — 單 gateway 所有權

上游 v0.23.0 把 v0.22.0 開始的「一個 gateway 擁有每一場對話」補完：slash command、`/retry`、`/refine`、`/review`、clarify card、reasoning 顯示、usage、ACP session 恢復正常，且 config 變更能傳到 resumed session。

**我們的實測覆蓋（D10a）**：經 gateway 的 api_server 跑真實 agent 回合 → HTTP 200、模型成功呼叫 bash 工具、DB 同步寫入 → 證明「CLI / API / bot 全部經同一 gateway」的新模型在我們的 server-only 部署上運作正常。

### 3.5 左核心遷移：Camofox 移出 core 的判定

官方註記「用了 Camofox 的家會自動裝上 `camofox` 外掛」。我們**不受影響**，理由：

- 我們的 `mcp_servers.camofox` 指向**外部 MCP server**（`http://camofox-mcp.camofox.svc.cluster.local:8080/mcp`），不是內建 Camofox 瀏覽器；
- 內建 Camofox 的設定塊 `browser.camofox` 雖存在，但 `cdp_url: ''`、無 `cloud_provider`、無 `use_gateway` → `camofox_in_use()` 回 False；
- 實測 `_left_core_used` 在 config 裡出現次數 = **0** → **沒有任何外掛被自動安裝**；
- `hermes_cli/left_core_migration.py` 對上游 diff = **0 行**。

---

## 4. 線上全面檢查結果（2026-11-06 實測）

```
版本:
Hermes Agent vv0.23.0 (2026.9.24) · upstream 3d6cda5e   ← upstream 後綴是我們的 commit
Python 3.14.9 │ OpenAI SDK 2.54.0 │ pydantic 2.14.1 │ nemo-relay 0.11.0
Node.js v26.12.1 │ npm 12.0.2 │ Debian 13 (trixie)
Config v52 → v52（不變，零遷移）

核心狀態（部署後）:
- sessions: 134 (基線 133 +1，來自 api_server 回合) ✅
- messages: 18,049 (基線 18,044 +5) ✅
- integrity_check: ok ✅
- messages_fts: 18,049 = messages 18,049 ✅ FTS trigger 全部正常
- session_admissions: 12 │ worker_executions: 0 │ worker_receipts: 0 ✅
- Config: v52 ✅
- _left_core_used: 0 ✅（無外掛自動安裝）
- cron/jobs: 無 job（僅 dispatch_held.json 時間戳）✅
- Skills: 95 enabled / 0 disabled（21 hub-installed + 1 builtin + 73 local）✅
- 磁碟: 1.8T / 592G used (35%) ✅
- 記憶體: 31G total / 16G available ✅

部署:
- pod: hermes-agent-f9496b576-wcxg8（舊 pod hermes-agent-58b98d987d-5nhh7 已移除）
- image: ghcr.io/kuniakil/hermes-agent:v0.23.0
        digest sha256:3aeff98bdf226fdd65bd2d6f03783295a9737a5fa619fefc7f3f426cd365f2ee
- RESTARTS: 0
- deployment: updated=1/1 ready=1 avail=1（Available=True / Progressing=True）
- 3 種 locale（C.utf8 / en_US.utf8 / zh_TW.utf8）全在
- sshd / rsync / tini / tmux / ffmpeg 全在
- Chromium: /opt/hermes/tools/chromium-1208/chrome-linux64/chrome

Gateway 開機（2026-11-06 07:41:01 起）:
- Model context warmed: MiniMax-M3 → 1000000 tokens (detected)
- ✓ telegram connected（Telegram polling confirmed healthy）
- ✓ api_server connected、Gateway running with 2 platform(s)
- Channel directory built: 1 target(s)
- kanban dispatcher: embedded in gateway、Cron scheduler will tick 1 profile(s): ['default']
- 舊 pod 關閉為 graceful：signal=SIGTERM under s6-supervise
- ERROR: 2（**全部是我方 /v1/skills 探測**，見 §6）→ 排除後 ERROR 0、CRITICAL 0

Camofox MCP:
- DNS → 10.43.250.235；未帶 token GET → HTTP 401（端點存活）
- 帶 Authorization 的 MCP initialize JSON-RPC → HTTP 200
  serverInfo {"name":"camofox-mcp","version":"1.16.0"}，capabilities: tools + prompts ✅
- Hermes config 的 Bearer token 與 camofox/camofox-secret:CAMOFOX_HTTP_API_KEY 逐字相符（40 chars）

額外端到端驗證（主代理執行，非使用者回報）:
- POST http://127.0.0.1:8642/v1/chat/completions（Authorization: Bearer $API_SERVER_KEY）
  → HTTP 200，耗時 6.3s，模型成功呼叫 bash 工具並回傳 "hermes-upgrade-smoke-v0230" ✅
- DB 同步寫入（sessions 133→134、messages 18,044→18,049）、integrity ok
- API 端點：/health /v1/health /v1/models /v1/capabilities /v1/toolsets /api/sessions 皆 200

真實 Telegram 訊息往返（使用者實測，2026-11-06 07:58 台北時間）:
- 使用者在 Telegram DM（chat 830338761）送出「系統已經升級，做一下檢查」
- inbound: platform=telegram user=Michael Lee chat=830338761 ✅
- Rehydrated persisted /model override: model=MiniMax-M3 provider=minimax
  → B1 單 gateway 架構下，既有 session 與 model 偏好完整還原 ✅
- response ready: time=66.1s api_calls=4 response=2404 chars ✅
- outbound: [Telegram] Sending response (2404 chars) to 830338761（送出後無任何錯誤）✅
- DB: messages 18,052→18,059（+7）、messages_fts = 18,059 = messages、integrity ok ✅
- sessions = 134 未變（正常）—— 續接既有 session 20260708_133022_65a00a95，非新建
  → 這正是 B1「一個 gateway 擁有每一場對話」的預期行為 ✅
- 開機後 ERROR = 0（排除我方 /v1/skills 探測）✅
```

---

## 5. 備份與資產處置

- **新備份**：`~/backups/hermes-20261106/`
  - `state.db`（184,508,416 B）、`state.db-wal`（0 B）、`state.db-shm`（32,768 B）、`config.yaml`（13,234 B）
  - 驗證：`messages = 18,044`、`sessions = 133`、`PRAGMA integrity_check = ok`
  - 製備方式：Pod 內 `PRAGMA wal_checkpoint(TRUNCATE)`（實測 `(0, 0, 0)`）後以 **tar streaming** 傳回（`kubectl cp` 傳 176MB 時 websocket 中斷 `close 1006` —— 見記憶 `kubectl-cp-large-db-backup-tar-streaming`）
- **舊備份**：`~/backups/hermes-20261104/`（176MB，v0.22.7 升級快照）— ✅ **已於 2026-11-06 依使用者授權刪除**
  - 刪除前已複驗 `hermes-20261106` 完整性：`PRAGMA integrity_check = ok`、`messages = 18,044`、`sessions = 133` → 通過後才執行 `rm -rf`（回收 176MB）
  - 現存備份：`~/backups/hermes-20261106/`（176MB，保留）、`~/backups/immich-20261016/`（與本專案無關）
- **K8s Repo**：`~/kubernetes/hermes/overlays/n100/kustomization.yaml` 已提交並推送 `origin/main`（commit `61491d0`，`newTag: "v0.22.7"` → `"v0.23.0"`）
- **Hermes Repo**：分支 `my-config-v0.23.0`，自訂 commits 合計 **40**（1 CI purge + 6 core + 32 docs + 1 worksheet），**0 個 merge commit，歷史完全線性**

---

## 6. `GET /v1/skills` 恆回 HTTP 500 — 上游既有缺陷，**不修**

部署後實測 `GET /v1/skills` → **HTTP 500**：

```
TypeError: find_all_skills() got an unexpected keyword argument 'include_editorial'
```

### 6.1 根因（上游原始碼）

| 檔案 | 行 | 內容 |
|---|---|---|
| `gateway/platforms/api_server.py` | 2388 | `find_all_skills(skip_disabled=False, include_editorial=True)` ← 呼叫端多傳參數 |
| `tools/skills_tool.py` | 277 | `def find_all_skills(*, skip_disabled: bool = False) -> list[dict[str, Any]]:` ← 簽章無此參數 |

### 6.2 三項「既有缺陷」證據

1. **逐 tag 逐位元組比對**：`upstream-v0.22.7` 與 `upstream-v0.23.0` 的上述兩處**完全相同** → 該 500 在升級前的 v0.22.7 上就已存在，**不是 v0.23.0 的 regression**。
2. **上游 `main` 仍存在**：缺陷尚未修復。
3. **上游 issue 群全部 OPEN**（2026-11-06 複查）：

| Issue | 標題 | 狀態 | 建立 |
|---|---|---|---|
| [#108967](https://github.com/NousResearch/hermes-agent/issues/108967) | [Bug]: GET /v1/skills always returns HTTP 500 | **OPEN** | 2026-09-12 |
| [#120831](https://github.com/NousResearch/hermes-agent/issues/120831) | TypeError: `_find_all_skills()` … `include_editorial` | **OPEN** | 2026-09-24 |
| [#124853](https://github.com/NousResearch/hermes-agent/issues/124853) | GET /v1/skills always returns 500 on v0.21.5 | **OPEN** | 2026-09-27 |
| [#132317](https://github.com/NousResearch/hermes-agent/issues/132317) | GET /v1/skills returns 500（duplicate） | **OPEN** | 2026-10-03 |
| [#142575](https://github.com/NousResearch/hermes-agent/issues/142575) | stale `include_editorial` kwarg after Collective Wisdom revert | **OPEN** | 2026-10-21 |
| [#148508](https://github.com/NousResearch/hermes-agent/issues/148508) | still returns HTTP 500 in latest Docker image (v0.22.6) | **OPEN** | 2026-11-03 |

> 最早回報於 **2026-09-12（v0.21.x）**，橫跨 4 個 minor 版本未修。

### 6.3 為什麼不修

| 理由 | 說明 |
|---|---|
| 非本次引入 | v0.22.7 即已存在 → 不屬本次升級範圍，修它只會讓分支與上游產生無謂分歧 |
| 無第一方消費路徑 | 我們是 server-only 部署，**沒有任何第一方元件呼叫 `/v1/skills`**（Desktop 不部署、webapp 未啟用、CLI 走 `hermes skills list` 而非 HTTP） |
| 核心 skill 載入完全正常 | 實測 `find_all_skills()` → **96 筆正常**；CLI `hermes skills list` → **95 enabled / 0 disabled**。受影響的只有那 1 個 HTTP 端點 |
| 未修前動它必然衝突 | 下次 rebase / cherry-pick 上游時會衝突，且要替上游承擔 correctness 責任 |

### 6.4 實際影響

- **零功能影響**（Telegram bot 走 gateway 內部路徑，不經此端點）。
- **僅 2 筆 ERROR log**（07:45:13 / 07:45:25），且**全部是我方自己的探測**。排除後 = **ERROR 0 / CRITICAL 0**。
- 端點需 `API_SERVER_KEY` 認證，我們的 api_server 未對外公開（僅 Pod 內 `127.0.0.1:8642`）。

---

## 7. 回滾方案

三重 schema 零變更（`SCHEMA_VERSION = 32` / `FTS_STORAGE_VERSION = 3` / `_config_version = 52`），且 DB 掛於 hostPath `/data/services/hermes/data` 持續保存，因此回滾**不需要任何資料遷移**：

```bash
# 把 newTag 改回 v0.22.7 並重新套用即可
# ~/kubernetes/hermes/overlays/n100/kustomization.yaml
kubectl apply -k ~/kubernetes/hermes/overlays/n100
```

預期時間：image pull ~1m43s + 開機 < 1 分鐘。

> 補充：若需以資料本身回退（例如僅想把 session 狀態還原到升級前），可直接從 `~/backups/hermes-20261106/state.db` 還原 —— 但在 schema 零變更的前提下，通常不需要。

---

## 8. Image stamp 與分支 HEAD 的差異（有意保留）

| 項目 | SHA | 說明 |
|---|---|---|
| 已部署 image 的 build stamp | `3d6cda5e0d` | 部署當下的分支 HEAD（GHCR run `42129150541` 的 `headSha`） |
| 分支現況 HEAD（`my-config-v0.23.0`） | `ae99ed9748` | 差 3 個 commit（全為 docs） |

差異內容**全部為文件**：`docs/worksheet-upgrade-hermes-v0.23.0-20261106.md` 的執行結果回填與本 `UPGRADE_LOG_v0.22.7_to_v0.23.0.md`。**runtime 程式碼零差異** —— 重新建置產出的 image 與現行 image 的執行行為完全相同。

**決策：不重新建置、不重新部署。** 理由：

1. 現行部署已通過完整線上驗證（D1–D10a 全綠、排除我方探測後 0 ERROR、RESTARTS 0）；
2. 重新建置會覆寫同一個 `v0.23.0` tag（既定行為），導致新 digest、需重新 pull + rollout + 重新驗證，**純粹為了讓 stamp 對齊一個文件 commit 而承擔風險**；
3. D11 的 24h 穩定性觀察窗口不應被無謂重置。

若日後因故需要讓 image stamp 與分支 HEAD 完全對齊，重跑同一條指令即可：

```bash
gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent \
  --ref my-config-v0.23.0 -f tag_name=v0.23.0 -f platforms=all
```

---

## 9. npm 漏洞決策複查（2026-11-06 事後稽核）

> 結論：**「不修」決策對 v0.23.0 仍然正確**，且**上游的修補已隨本版自動帶入**。

### 9.1 本地實測（`npm audit --package-lock-only`，v0.23.0 lockfile）

```
vulns: { info: 0, low: 0, moderate: 21, high: 2, critical: 0, total: 23 }
  follow-redirects  high  1.16.0 - 1.16.1
  joi              high  18.0.0 - 18.3.0
```

### 9.2 與 v0.22.7 的對照

| 項目 | v0.22.7 | v0.23.0 | 變化 |
|---|---|---|---|
| `undici@^6` override | 6.29.0 | **6.29.1** | ✅ 上游修補 |
| `undici@^7` override | 7.30.0 | **7.30.1** | ✅ 上游修補 |
| `zod`（resolved） | 4.6.5 | **4.6.7** | ✅ 上游修補 |
| `fast-uri` | 3.1.8 | **3.1.9** | ✅ 上游修補 |

這正是上一版（v0.22.7）記錄的「上游 commit `e3085ec023` 修復 undici」隨本版正式進入 tag 的結果 —— **我們的 lockfile 與 package.json 對官方逐位元組相同，因此自動取得，零本地動作**。

修補後殘餘的 2 個 high（`follow-redirects 1.16.0-1.16.1`、`joi 18.0.0-18.3.0`）上游尚未處理，與 v0.22.7 的殘餘集合相同。

### 9.3 三個「不能本地修」的硬性理由（仍然成立）

1. **修不持久** —— `hermes update` / nightly 走 `_run_npm_install_deterministic` → `npm ci` 從 committed lockfile 重裝，本地 `npm audit fix` 的改動會被丟棄。上游 `hermes_cli/doctor_tools.py:_audit_one` 的 docstring 即載明此點，doctor 刻意不提供本地 mutating 修復指令。
2. **手動修也會失敗** —— `.npmrc` 的 `min-release-age=14` 只允許安裝 14 天前發布的版本。
3. **上游 overrides 把版本釘在脆弱上限** —— `npm audit fix --force` 永遠報 `outside the stated dependency range`，**不會自癒**。

### 9.4 實際暴露面（容器 runtime）

- 我們**不部署 Desktop**（Electron 不在 image 內）、**不啟用 Photon sidecar**、**不啟用 Webapp** → 暴露面維持 **0**。
- `web` / `ui-tui` workspace 沒有 node_modules，容器內 `hermes doctor` 報的 npm 數字**不可信**；真實數字必須用 `npm audit --package-lock-only`（此結論自 v0.22.0 即已確立）。

### 9.5 觸發條件 issue 狀態

`#133435` **OPEN**、`#132924` **OPEN**、`#79021` **OPEN** → 條件未成立，**維持「不修」**。

---

## 10. 尚待完成

| # | 項目 | 狀態 |
|---|---|---|
| **D10b** | **真實 Telegram 訊息往返驗證** | ✅ **使用者實測通過**（2026-11-06 07:58 台北時間，詳見 §4） |
| **D11** | **部署後 24h 觀察**：ERROR/CRITICAL = 0、`RESTARTS = 0`、記憶體趨勢平穩 | ⏳ 觀察中（基線已記錄：RESTARTS 0、400Mi、0 ERROR；到期 2026-11-06 23:39Z） |
| **E4** | 是否刪除舊備份 `~/backups/hermes-20261104/` | ✅ **已完成**（使用者授權後刪除，回收 176MB） |
