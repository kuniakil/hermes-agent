# Hermes Agent 升級紀錄：v0.22.5 → v0.22.6

- **升級日期**：2026-11-03
- **目標版本**：`v0.22.6`（官方 commit `f0d94882e89ab8d4098b5bb2f166adfb9ee0a0ab`，2026-11-02 發佈）
- **升級前版本**：`v0.22.5`（基於官方 `v0.22.5` = `bf0203a794`）
- **新分支**：`my-config-v0.22.6`
- **Image source SHA**：`f896a331d11ea6e1d99b02baf610729487c18043`（= `hermes --version` 顯示的 `upstream f896a331`）
- **GH Actions Run**：[`41555930195`](https://github.com/kuniakil/hermes-agent/actions/runs/41555930195)（prepare / build-and-push amd64 / build-and-push arm64 / merge 全 success，總耗時 11m 15s）
- **發布映像**：`ghcr.io/kuniakil/hermes-agent:v0.22.6`（與 `latest`）
- **部署環境**：K3s n100，pod `hermes-agent-5f74db767c-x4d7c`
- **schema_version**：32 → **32**（**未變，DB 零遷移**）
- **config_version**：51 → **52**（**平滑推進，無破壞性變更**）
- **備份**：`~/backups/hermes-20261103/state.db`（176MB，integrity ok，messages 18,023；舊備份 `hermes-20261024` 已於 2026-11-03 清理）

---

## 1. 一句話總結

> 這是收斂了 **776 個 PR** 的大型 Patch 窗口。官方將完整 curated notes 延後至 `v0.23.0`。
> 我們透過事前靜態 diff 與線上實測抓出關鍵技術變更：
> 1. **`agent-browser` 徹底退役**：上游改由 `browser_exec` 直接驅動內建 `chromium`，我們順應移除舊 Dockerfile 中的 `agent-browser` hunk，避免了 CI build 失敗；
> 2. **DB Schema 未變（可逆）**：`SCHEMA_VERSION = 32`，若有異常可無損秒級退回 `v0.22.5`；
> 3. **Config v52 平滑過渡**：`camofox` 走標準 MCP，不觸發 Left-Core 誤裝與 toolset 誤關；
> 4. **線上全面檢查全綠**：Telegram 實測正常，44 項 API Connectivity 全通，30 個 tools 就緒。

---

## 2. 官方 Release Notes 稽核

### 2.1 官方量測

| 指標 | 值 |
|---|---|
| non-merge commits | 3,448 |
| changed files | 4,316 |
| 行數 | +248,579 / −94,077 |
| merged PRs | **776** |
| closed issues | 385 |

### 2.2 官方重點功能盤點

- **Webapp（瀏覽器版 Desktop）**：由 gateway 自身 listener 提供（`hermes webapp`），Dockerfile 新增 `webapp_build` stage 產出 `/opt/hermes/apps/desktop/dist-webapp`。
- `/model reset`：清除 session 的 model pin 而不丟失對話歷史。
- **per-skill locks**（`tools/skill_lock.py`）：防止自主寫入（可從 Desktop Capabilities 鎖定）。
- **prepared compaction**（`compression.prepare_ahead`，`agent/prepared_compaction.py`）：opt-in 預先壓縮。
- `hermes cron cancel` + per-job missed-run policy + Desktop cron Stop 按鈕。
- `/delegation` 選擇會跨 session 記住到下一回。
- `hermes migrate` 與 setup 支援從 Grok Bot / OpenBot 遷移。
- vault key 支援 opt-in OS-keychain 儲存。
- plugin catalog 的 `requires_hermes` 在 install 與 update 時強制檢查。
- `text_to_speech` 支援由 agent 自選 ElevenLabs voices（`tools/tts_elevenlabs_voices.py`）。
- `pre_llm_call` hook 可在 inference 前阻擋回合。
- Desktop group chat（rename / disband / mentions / 貼圖）與 sidebar profile 分組。
- Telegram video notes、Slack thread context emoji reactions。
- PM（package manager）支援斷點續傳下載。

---

## 3. 關鍵技術調整與解決

### 3.1 `agent-browser` 退役與 Dockerfile 7 個自訂 Hunk 整合

- **原因**：Commit `1ac18d2b12`（`refactor(pm): drop the agent-browser package; Chromium is a default package in its own right`）自 `pm/lock.json` 與 `pm/packages.py` 移除了 `agent-browser`，改為直接將 Chromium 作為預設套件，路徑寫在 `/etc/hermes/chromium-executable-path`。
- **處置**：
  - 移除舊有 Dockerfile 第 3 個 hunk（`[ensure(name) for name in (..., "agent-browser", ...)]` 與 symlink）。
  - 合併上游 apt 新增的 `tmux`，保留我們的 `openssh-server`、`rsync`、`locales` 與 sshd/locale 初始化。
  - 合併上游 `pm.build_env` 新增的 `--extra fal --extra documents`，保留我們的 5 個 extras（`edge-tts`、`firecrawl`、`dingtalk`、`feishu`、`exa`）。
  - 保留 `useradd -s /bin/bash`、`/tmp/.npm-cache`（1777）、`/root/.npm` chown 10000、`ENV HOME=/opt/data`、以及 `entrypoint-ssh.sh`。

### 3.2 Config Migration 51 → 52 與 Left-Core 稽核

- **機制**：v52 migration（`config_migrations_browser.py`）與 `left_core_migration.py` 將內建 Camofox backend 與 GitHub Copilot 移出 core 變為 catalog plugin。若判定在使用中，會在開機自動裝 plugin 並關閉 `browser` toolset。
- **實測證明**：
  - 我們的 Camofox 走獨立 MCP（`mcp_servers.camofox`），線上 `.env` 無 `CAMOFOX_URL`、`config.yaml` 無 `browser.cloud_provider`。
  - 主力模型為 MiniMax，無 Copilot 路由。
  - 開機後 `_config_version: 52`，`_left_core_used: None`，`mcp_servers.camofox` 完好運作，`browser` toolset 未被關閉。

---

## 4. 線上全面檢查結果（2026-11-03 實測）

```
版本演進:
v0.22.4 (upstream 621915ab) → v0.22.5 (upstream 505335bf) → v0.22.6 (upstream f896a331) ✅
Python 3.14.7 → 3.14.9
OpenAI SDK 2.24.0 → 2.54.0
Config v51 → v52

核心狀態:
- sessions: 132 (+5) ✅
- messages: 18,029 (+351) ✅
- integrity_check: ok ✅
- messages_fts: 18,029 = messages 18,029 ✅
- messages_fts_trigram: 18,029 ✅
- triggers: messages 12 + sessions 1 = 13 (全部正常運作) ✅
- worker_executions / worker_receipts: 0 / 0 ✅
- session_admissions: 9 (正常) ✅
- Config: v52 ✅
- 磁碟: 1.8T / 29% (494G，健康) ✅
- 記憶體: 30Gi / 15Gi available ✅
- cron/jobs: 無 job (符合預期) ✅
- API Connectivity: 44 項全通 ✅
- Skills Hub: 22 skills ✅
- Tools: 30 active ✅

執行期路徑與工具鏈變化:
- agent-browser → Chromium: /opt/hermes/tools/chromium-1208/chrome-linux64/chrome
- hermes 執行路徑: /opt/hermes/libexec/hermes (官方改採 libexec 慣例)
- 日誌: 僅有 Telegram 連線網路抖動重建 (CLOSE-WAIT)，非本地邏輯錯誤
- npm 漏洞: 維持「不修」決策 (官方 3 個 issue 仍 OPEN，runtime 暴露面 = 0)
```

---

## 5. 備份與資產處置

- **新備份**：`~/backups/hermes-20261103/state.db`（176MB，完整性 ok，保留）
- **舊備份**：`~/backups/hermes-20261024/`（已於 2026-11-03 依使用者授權刪除）
- **K8s Repo**：`~/kubernetes/hermes/overlays/n100/kustomization.yaml` 已提交並推送到 `origin/main`（Commit `045d005`）
