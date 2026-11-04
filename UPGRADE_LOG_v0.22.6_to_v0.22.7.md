# Hermes Agent 升級紀錄：v0.22.6 → v0.22.7

- **升級日期**：2026-11-04
- **目標版本**：`v0.22.7`（官方 commit `b200f5bc60e31588ba2cb60e288029c4a54ba5fa`，2026-11-03 發佈）
- **升級前版本**：`v0.22.6`（基於官方 `v0.22.6` = `f0d94882e89`）
- **新分支**：`my-config-v0.22.7`
- **Image source SHA**：`caa90cb95e83dd28ac9bb7da87419b8f9e8652e0`（= `hermes --version` 顯示的 `upstream caa90cb9`）
- **GH Actions Run**：[`41738542075`](https://github.com/kuniakil/hermes-agent/actions/runs/41738542075)（prepare / build-and-push amd64 / build-and-push arm64 / merge 全 success，總耗時 10m 51s）
- **發布映像**：`ghcr.io/kuniakil/hermes-agent:v0.22.7`（與 `latest`），雙架構 multi-arch index
- **部署環境**：K3s n100，pod `hermes-agent-58b98d987d-5nhh7`
- **schema_version**：32 → **32**（**未變，DB 零遷移**）
- **config_version**：52 → **52**（**未變，Config 零遷移**）
- **備份**：`~/backups/hermes-20261104/`（176MB，integrity ok，messages 18,031；舊備份 `hermes-20261103` 已於 2026-11-04 依使用者授權刪除）

---

## 1. 一句話總結

> 這是收斂了 **174 個 PR** 的輕量常規 Patch 窗口（上次 v0.22.5 → v0.22.6 為 776 PR / 4,316 檔，本次 174 PR / 554 檔）。官方將完整 curated notes 延後至 `v0.23.0`。
> 這是**兩次連續升級中最乾淨的一次**：
> 1. **三重 schema 全部零變化**：`SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3`、`_config_version = 52` 皆未動，`hermes_state*.py` 與 `config_migrations*.py` 對上游 diff 為 **0 行** → 完全可逆；
> 2. **自訂層 100% 零衝突**：上游本窗口**完全未動** `Dockerfile` 與 `docker/`（diff = 0 行），我們 7 個自訂 hunk 原樣移植，`git merge-tree` 實測零代碼衝突；
> 3. **線上全面檢查全綠**：Telegram 實測往返正常，44 項 API 全通，30 個 tools 就緒，**全天 0 筆 ERROR**（比上次乾淨 —— 11/03 有 4 筆 Telegram CLOSE-WAIT 網路抖動）。

---

## 2. 官方 Release Notes 稽核

### 2.1 官方量測

| 指標 | 值 |
|---|---|
| non-merge commits | 581 |
| changed files | 554 |
| 行數 | +24,012 / −3,144 |
| merged PRs | **174** |
| closed issues | 29 |

> 相較前一次窗口（776 PR / 4,316 檔 / +248,579 / −94,077），本次為輕量常規收斂版。核心 runtime（`gateway/` `agent/` `tools/` `hermes_cli/` `plugins/` `cron/` `pm/`）僅 98 檔（+3,992 / −903），其餘 ~456 檔為 `apps/desktop/`、`website/`、`plugin-catalog/`、`tests/`。

### 2.2 官方重點功能盤點

- **Desktop Group Chats 強化**：opt-in lead routing（聊天室標頭 Lead 徽章，`gateway/hosted_room_lead.py`）、排程 cron job 投遞至 Group Chats（`cron/scheduler_delivery_room.py`）、聊天室用途與共享筆記、單欄整合顯示成員即時狀態。
- **Kanban 快速切換分頁**：釘選的 Kanban 看板可作為 quick-switch tabs。
- **`$$TeX$$` 與 Mermaid 圖表渲染切換至 `pele`**：`pele 1.13.0` 取代 `mermaid 11.17.2`（`package.json` / `apps/desktop/package.json`），`package-lock.json` 淨減少 551 行依賴。
- **Desktop 更新錯誤面板**：顯示失敗更新的輸出與回報連結。
- **Web Access 啟動狀態**：顯示 Start 當前所在的步驟名稱與計時器。
- **Telegram on Team Gateway**：透過連結帳號至共享 Bot 完成設定（`gateway/relay/link.py`）。
- **Slack `thread_followup_silence`**：opt-in 靜音未點名的討論串回覆。
- **Catalog ChatGPT 訂閱模型 Daybreak 開關**（`agent/codex_service_tiers.py`）。
- **新增一批 `plugin-catalog` 條目**。

### 2.3 機器可讀真相對照

| 項目 | v0.22.6 | v0.22.7 | 判定 |
|---|---|---|---|
| `requires-python` | `>=3.11,<3.15` | `>=3.11,<3.15` | 不變 |
| Base image（兩個 `FROM`） | `debian:trixie-20261020@sha256:4c252754…` | **完全相同** | 零變動 |
| `pm/lock.json`（Python / Node / npm / uv / ffmpeg / ripgrep / chromium） | Python `3.14.9+20261021`、Node `26.12.1`、npm `12.0.2`、uv `0.13.5`、chromium `1208+145.0.7632.6` | **完全相同（零 diff）** | 工具鏈零變動 |
| Python 套件 | `nemo-relay 0.10.3` | **`nemo-relay 0.11.0`**（唯一變更的套件） | 單一套件小幅升版 |
| 前端圖表渲染 | `mermaid 11.17.2` | **`pele 1.13.0`** | 僅影響前端 / Desktop |

---

## 3. 關鍵技術調整與解決

### 3.1 自訂層 7 個 Hunk：零衝突原樣移植

上游本窗口**完全未觸碰** `Dockerfile` 與 `docker/`：

```bash
git diff upstream-v0.22.6 upstream-v0.22.7 -- Dockerfile docker/   # → 0 行
```

因此 `git merge-tree` 實測結果為：**程式碼 / Dockerfile / 設定 0 檔衝突**，僅 3 個官方 workflow 需 Purge。7 個自訂 hunk 全部原樣帶入：

| # | 位置 | 內容 |
|---|---|---|
| 1 | `runtime_base` apt | `openssh-server` `rsync` `locales` + `/var/run/sshd` + `ssh-keygen -A` + `C.UTF-8` / `en_US.UTF-8` / `zh_TW.UTF-8` locale 生成與 `/etc/default/locale`、`/etc/profile`、`.bashrc` 寫入 |
| 2 | `useradd` | `RUN useradd -u 10000 -m -d /opt/data -s /bin/bash hermes` |
| 3 | `python_deps` `pm.build_env` | 上游 extras 後追加 `--extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa` |
| 4 | `runtime` `/tmp/.npm-cache` | `mkdir -p /tmp/.npm-cache && chmod 1777` |
| 5 | `runtime` `/root/.npm` | `mkdir -p /root/.npm /root/.cache && chown -R 10000:10000` |
| 6 | `runtime` `ENV HOME` | `ENV HOME=/opt/data` |
| 7 | `runtime` entrypoint shim | `COPY --chmod=0755 docker/entrypoint-ssh.sh /opt/hermes/docker/entrypoint-ssh.sh` |

**建置日誌實錘**（非僅 diff 推論）：`apt-get install … openssh-server … rsync locales` + `zh_TW.UTF-8... done`、`RUN useradd -u 10000 -m -d /opt/data -s /bin/bash hermes`、`pm.build_env … --extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa`、`[write_install_stamp] wrote install-stamp.json -> caa90cb95e83 (my-config-v0.22.7)` 全部出現在 image build log 中。

### 3.2 CI Workflow Purge 與額外 README 移除

- 上游 58 個 workflow → 保留 **1 個**（`ghcr-publish.yml`，自 `my-config-v0.22.6` 覆寫回來，dispatch input 為 **`tag_name`**）。
- **額外移除 `.github/workflows/README.md`**：v0.22.7 新增的 611 行官方 CI 說明文件，內容描述 57 個已被 purge 的 workflow，對本分支已失真 → 隨 purge 一併刪除。

### 3.3 MCP 工具強化（R3）

- `tools/mcp_tool_config.py:227` — 產生 stdio 子行程時固定注入 `env["HERMES_HOME"] = str(get_hermes_home())`，避免跨 profile 落回預設 home。
- `tools/mcp_tool_discovery.py` — 改善 parked server 狀態回報。
- `tools/mcp_tool_agent.py` — 保護 prompt prefix 快取，不因 `check_fn` 抖動而位移（**對 prompt caching 有直接收益**）。
- 我們的 Camofox 走 HTTP MCP（`mcp_servers.camofox`），完全相容。

### 3.4 Gateway adapter 恢復機制拆分

`gateway/run_adapters.py` 的斷線重連 / backoff 邏輯拆為獨立 sibling `gateway/run_adapters_recovery.py`，並加入 `relay` 背景 self-provision retry。屬結構性改進，對 Telegram adapter 無破壞性（實測開機連線正常）。

---

## 4. 線上全面檢查結果（2026-11-04 實測）

```
版本演進:
v0.22.6 (upstream f896a331) → v0.22.7 (upstream caa90cb9) ✅
Python 3.14.9 │ OpenAI SDK 2.54.0 │ pydantic 2.14.1 │ nemo-relay 0.11.0
Node.js v26.12.1 │ npm 12.0.2 │ Debian 13.7 (trixie)
Config v52 → v52（不變，零遷移）

核心狀態（使用者 Telegram 端實測 + 主代理獨立覆核）:
- sessions: 133 (+1) ✅
- messages: 18,044 (+13) ✅
- integrity_check: ok ✅
- messages_fts: 18,044 = messages 18,044 ✅ FTS trigger 全部正常
- triggers: messages 12 + sessions 1 = 13（未動）✅
- worker_executions / worker_receipts: 0 / 0 ✅
- session_admissions: 11（正常）✅
- Config: v52 ✅
- 磁碟: 1.8T / 30% (509G) ✅
- 記憶體: 30Gi / 15Gi available ✅
- cron/jobs: 無 job（符合預期）✅
- API Connectivity: 44 項全通 ✅
- Skills Hub: 22 skills ✅
- Tools: 30 active ✅

部署與環境:
- pod: hermes-agent-58b98d987d-5nhh7（舊 pod hermes-agent-5f74db767c-x4d7c 已移除）
- image: ghcr.io/kuniakil/hermes-agent:v0.22.7（digest sha256:4ae8d02db0670f87fa9fcb3d06214e77c1a394405093f36d1755d27024172309）
- RESTARTS: 0
- deployment: updated=1/1 ready=1 avail=1（Available=True / Progressing=True）
- 3 種 locale（C.utf8 / en_US.utf8 / zh_TW.utf8）全在
- sshd / rsync / tini / tmux / ffmpeg 全在
- Chromium: /opt/hermes/tools/chromium-1208/chrome-linux64/chrome

Gateway 開機（部署後 07:35:47 起共 2,430 行）:
- ✓ telegram connected（Telegram polling confirmed healthy: getUpdates progressing）
- ✓ api_server connected、Gateway running with 2 platform(s)
- Channel directory built: 1 target(s)
- kanban dispatcher: embedded in gateway、Cron scheduler will tick 1 profile(s): ['default']
- Model context warmed: MiniMax-M3 → 1000000 tokens
- ERROR: 0、CRITICAL: 0；WARNING: 3（全為 Telegram adapter 良性訊息：DNS-over-HTTPS fallback 探索、Connecting attempt 1/8、Connected polling mode）
- 舊 pod 關閉為 graceful：all adapters disconnected at +1.94s → Previous gateway exited cleanly

Camofox MCP:
- DNS → 10.43.250.235；未帶 token GET → HTTP 401（端點存活）
- 帶 Authorization 的 MCP initialize JSON-RPC → HTTP 200
  serverInfo {"name":"camofox-mcp","version":"1.16.0"}，capabilities: tools + prompts ✅

額外端到端驗證（主代理執行，非使用者回報）:
- 經 gateway api_server 跑真實 agent 回合 → 模型成功呼叫 bash 工具並回傳 "hermes-upgrade-smoke"
- DB 同步寫入（sessions 132→133、messages 18,031→18,036）、integrity ok

今日日誌:
- 2026-11-04 全天 ERROR: 0 筆；部署後（07:35:33 之後）ERROR: 0 筆
- 比上次乾淨 —— 11/03 有 4 筆 Telegram CLOSE-WAIT 網路抖動，今天 0 筆

npm 漏洞:
- web workspace: 1 high + 5 moderate；ui-tui workspace: 1 high + 1 moderate
- 決策不變：不修（官方 3 個 issue #133435 / #132924 / #79021 於 2026-11-04 複查仍全為 OPEN）
```

---

## 5. 備份與資產處置

- **新備份**：`~/backups/hermes-20261104/`
  - `state.db`（184,508,416 B）、`state.db-wal`（0 B）、`state.db-shm`（32,768 B）、`config.yaml`
  - 驗證：`messages = 18031`、`sessions = 132`、`PRAGMA integrity_check = ok`
  - 製備方式：Pod 內 `PRAGMA wal_checkpoint(TRUNCATE)` 後以 **tar streaming** 傳回（`kubectl cp` 傳 176MB 時 websocket 中斷 `close 1006`）
- **舊備份**：`~/backups/hermes-20261103/`（176MB）— ✅ **已於 2026-11-04 依使用者授權刪除**（刪除前已複驗 `hermes-20261104` 完整性：`messages = 18031`、`sessions = 132`、`integrity = ok`）
  - 現存備份：`~/backups/hermes-20261104/`（176MB，保留）、`~/backups/immich-20261016/`（與本專案無關）
- **K8s Repo**：`~/kubernetes/hermes/overlays/n100/kustomization.yaml` 已提交並推送 `origin/main`（Commit `d703648`）
- **Hermes Repo**：分支 `my-config-v0.22.7`，31 個自訂 commits（1 CI purge + 6 核心 + 23 歷史文檔 + 1 本工作表），**0 個 merge commit，歷史完全線性**

---

## 6. 回滾方案

三重 schema 零變更（`SCHEMA_VERSION = 32` / `FTS_STORAGE_VERSION = 3` / `_config_version = 52`），且 DB 掛於 hostPath PVC `/data/services/hermes/data` 持續保存，因此回滾**不需要任何資料遷移**：

```bash
# 把 newTag 改回 v0.22.6 並重新套用即可
# ~/kubernetes/hermes/overlays/n100/kustomization.yaml
kubectl apply -k ~/kubernetes/hermes/overlays/n100
```

預期時間：image pull ~1m43s + 開機 < 1 分鐘。

---

## 7. Image stamp 與分支 HEAD 的差異（有意保留）

| 項目 | SHA | 說明 |
|---|---|---|
| 已部署 image 的 build stamp | `caa90cb95e` | 部署當下的分支 HEAD |
| 分支現況 HEAD（`my-config-v0.22.7`） | `e60a623ec7` | 差 3 個 commit |

差異內容**全部為文件**：`docs/worksheet-upgrade-hermes-v0.22.7-20261104.md` 的執行結果回填、`UPGRADE_LOG_v0.22.6_to_v0.22.7.md`，以及本工作表的結案。**runtime 程式碼零差異** —— 重新建置產出的 image 與現行 image 的執行行為完全相同。

**決策：不重新建置、不重新部署。** 理由：

1. 現行部署已通過完整線上驗證（D3–D10 全綠、0 ERROR、Telegram 實測往返正常）；
2. 重新建置會覆寫同一個 `v0.22.7` tag（Hard Rule 6 的既定行為），導致新 digest、需重新 pull + rollout + 重新驗證，**純粹為了讓 stamp 對齊一個文件 commit 而承擔風險**；
3. 使用者於 Telegram 端亦已指出 pod 當時運行僅約 29 分鐘，穩定性觀察窗口應予保留而非重置。

若日後因故需要讓 image stamp 與分支 HEAD 完全對齊，重跑同一條指令即可：

```bash
gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent \
  --ref my-config-v0.22.7 -f tag_name=v0.22.7 -f platforms=all
```

