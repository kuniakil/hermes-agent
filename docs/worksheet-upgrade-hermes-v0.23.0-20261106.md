# Hermes Agent 升級工作表：v0.22.7 → v0.23.0

- **目標版本**：`v0.23.0`（官方 commit `2bd378ed1b8d6bf2192cb26e0a55ff3091e6bd19`，2026-11-05 發佈，*"The Hearth Release"*）
- **升級前版本**：`my-config-v0.22.7`（HEAD `4d7973ece9`，基於官方 `v0.22.7` = `b200f5bc60e3`）
- **新分支**：`my-config-v0.23.0`（基底 = `upstream-v0.23.0`，**不是**本地 `v0.23.0` tag）
- **Remote**：`origin` = 官方（NousResearch）、`kuniakil` = 個人 fork（⚠️ 與 OpenClaw 相反）
- **發布模型**：`my-config-v0.23.0` 分支為 source of truth，由 `ghcr-publish.yml`（dispatch input **`tag_name`**）建置 `ghcr.io/kuniakil/hermes-agent:v0.23.0`
- **目前上線版本**：✅ **`v0.23.0`**（K3s n100，pod `hermes-agent-f9496b576-wcxg8`，Running 1/1，RESTARTS 0，image digest `sha256:3aeff98b…`）
- **狀態**：✅ **升級完成，Phase E 收尾中**（Go-Sign 2026-11-06 已收到；Phase 0 / A / B / C / D1–D10b 全綠（含使用者 Telegram 實測）；僅待 D11 24h 觀察）
- **日期**：2026-11-06

---

## 0. ⚠️ 最高優先結論

### 0.1 一句話結論

**v0.23.0 是本系列至今最大的功能性版本（808 commits / 1223 檔），但對我們的資料庫與設定面是「零 schema 變更、零不可逆遷移」，自訂層 100% 零實質衝突 → 可低風險、可秒退的升級。**

真正的風險不在資料，在**執行期架構變更**：「一個 gateway 擁有每一場對話」+ **s6 監督樹重構**（profile gateway 從 `/run/service/` 搬到 `/run/hermes-service/`，`015-supervise-perms` 被重寫）。這兩項都直接作用在我們唯一的生產 Pod（Telegram bot + gateway）上，必須在 D8 開機驗證重點盯。

### 0.2 不可逆性判定（全部綠燈）

| 面向 | v0.22.7 | v0.23.0 | 判定 |
|---|---|---|---|
| DB `SCHEMA_VERSION` | 32 | **32** | ✅ 零變更 |
| `FTS_STORAGE_VERSION` | 3 | **3** | ✅ 零變更 |
| `hermes_state_schema.py` / `_common.py` / `_search.py` | — | **diff = 0 行** | ✅ 零變更 |
| config `_config_version` | 52 | **52** | ✅ 零遷移 |
| `hermes_cli/config_migrations.py` | — | **diff = 0 行** | ✅ 零變更 |
| `hermes_cli/left_core_migration.py` | — | **diff = 0 行** | ✅ 不會觸發新外掛自動安裝 |
| base image | `debian:trixie-20261020@sha256:4c25275…` | **同一 digest** | ✅ 零變更 |
| `requires-python` | `>=3.11,<3.15` | **同** | ✅ 零變更 |
| `nemo-relay` | `>=0.11,<0.12`（lock 0.11.0） | **同** | ✅ 零變更 |

> **結論：不需要 migration、不需要手動 DB 轉換、可無損退回 `v0.22.7`。** 備份仍為 MANDATORY（因為 Pod 會被換掉），但**不是**因為 schema 遷移，而是出於回退保險。

### 0.3 官方 Release Notes 的 5 條 ⚠️ Upgrade notes — 逐條對我們的環境判定

| 官方條目 | 我們的環境 | 判定 |
|---|---|---|
| **舊的內建 browser 工具被移除**（只剩 `browser_exec`） | `toolsets.py` 在 v0.22.7 與 v0.23.0 **都只有 `browser_exec`**；我們的 `browser` toolset 早已是 `browser_exec` | ✅ **本次無影響**（v0.22.6 已完成） |
| **Desktop 需要 macOS 13+ / 64-bit Windows**（Electron 40→44） | 我們**不部署 Desktop**（K3s 僅 server 容器，Electron 無 sidecar） | ✅ N/A |
| **`hermes mcp serve` → `hermes mcp-serve`**（移入外掛） | 我們**不使用** Hermes 作為 MCP server；`~/kubernetes/hermes/` 內 grep `mcp serve` = 0 筆 | ✅ N/A |
| **Word/PPT/Excel 合併為 `microsoft-office`** | 上游內建 skills 在兩個 tag **完全相同（44 = 44，檔名逐一 diff = IDENTICAL）**；但 **PVC 上 `/opt/data/skills` 有 181 個 `SKILL.md`**，含舊版殘留副本 | ⚠️ **低風險**：需在 D7 盤點殘留（見 §1.4） |
| **Webapp 預設關閉**（`webapp.enabled`） | 我們 config 無 `webapp` 鍵 → 預設關閉 | ✅ N/A |

### 0.4 真正需要在意的 4 個行為變更（不在官方 Upgrade notes 裡，但會作用到我們）

| # | 變更 | 對我們的影響 | 驗證點 |
|---|---|---|---|
| **B1** | **一個 gateway 擁有每一場對話**：CLI / TUI / Desktop / API / ACP / bots / cron 全部 attach 到同一 profile 的單一 gateway（自 v0.22.0 起，本版修完殘留問題） | 我們只有 Telegram bot + 1 個 gateway，架構最單純，但 **cron / 背景 subagent / 訊息佇列都改走 gateway 軌道** | D8（開機 log）、D10（真實 Telegram 往返） |
| **B2** | **s6 監督樹重構**：profile gateway 改由 hermes 自己的 s6-svscan 監督，scandir 從 `/run/service/` 搬到 `/run/hermes-service/`；`015-supervise-perms` 被整份重寫（99 行改寫） | 我們的容器就是 s6 stack；`hermes doctor` / `s6-svstat` 以 hermes 使用者操作 slot 的權限模型**改了** | D8（gateway 正常啟動、`s6-svstat` 可查、RESTARTS=0） |
| **B3** | **預設模型 GLM-5.2 → GLM-5.3** | 我們 config **顯式指定** `model.default: MiniMax-M3` / `provider: minimax` → **不受影響** | D7（config 覆核） |
| **B4** | **Telegram adapter 改動** + 訊息平台全面外掛化（Signal / Weixin / BlueBubbles / QQ / Yuanbao / WhatsApp Cloud → bundled platform plugins） | Telegram 是我們**唯一**的平台；adapter 有 13 行改動 | D3 / D8 / D10 |

### 0.5 決策點（Go-Sign 時請一併回覆）

| # | 決策 | 建議 |
|---|---|---|
| **A** | 目標版本 | **`v0.23.0`**（唯一官方穩定版，2026-11-05 發佈） |
| **B** | 自訂 commits 攜帶方式 | **原樣 cherry-pick**（8 個核心自訂 commits）+ Dockerfile 自訂層重新移植（7 hunks） |
| **C** | npm 漏洞 | **維持不修**（上游已於 v0.23.0 內含 undici 6.29.1 / 7.30.1 / zod 4.6.7 / fast-uri 3.1.9 修補，暴露面仍為 0） |
| **D** | FTS layout | **維持不動**（`FTS_STORAGE_VERSION = 3` 零變更） |
| **E** | 舊備份 | 先建 `~/backups/hermes-20261106/`，驗證完成後再請示清理 `~/backups/hermes-20261104/` |
| **F** | 殘留 skills 清理（`/opt/data/skills` 181 個，含舊版 `browser_*` 引用） | **本次不動**（v0.22.7 已在跑、狀態相同，非本次引入），另開議題處理 |

---

## 1. 官方 Release Notes 與機器可讀真相稽核

### 1.1 Release Notes 摘要（v0.23.0，2026-11-05）

> *The Hearth Release.* 自 v0.22.0 起累積 **~10,080 commits / ~1,950 merged PRs / ~8,720 files / +725,200 / −201,400 / ~850 issues closed / 666 contributors**。本版把 v0.22.1–v0.22.7 的 patch 收斂完整收錄並完整記錄。

**對我們最相關的 6 個亮點：**

1. **一個 gateway 擁有每一場對話**（#106742, #140334）— 這是本版的架構主軸
2. **所有訊息平台 adapter 變成外掛**（#139843, #140168）— Telegram 是唯一受影響的平台
3. **省 token / 省快取**：cron job 共用 prompt cache key、one-shot 每次少 1,570 prompt tokens、4 個 tool schema 少 319 tokens；gateway 記憶體治理（closed session 釋放記憶體、glibc malloc arena 上限 4）
4. **CLI/TUI 終端機內嵌圖片**（#147293, #148874）+ **`/rewind`** 回捲對話（#144937, #148880）
5. **外掛自我更新** + catalog 從 ~600 暴增到 **>1,050** 筆；`plugins.auto_apply` 預設關
6. **built-in skills 58 → 44**（Word/PPT/Excel 合併為 `microsoft-office`）；`hermes curator lock` 鎖定自訂 skill

### 1.2 機器可讀真相（Dependency / Runtime 稽核）

| 項目 | v0.22.7 | v0.23.0 | 判定 |
|---|---|---|---|
| base image | `debian:trixie-20261020@sha256:4c25275446ca371766b8b093c696782eabce06263fccacb8d5d813b3dc44b308` | **完全相同** | 🟢 |
| `requires-python` | `>=3.11,<3.15` | **同** | 🟢 |
| `nemo-relay` | `>=0.11,<0.12` | **同** | 🟢 |
| Python build pins | `pypdf==6.21.2` / `pyasn1==0.6.4` / `setuptools==83.0.0` | `pypdf==6.21.4` / `pyasn1==0.6.5` / `setuptools==84.1.0`（GHSA-xmj3-9gf7-h52w） | 🟡 build-env 釘版，隨 build 生效 |
| `zod`（resolved） | 4.6.5 | **4.6.7** | 🟢 上游修補 |
| `undici`（resolved） | 6.29.0 / 7.30.0 | **6.29.1 / 7.30.1** | 🟢 上游修補 |
| `fast-uri` | 3.1.8 | **3.1.9** | 🟢 上游修補 |
| Electron | 40 | **44**（Desktop only） | ⚪ N/A |
| 新增 `HERMES_*` 環境變數 | — | `HERMES_FORK_SERVER_ONLY` / `HERMES_TEST_FORKSERVER`（**皆為測試用**） | 🟢 N/A |
| 新增 config 預設鍵 | — | `aux.group_router`、`display.inline_images`；移除 `aux.skills_hub` 預設值 | 🟢 選擇性，無版本號變動 |

### 1.3 官方 Highlight 中「與我們環境無關」的快速篩除

以下亮點**不影響我們**（不部署 Desktop / 不部署 Photon sidecar / 不用 Singularity / 不用 Camofox 內建瀏覽器 / 不用 MCP server 模式 / 不用 agent-browser / 不跑 cron job / `/opt/data/plugins` 為空）：

Webapp、Desktop 全系列、Bot Mode Group Chats、付费 MCP 工具計價、`advanced-delegation` 外掛、Meshy / ElevenLabs / X Chat / REA / bubblewrap、密碼管理器 + keychain、`hermes cron cancel`（我們無 job）、Kanban worker、`/usage` 計費窗、`agent.daybreak`、外掛自我更新、`hermes setup` 匯入、Microsoft Store / Nix / 安裝器、`--cpu-profile`。

### 1.4 需要我們在部署後實地確認的「殘留物」盤點

| 項目 | 現況（2026-11-06 實測） | 判定 |
|---|---|---|
| `/opt/data/skills` | **181 個 `SKILL.md`**（39 個目錄，含 `.archive/`） | ⚠️ 內含引用已移除 `browser_navigate` / `browser_click` / `browser_scroll` / `browser_type` 的舊 skill（共 16 / 4 / 3 / 4 處引用）。**但這在 v0.22.7 已是現況**，非本次引入 → 見決策 F，本次不動 |
| `/opt/data/plugins` | **空** | 🟢 外掛自動更新 / catalog 無影響 |
| `/opt/data/profiles` | **無**（單一 default profile） | 🟢 B2 的 profile-gateways 路徑不會被觸發，但 s6 基礎變更仍會生效 → 仍需 D8 |
| `/opt/data/cron` | 無 job（僅 `executions.db` + ticker 心跳） | 🟢 cron 共享 prompt cache 無實際受益也無風險 |
| `browser.camofox` 設定塊 | 存在但 `cdp_url: ''`、無 `cloud_provider`、無 `use_gateway` | 🟢 `camofox_in_use()` 回 False → **不會觸發 camofox 外掛自動安裝** |
| `mcp_servers.camofox` | HTTP 端點 `http://camofox-mcp.camofox.svc.cluster.local:8080/mcp` | 🟢 是**外部 MCP server**，不是內建 Camofox 瀏覽器 → 不受「Camofox 移出 core」影響 |

---

## 2. Diff 與衝突面稽核（`upstream-v0.22.7 → upstream-v0.23.0`）

### 2.1 變動量

| 指標 | 值 |
|---|---|
| commits | **808** |
| changed files | **1,223** |
| 行數 | **+42,358 / −11,117** |
| 核心 runtime（`gateway/ agent/ cli.py run_agent.py model_tools.py toolsets.py`） | 83 檔 / +3,023 / −609 |

> ℹ️ 官方 Release Notes 的「10,080 commits / 8,720 檔」是**自 v0.22.0 起**的累計（含 v0.22.1–v0.22.7）。我們的實際升級落差是 **v0.22.7 → v0.23.0** = 808 commits / 1,223 檔。

### 2.2 `git merge-tree` 實測衝突報告

```bash
git merge-tree --write-tree --merge-base=upstream-v0.22.7 upstream-v0.23.0 my-config-v0.22.7
```

| 類別 | 檔案數 | 明細與處置 |
|---|---|---|
| **Modify/Delete 衝突（`.github/workflows/*`）** | **12 檔** | `README.md`、`bootstrap-installer.yml`、`deploy-site.yml`、`desktop-bundle-smoke.yml`、`desktop-bundled-release.yml`、`install-e2e-macos-run.yml`、`js-tests.yml`、`pm-bundle.yml`、`stable-release-publication.yml`、`stable-release.yml`、`tests-os.yml`、`tests.yml` → **依 Purge 規則全數刪除，只留我們的 `ghcr-publish.yml`（零人工解衝成本）** |
| **Content 衝突（程式碼 / Dockerfile / 設定）** | **0 檔** | **完全零衝突！** `Auto-merging Dockerfile` → 自動合併成功 |
| **自動合併無衝突** | 全部自訂檔 | `docker/stage2-hook.sh`、`docker/entrypoint-ssh.sh`、`docker-compose.yml`、`.env.example`、`AGENTS.md`、所有 `UPGRADE_LOG_*.md` 與 `docs/` 檔 |

### 2.3 Dockerfile 逐 hunk 對撞分析

| 面向 | 結果 |
|---|---|
| 上游 v0.22.7→v0.23.0 動 `Dockerfile` | **2 個 hunk，且全部是註解改寫**（`s6-rc.d` 說明、`/run/hermes-service/` 說明），**零功能性變更** |
| 我們的自訂層 | **7 個 hunk**，位於上游 Dockerfile 的第 78 / 175 / 302 / 380 / 397 / 490 / 515 行附近 |
| 位置重疊 | **零重疊** → 移植零衝突 |

上游 2 個 hunk 的實際內容（節錄）：

```
-# Static services declared at build time: main-hermes + dashboard.
+# Static services declared at build time: main-hermes, dashboard and
+# profile-gateways. … they live under /run/hermes-service/ (tmpfs) …
 RUN mkdir -p /etc/cont-init.d && \
     printf '#!/command/with-contenv sh\nexec /opt/hermes/docker/stage2-hook.sh\n' …
```

### 2.4 線上環境唯讀基線預檢（2026-11-06 實測，context `n100-cf`）

對目前運行中的 K3s n100 Pod（`hermes-agent-58b98d987d-5nhh7`）進行唯讀檢查：

| 指標 | 2026-11-06 實測值 | 狀態 |
|---|---|---|
| Deployment image | `ghcr.io/kuniakil/hermes-agent:v0.22.7` | 🟢 |
| Pod 狀態 | `1/1 Running`, `RESTARTS 0`, age `47h` | 🟢 健康 |
| `sessions` 總數 | **133** | 🟢 與 v0.22.7 升級後一致 |
| `messages` 總數 | **18,044** | 🟢 零損失基線 |
| 24h 內訊息數 | **0**（最後一則 `2026-11-04 08:04:35` 台北 / `00:04:35 UTC`） | 🟢 **閒置近 2 天，安全升級窗口** |
| `state.db` 大小與完整性 | **184,508,416 B (176.0 MB)**，`PRAGMA integrity_check` = **`ok`** | 🟢 完好 |
| `session_admissions` / `worker_executions` / `worker_receipts` | `11` / `0` / `0` | 🟢 無殘留背景任務 |
| `_config_version` | **52** | 🟢 已在最新 v52 |
| `model` | `default: MiniMax-M3` / `provider: minimax`（**顯式指定**） | 🟢 不受 GLM-5.3 預設變更影響 |
| `terminal.backend` | `local` | 🟢 不受 Singularity 移出 core 影響 |
| `toolsets` | `[hermes-cli]`；`platform_toolsets.cli` 含 `browser` | 🟢 `browser` = `browser_exec` |
| `mcp_servers.camofox` | HTTP `http://camofox-mcp.camofox.svc.cluster.local:8080/mcp` + Bearer token | 🟢 不受影響 |
| `/opt/data/plugins` | **空** | 🟢 |
| 既有備份盤點（`~/backups/`） | `~/backups/hermes-20261104/`（v0.22.7 升級快照，176MB） | 🟢 清楚列管 |

---

## 3. 需攜帶的自定義補丁清單

### 3.1 Dockerfile 自訂層（7 個有效 hunk，重新移植到 v0.23.0 基底）

| # | 位置（上游行號） | 內容 | v0.23.0 處置 |
|---|---|---|---|
| 1 | `runtime_base` apt (~L78) | 在上游 apt 清單加上 `openssh-server` `rsync` `locales` `tmux`；建立 `/var/run/sshd` + `ssh-keygen -A`；產生 `C.UTF-8` / `en_US.UTF-8` / `zh_TW.UTF-8` locale 並寫入 `/etc/default/locale`、`/etc/profile`、`.bashrc` | ✅ **原樣移植（零重疊）** |
| 2 | `useradd` (~L175) | `RUN useradd -u 10000 -m -d /opt/data -s /bin/bash hermes` | ✅ **原樣移植** |
| 3 | `python_deps` `pm.build_env` (~L302) | 在上游 extras 後方加上 `--extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa`（上游另有 `--extra azure-identity --extra matrix --extra google-chat --extra fal --extra documents`） | ✅ **原樣移植（行號平移，內容不動）** |
| 4 | `runtime` `/tmp/.npm-cache` (~L380) | `RUN mkdir -p /tmp/.npm-cache && chmod 1777 /tmp/.npm-cache` | ✅ **原樣移植** |
| 5 | `runtime` `/root/.npm` (~L397) | `RUN mkdir -p /root/.npm /root/.cache && chown -R 10000:10000 /root/.npm /root/.cache` | ✅ **原樣移植** |
| 6 | `runtime` `ENV HOME` (~L490) | `ENV HOME=/opt/data` | ✅ **原樣移植** |
| 7 | `runtime` entrypoint shim (~L515) | `COPY --chmod=0755 docker/entrypoint-ssh.sh /opt/hermes/docker/entrypoint-ssh.sh` | ✅ **原樣移植** |

### 3.2 自訂 Commits 攜帶計畫（`upstream-v0.22.7..my-config-v0.22.7`，共 31 個 commits）

在 `my-config-v0.23.0`（基於 `upstream-v0.23.0`）上依序處理：

| 順序 | 原 Commit | 類別 | 說明 | 處置方式 |
|---|---|---|---|---|
| 1 | `04138723b9` | CI Purge | `chore(ci): purge official CI workflows; retain only ghcr-publish.yml` | 🔁 **不 cherry-pick**：在新分支上重做 purge（上游 v0.23.0 有 58 個 workflow 且**不含** `ghcr-publish.yml` → 從 `my-config-v0.22.7` 檢出我們的版本） |
| 2 | `45c07a7c6f` | Docker | `fix(docker): restore docker/entrypoint-ssh.sh for Zeabur backward compatibility` | ✅ `git cherry-pick`（上游零改動 → 零衝突） |
| 3 | `28607c420f` | Docker | `chore: carry forward my-config docker-compose.yml (uses HERMES_IMAGE env, TZ=Asia/Taipei)` | ✅ `git cherry-pick`（零衝突） |
| 4 | `faa80374cc` | Docs/Rule | `chore: re-append Mac host resource constraint rule to AGENTS.md` | ✅ `git cherry-pick`（零衝突） |
| 5 | `20264ca395` | Docker | `feat(docker): restore custom SSH setup and npm cache handling in stage2-hook.sh` | ✅ `git cherry-pick`（上游零改動 → 零衝突） |
| 6 | `34ca85b519` | Docker | `feat(docker): re-port custom layer (SSH, locales, extras, perms) onto v0.22.6` | ⚠️ **手動移植**（改的是 Dockerfile；上游只動註解 → 可直接套用，但需逐條核對 7 個 hunk 是否落在 v0.23.0 的正確位置） |
| 7 | `a8491124a7` | Env | `chore(env): document HERMES_IMAGE in .env.example` | ✅ `git cherry-pick`（零衝突） |
| 8 | `b1f38e3fe7` … `4d7973ece9`（24 個 commits） | Docs | v0.22.2 / v0.22.4 / v0.22.5 / v0.22.6 / v0.22.7 升級工作表、`UPGRADE_LOG_*`、Camofox MCP 測試報告 | ✅ `git cherry-pick`（全為獨立文檔，零衝突）+ 本工作表 |

---

## 4. 執行步驟 Checklist（待收到 Go-Sign 後依序執行）

### Phase 0 — 停機前盤點 + 備份（MANDATORY）

- [x] 0.1 確認無使用中 — ✅ **實測 `msgs_24h = 0`**，最後一則 `2026-11-04 08:04:35` 台北 / `00:04:35 UTC`（閒置近 2 天）
- [x] 0.2 記錄升級前基線（部署後不得下降）：
  - **2026-11-06 實測基線**：`sessions = 133`、`messages = 18,044`、`state.db = 184,508,416 B (176.0MB)`、`integrity = ok`
  - `session_admissions = 11`、`worker_executions = 0`、`worker_receipts = 0`
  - Pod：`hermes-agent-58b98d987d-5nhh7`，`Running`，`RESTARTS 0`，age `47h`
- [x] 0.3 記錄 FTS 現況（維持 opt-in，本次不動）— ✅ `FTS_STORAGE_VERSION = 3` 於 v0.22.7 / v0.23.0 皆相同
- [x] 0.4 記錄 config 基線 — ✅ **實測 `_config_version: 52`**、`model.default: MiniMax-M3` / `provider: minimax`、`terminal.backend: local`、`toolsets: [hermes-cli]`、`mcp_servers.camofox`（HTTP + Bearer）、`browser.cdp_url: ''`、`/opt/data/plugins` 空、`/opt/data/profiles` 無
- [x] 0.5 **備份 DB（`.db` + `.db-wal` + `.db-shm`，缺一不可）** — ✅ 建立於 `~/backups/hermes-20261106/`
  - 前置：`PRAGMA wal_checkpoint(TRUNCATE)` → 實測 `(0, 0, 0)`，`state.db-wal` 歸零
  - 傳輸：**tar streaming**（`kubectl exec -- tar -cf - -C /opt/data state.db state.db-wal state.db-shm config.yaml`）→ exit 0，184,565,760 B
  - 產物：`state.db`（184,508,416 B）、`state.db-wal`（0 B）、`state.db-shm`（32,768 B）、`config.yaml`（13,234 B）
- [x] 0.6 驗證備份完整性 — ✅ **實測 `messages = 18,044` / `sessions = 133` / `PRAGMA integrity_check = ok`**
- [x] 0.7 盤點既有備份 — ✅ `~/backups/hermes-20261104/`（v0.22.7 升級快照，176MB）、`~/backups/immich-20261016/`（與本次無關）
- [x] 0.8 **刪除舊備份**（決策 E，2026-11-06 經使用者授權）— ✅ 刪除前複驗 `hermes-20261106`：`integrity = ok`、`messages = 18,044`、`sessions = 133` → 通過；`rm -rf ~/backups/hermes-20261104/`（回收 176MB）
  - 現存備份：`~/backups/hermes-20261106/`（176MB，保留）、`~/backups/immich-20261016/`（與本專案無關）

### Phase A — 建立分支 + Purge Workflows + 移植自訂 Commits

- [x] A0. **取得使用者 Go-Sign** — ✅ 2026-11-06 收到「go」，A–F 全部採納建議方案
- [x] A1. `git fetch origin refs/tags/v0.23.0:refs/tags/upstream-v0.23.0 --no-tags` — ✅ 已完成，commit `2bd378ed1b8d6bf2192cb26e0a55ff3091e6bd19`（`git rev-parse upstream-v0.23.0^{commit}` 一致）
- [x] A2. `git checkout -b my-config-v0.23.0 upstream-v0.23.0` — ✅ 分支建立於 `2bd378ed1b`
- [x] A3. Purge 官方 workflows，只留我們的 `ghcr-publish.yml`：
  ```bash
  find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete
  git checkout my-config-v0.22.7 -- .github/workflows/ghcr-publish.yml
  git add .github/workflows
  git commit -m "chore(ci): purge official CI workflows; retain only ghcr-publish.yml"
  ```
  - ✅ 實測：上游 **58 個** workflow → 保留 **1 個**；commit `2a529f1e39`（59 files changed, **+154 / −13,404**）
  - 📌 上游 v0.23.0 **不含** `ghcr-publish.yml`，我們的版本由 `my-config-v0.22.7` 檢入
- [x] A4. Cherry-pick 零衝突自訂 commits：`45c07a7c6f`、`28607c420f`、`faa80374cc`、`20264ca395`、`a8491124a7` — ✅ **全部零衝突**（Dockerfile 那筆顯示 `Auto-merging Dockerfile`，亦無衝突）
- [x] A5. **Dockerfile 自訂層移植 7 hunks** — ✅ 由 `34ca85b519` cherry-pick 套用（commit `8004b8a18b`，33 insertions / 3 deletions）
- [x] A6. 驗證自訂層 — ✅ `git diff upstream-v0.23.0 HEAD -- Dockerfile | grep -c '^@@'` = **7**；15 個自訂標記（`openssh-server` / `rsync` / `locales` / `ssh-keygen -A` / `zh_TW.UTF-8` / `en_US.UTF-8` / `useradd -u 10000` / `--extra edge-tts` / `firecrawl` / `dingtalk` / `feishu` / `exa` / `/tmp/.npm-cache` / `ENV HOME=/opt/data` / `entrypoint-ssh.sh`）**全數存在**
  - hunk 位置因上游 +2 行而平移：`@@ -490→492`、`@@ -515→517`（其餘不變），**零位置重疊**
- [x] A7. Cherry-pick 30 個歷史文檔 commits + 提交本工作表 — ✅ **全部零衝突**；本工作表 commit `3d6cda5e0d`
- [x] A8. **tracked-but-ignored 遺失偵測** — ✅ `old = 22,226` / `new = 22,523`；**LOST = 23 檔，逐檔驗證全部在 `upstream-v0.23.0` 亦不存在**（= 上游主動刪除：12 個 optional-skills、`apps/desktop/src/plugins/hermes-bots/canonical-group-list-gateway-open.test.tsx`、`ui-tui/src/components/petSprite.tsx` 及 9 個對應 website 文件）→ **真正遺失 = 0 檔**；7 個自訂檔全數在位
- [x] A9. 線性檢查 — ✅ **merge commits = 0**，自訂 commits 合計 **38**（1 purge + 6 core + 30 docs + 1 worksheet）

### Phase B — 本地輕量驗證（嚴禁跑重型測試或本機 docker build）

- [x] B1. `git status` 乾淨 — ✅ 工作區無未提交變更
- [x] B2. `.github/workflows/` 僅有 `ghcr-publish.yml` — ✅
- [x] B3. 關鍵檔案完整性 — ✅ 全數存在且行數與 v0.22.7 基線一致：`docker/entrypoint-ssh.sh` (13) / `docker/stage2-hook.sh` (874) / `docker-compose.yml` (19) / `AGENTS.md` (175) / `.env.example` (559) / `.github/workflows/ghcr-publish.yml` (154)
- [x] B4. `ghcr-publish.yml` dispatch input — ✅ 實測 `tag_name`（description: `Image tag name (e.g. v2026.8.13)`）+ `platforms`（choice: all/amd64/arm64，default `all`）
- [x] B5. `hermes_state_common.py` — ✅ 實測 `:289 SCHEMA_VERSION = 32`、`:312 FTS_STORAGE_VERSION = 3`
- [x] B6. `hermes_cli/config_defaults.py` — ✅ 實測 `:2709 "_config_version": 52`
- [x] B7. `.env` 仍在 working tree 且未被 git track — ✅ 本機 `.env`（51 B）存在、`git ls-files` 計數 **0**
- [x] B8. **上游 Dockerfile 僅註解變更** — ✅ **實錘 R1**：`git diff upstream-v0.22.7 upstream-v0.23.0 -- Dockerfile` 的 `+`/`−` 行**全部是 `#` 註解**（2 個 hunk、11 行），過濾掉註解後輸出為空 → **零功能性變更**
  - 另實測 `scripts/write_install_stamp.py` 在兩 tag **CLI flags 完全相同**（`--base-version` / `--display-version` / `--distance` / `--commit` …），我們 workflow 的呼叫方式不需修改

### Phase C — 推送 Fork + 觸發 GHCR Build

- [x] C1. `git push -u kuniakil my-config-v0.23.0` — ✅ `[new branch] my-config-v0.23.0 -> my-config-v0.23.0`
- [x] C2. `gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v0.23.0 -f tag_name=v0.23.0 -f platforms=all`
  - ✅ **無 422**（Hard Rule 8 未觸發）；run URL → `https://github.com/kuniakil/hermes-agent/actions/runs/42129150541`
  - `gh auth status`：`kuniakil`（GH_TOKEN），scopes 含 `workflow` ✅
- [x] C3. 驗證觸發的 run — ✅ 實測 `event=workflow_dispatch`、`headBranch=my-config-v0.23.0`、`headSha=3d6cda5e0d`（= 本地 HEAD，**非**上游 `2bd378ed1b`）、`createdAt=2026-11-05T23:26:02Z`、`status=in_progress`
- [x] C4. **派背景子代理**監控 `gh run watch`（Hard Rule 9；主迴圈不阻塞）— ✅ 唯讀監控子代理回報
- [x] C5. 驗證 multi-arch image tags — ✅ **`v0.23.0` OK**、**`latest` OK**（同一 index）
  - media type：`application/vnd.oci.image.index.v1+json`（multi-arch OCI index）
  - index digest：`sha256:3aeff98bdf226fdd65bd2d6f03783295a9737a5fa619fefc7f3f426cd365f2ee`
  - `linux/amd64` → `sha256:7f27da89288c42a1b1bb7e3608718b116cec566a14a81f538b89c47a4d2dcab7`
  - `linux/arm64` → `sha256:bd8ecb549804c80166ca0748ddf9296f3a99a5ea3655ff399da137c373c3b6a8`
  - 附屬 `unknown/unknown` attestation / provenance manifest（buildx 正常行為）
- [x] C6. 確認 install stamp — ✅ build log 內 `[write_install_stamp] wrote install-stamp.json -> 3d6cda5e0d84 (my-config-v0.23.0)`，stamp 的 `commit` 欄位與 build provenance 的 `vcs:revision` / `github_workflow_sha` **全部指向我們的 commit**
- [x] C7. **自訂層 14/14 全部進入 image** — ✅ build log 內 13 個標記直接命中（`openssh-server` / `rsync` / `ssh-keygen -A` / `zh_TW.UTF-8` / `en_US.UTF-8` / `useradd -u 10000` / `--extra edge-tts` / `firecrawl` / `dingtalk` / `feishu` / `exa` / `/tmp/.npm-cache` / `entrypoint-ssh.sh`）；第 14 個 `ENV HOME=/opt/data` 因 Dockerfile 的 `ENV` 指令**不會被 echo 成 build step**（log 內連 `HERMES_HOME` / `HERMES_TUI_DIR` 也都沒有），已改以 `docker buildx imagetools inspect --format '{{json .Image}}'` 直接驗證 published image config → **amd64 與 arm64 的 `Env` 清單皆含 `HOME=/opt/data`** ✅
- [x] C8. Build 結果 — ✅ **SUCCESS**，耗時 **11m55s**（`23:26:02Z → 23:37:57Z`）；jobs：`prepare` / `build-and-push (linux/amd64, ubuntu-latest)` / `build-and-push (linux/arm64, ubuntu-24.04-arm)` / `merge` **全部 success**

### Phase D — K3s 部署 + 全方位驗證

- [x] D1. 更新 `~/kubernetes/hermes/overlays/n100/kustomization.yaml` — ✅ `newTag: "v0.22.7"` → **`"v0.23.0"`**；commit `61491d0`，push `b6b4ab4..61491d0 main -> main`
- [x] D2. `kubectl apply -k ~/kubernetes/hermes/overlays/n100` — ✅ apply 結果：`namespace/hermes unchanged`、`secret/secrets-env unchanged`、`service/hermes-agent unchanged`、**`deployment.apps/hermes-agent configured`**、`ingressroutetcp.traefik.io/hermes-ssh-ingress unchanged`
  - ✅ **rollout 成功**（背景子代理監控，耗時 ~100s）：新 pod **`hermes-agent-f9496b576-wcxg8`**，`Running 1/1`、`ready=true`、**`RESTARTS 0`**、`startedAt=2026-11-05T23:41:01Z`、node `n100`
  - ✅ image ID = `ghcr.io/kuniakil/hermes-agent@sha256:3aeff98bdf226fdd65bd2d6f03783295a9737a5fa619fefc7f3f426cd365f2ee` = **v0.23.0 multi-arch index digest，完全吻合**
  - ✅ hostPath `/data/services/hermes/data` 持續掛載於 `/opt/data`（DB 未遺失）；`hermes-ssh-host-keys` 6 個 `/etc/ssh/ssh_host_*` 掛載正常
  - ✅ 舊 pod `hermes-agent-58b98d987d-5nhh7` 已移除；ReplicaSet 縮到 0/0/0；Deployment `updated/ready/avail = 1/1/1`、`Available=True`、`Progressing=True`
- [x] D3. **冒煙測試**（對照 v0.22.7 基線）— ✅ **全部通過**
  - Python `3.14.9` ✅、`openai 2.54.0` ✅、`pydantic 2.14.1` ✅、**`nemo-relay 0.11.0` ✅**
  - Node.js `v26.12.1` ✅、npm `12.0.2` ✅
  - Debian base = `13 (trixie)` ✅
  - 3 種 locale（`C.utf8` / `en_US.utf8` / `zh_TW.utf8`）全在 ✅
  - `sshd` `/usr/sbin/sshd` ✅、`rsync` `/usr/bin/rsync` ✅、`tini` `/usr/bin/tini` ✅、`tmux` `/usr/bin/tmux` ✅、`ffmpeg` `/usr/local/bin/ffmpeg` ✅
  - Chromium binary 存在：`/opt/hermes/tools/chromium-1208/chrome-linux64/chrome` ✅
  - Telegram connected ✅、**0 ERROR / 0 CRITICAL** ✅（見 D8）
- [x] D4. **版本確認** — ✅ 實測 **`Hermes Agent vv0.23.0 (2026.9.24) · upstream 3d6cda5e`**（`upstream` 後綴為**我們的 commit**，非上游 `2bd378ed1b`）
- [x] D5. **DB Schema 檢查** — ✅ `PRAGMA integrity_check` = **`ok`**；`SCHEMA_VERSION = 32` / `FTS_STORAGE_VERSION = 3` 零變更
- [x] D6. **資料完整性** — ✅ 部署後 `sessions = 134`（基線 133 + 1 條 api_server 回合）、`messages = 18,049`（基線 18,044 + 5）、**`messages_fts = 18,049` = messages**、`admissions = 12`、`worker_executions = 0`、`worker_receipts = 0` → **零損失**
- [x] D7. **Config 驗證** — ✅ `_config_version` 維持 **52**（無遷移）；`model.default: MiniMax-M3` / `provider: minimax`、`terminal.backend: local`、`toolsets: [hermes-cli]` 原封不動；`mcp_servers.camofox` 原封不動；**`_left_core_used` 出現次數 = 0** → 不觸發任何外掛自動安裝
- [x] D8. **開機與穩定性驗證**（★ 涵蓋 B1/B2）— ✅
  - `RESTARTS = 0`
  - 開機 log（`2026-11-06 07:41:01` 起）：`Model context warmed: MiniMax-M3 -> 1000000 tokens (detected)` ✅、`✓ telegram connected` ✅、`✓ api_server connected` ✅、`Gateway running with 2 platform(s)` ✅、`Channel directory built: 1 target(s)` ✅、`kanban dispatcher: embedded in gateway` ✅、`Cron scheduler will tick 1 profile(s): ['default']` ✅
  - 舊 Pod 關閉為 graceful：`Shutdown context: signal=SIGTERM under_systemd=no parent_name=s6-supervise` ✅
  - **B2 專項 ✅**：s6 行程樹已切換到 v0.23.0 新架構 — `s6-supervise profile-gateways` (pid 30)、**`s6-svscan /run/hermes-service`** (pid 185)、`s6-supervise gateway-default` (pid 199)、`s6-supervise main-hermes` (pid 33)、per-profile log `s6-log … /opt/data/logs/gateways/default`
  - **B2 專項 ✅**：s6 slot 可被 hermes 使用者查詢，**無 EACCES** — `s6-svstat /run/service/main-hermes` → `up (pid 186 pgid 186)`；`s6-svstat /run/hermes-service/gateway-default` → `up (pid 202 pgid 202)`；`hermes doctor` → `s6 Supervision ✓ Host gateway: the host gateway (PID 202) serving profiles default`
  - **B2 行程樹實測**（`ps -eo pid,ppid,cmd`）：`1 s6-svscan -X3 -- /run/service` → `30 s6-supervise profile-gateways` → **`185 s6-svscan /run/hermes-service`** → `199 s6-supervise gateway-default` → `202 hermes … gateway run --replace`（**以 hermes 使用者執行**）+ `203 s6-log … /opt/data/logs/gateways/default`
    - 📌 `/run/hermes-service/` 底下只有 `gateway-default` 一個 slot；`profile-gateways` 是**根 scandir 的 longrun（scandir 守護者）**，本身不是 `/run/hermes-service` 下的 slot → 對它下 `s6-svstat` 會得到 `s6-supervise not running`，**這是設計如此、非故障**
  - `dashboard` slot 顯示 `down (exitcode 0)` = **設計如此**（`HERMES_DASHBOARD` 未設時 run script 乾淨退出、finish script 回 125 → slot 永久 down），非故障
  - 部署後 ERROR 統計：**開機後 2 筆，全部是我方 `/v1/skills` 探測所觸發**（見 §8）；排除後 **ERROR = 0、CRITICAL = 0**（全 log 的 810 筆歷史 ERROR 皆落在 `2026-10-07` ~ `2026-11-03`，11-04 起為 0）
- [x] D9. **Camofox MCP 驗證** — ✅ DNS → `10.43.250.235`；未帶 token GET → `HTTP 401`（端點存活、正確要求 Authorization）；帶 token 的 MCP `initialize` JSON-RPC → **`HTTP 200`**，`serverInfo {"name":"camofox-mcp","version":"1.16.0"}`，capabilities 含 `tools` + `prompts`
  - 註：Hermes config 的 Bearer token 與 `camofox/camofox-secret:CAMOFOX_HTTP_API_KEY` **逐字相符**（40 chars，secret 建立於 2026-08-15，pod 3d19h 未重啟）→ 服務端與設定皆無變更
- [x] D10a. **經 gateway api_server 跑真實 agent 回合**（主代理主動驗證，非使用者回報）— ✅
  - `POST http://127.0.0.1:8642/v1/chat/completions`（`Authorization: Bearer $API_SERVER_KEY`）→ **`HTTP 200`，耗時 6.3s**
  - 模型成功呼叫 `bash` 工具並回報 **`hermes-upgrade-smoke-v0230`** ✅
  - DB 同步寫入：`sessions 133→134`、`messages 18,044→18,049`、`messages_fts = 18,049` = messages、`integrity ok` ✅
  - API 端點實測：`/health` `/v1/health` `/v1/models` `/v1/capabilities` `/v1/toolsets` `/api/sessions` **皆 200**；`/v1/skills` → **500（上游既有缺陷，見 §8）**；`/v1/models/hermes-agent` → 404（非既有路由，忽略）
  - skills 統計：CLI `hermes skills list` 正常 → **95 enabled、0 disabled**（21 hub-installed、1 builtin、73 local）；`find_all_skills()` 直接呼叫正常 → **96 筆** → **核心 skill 載入路徑完全不受影響**
- [x] D10b. **真實 Telegram 訊息往返驗證** — ✅ **使用者實測通過**（2026-11-06 07:58 台北時間）
  - 使用者在 Telegram DM（chat `830338761`）送出：「系統已經升級，做一下檢查」
  - **inbound**：`2026-11-06 07:58:35,791 INFO gateway.run: inbound message: platform=telegram user=Michael Lee chat=830338761 msg='系統已經升級，做一下檢查'`
  - **session 續接正確**：`Rehydrated persisted /model override for session=agent:main:telegram:dm:830338761: model=MiniMax-M3 provider=minimax` → **B1 單 gateway 架構下既有 session 與 model 偏好完整還原**
  - **agent 回合**：`response ready: platform=telegram … time=66.1s api_calls=4 response=2404 chars`
  - **outbound**：`2026-11-06 07:59:41,913 INFO gateway.platforms.base: [Telegram] Sending response (2404 chars) to 830338761`（送出後**無任何錯誤**）
  - **DB 同步**：`messages 18,052 → 18,059`（+7：user 1 / assistant 4 / tool 3），**`messages_fts = 18,059` = messages**，`integrity = ok`
  - **sessions = 134 未變**（正常）：Telegram DM 續接既有的 `20260708_133022_65a00a95` session，**不是新建 session** → 這正是 B1「一個 gateway 擁有每一場對話」的預期行為
  - **ERROR = 0**（開機後，排除我方 `/v1/skills` 探測）
- [ ] D11. **部署後 24h 觀察**：ERROR/CRITICAL 計數 = 0、`RESTARTS = 0`、記憶體趨勢平穩
  - 📌 **基線（2026-11-06 07:52 實測，開機 ~11 分鐘後）**：`pod startedAt = 2026-11-05T23:39:21Z`、`RESTARTS = 0`、`kubectl top` → CPU 15m / MEM **400Mi**、`gateway.log` 自開機起 ERROR = 2（**全為我方 `/v1/skills` 探測**，排除後 **0**）、CRITICAL = **0**
  - 觀察窗口到期：**2026-11-06 23:39Z**（開機 +24h）＝ 2026-11-07 07:39 台北時間
  - 📌 已排定 **durable cron `e5293376`**（one-shot，Nov 7 07:47）自動執行本項驗收並回填本工作表
  - 驗收指令：`kubectl --context n100-cf -n hermes top pod hermes-agent-f9496b576-wcxg8` + `kubectl --context n100-cf -n hermes exec hermes-agent-f9496b576-wcxg8 -- sh -lc 'awk "\$0 >= \"2026-11-06 07:41\"" /opt/data/logs/gateway.log | grep " ERROR \| CRITICAL " | grep -v "/v1/skills" | wc -l'`（期望 **0**）
  - ⚠️ 對照：全 log 的 **812 筆歷史 ERROR** 全部落在 `2026-10-07` ~ `2026-11-03`（每日 2–4 筆）；`2026-11-04` 起為 0

### Phase E — 收尾與文件歸檔

- [x] E1. 更新本工作表所有 checkbox 與實測數據 — ✅ Phase 0 / A / B / C / D1–D10a 已全部回填；D10b（使用者 Telegram 實測）與 D11（24h 觀察）待完成
- [x] E2. Commit + push `~/kubernetes/.../kustomization.yaml` — ✅ commit `61491d0`，push `b6b4ab4..61491d0 main -> main`
- [x] E3. 產出 `UPGRADE_LOG_v0.22.7_to_v0.23.0.md` — ✅ 檔名：`/Users/mlee/hermes/UPGRADE_LOG_v0.22.7_to_v0.23.0.md`
- [x] E4. 請示是否刪除舊備份 `~/backups/hermes-20261104/`（保留 `hermes-20261106/`）— ✅ **2026-11-06 使用者授權刪除**；刪除前複驗 `hermes-20261106` 完整性通過（integrity ok / messages 18,044 / sessions 133）

---

## 5. 風險總結表

| 風險項目 | 等級 | 緩解與驗證措施 |
|---|---|---|
| **單 gateway 架構變更**（B1）影響我們唯一的 Telegram 生產 Pod | 🟡 中 | v0.23.0 的重點就是修完 v0.22.0 以來「每個介面各跑一份 agent」的殘留問題；我們架構最單純。**D8 + D10 覆蓋** |
| **s6 監督樹重構**（B2）—— profile gateway 路徑改變、`015-supervise-perms` 重寫 | 🟡 中 | 我們只有單一 profile，`profile-gateways` 不會被註冊，但 s6 基礎變更仍生效 → **D8 專項驗證 `s6-svstat` / `hermes doctor` 權限** |
| **Telegram adapter 改動**（B4） | 🟢 低 | 13 行改動；D3 / D8 / D10 三重覆蓋 |
| **Dockerfile 自訂層衝突**（R1） | 🟢 **零風險** | 上游僅動 2 個註解 hunk，與我們 7 個自訂 hunk **零位置重疊**；`git merge-tree` 已證實 0 content conflict |
| **DB Schema / Config Schema 不可逆遷移** | 🟢 **無** | `SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3`、`_config_version = 52`、`hermes_state_*.py` 與 `config_migrations.py` 對上游 diff = **0 行** → 可秒退 `v0.22.7` |
| **殘留 skills 引用已移除的 `browser_*` 工具** | 🟢 低（非本次引入） | v0.22.7 已在同一狀態運行；決策 F = 本次不動，另開議題 |
| **GitHub Actions Fork 自動停用（HTTP 422）** | 🟡 中（外部啟發式） | 若觸發時回 422，直接請使用者在 `/actions` 點擊 re-enable 橫幅（Hard Rule 8） |
| **npm 漏洞** | 🟢 無（既有決策，且上游已修補） | v0.23.0 內含 undici 6.29.1 / 7.30.1 / zod 4.6.7 / fast-uri 3.1.9；容器 runtime 暴露面仍為 0 |
| **`GET /v1/skills` 恆回 500** | 🟢 **非本次引入**（上游既有缺陷） | 逐 tag 比對 `upstream-v0.22.7` 與 `upstream-v0.23.0` 程式碼**完全相同**；6 個上游 issue 自 2026-09-12 起全為 OPEN。我們無第一方消費路徑（核心 `find_all_skills()` 與 CLI `hermes skills list` 實測正常）→ **不修**，見 §8 |
| **節點共用檔案系統磁碟增長**（非 Hermes 造成） | 🟢 低 | `/opt/data` 僅 3.5G 且穩定；主因為 Sonarr 拉劇 75G + containerd 4 層 image。已回收 22G（592G→570G / 35%→33%）；v0.22.5–7 仍在 GHCR 可回拉，回滾路徑完好 |

---

## 6. npm 漏洞決策複查（2026-11-06）

| 檢查項目 | 2026-11-06 實測結果 |
|---|---|
| ① 觸發條件 Issue 狀態 | `#133435` **OPEN**、`#132924` **OPEN**、`#79021` **OPEN** → 條件未成立，**維持「不修」** |
| ② 上游 v0.23.0 lockfile 變化 | ✅ **上游已修補並納入本版**：`undici 6.29.0→6.29.1`、`undici 7.30.0→7.30.1`、`zod 4.6.5→4.6.7`、`fast-uri 3.1.8→3.1.9`（對應我們上一版記錄的「上游 undici/zod fix on main, e3085ec023」） |
| ③ 實際 K3s runtime 暴露面 | Photon sidecar 未啟用、Electron desktop 未部署 → **暴露面 = 0** |

> ✅ **本次升級會自動帶入上游的 npm 修補**（lockfile 隨基底更新），不需我們額外處理。

---

## 7. Go-Sign 確認區

- [x] §0.5 決策 **A**：目標版本 = **`v0.23.0`** — ✅ 2026-11-06 採納
- [x] §0.5 決策 **B**：自訂 commits = **原樣 cherry-pick**（6 個核心）+ Dockerfile 7 hunks — ✅ 2026-11-06 採納，全部零衝突
- [x] §0.5 決策 **C**：npm 漏洞 = **維持不修**（上游已於本版修補）— ✅ 2026-11-06 採納
- [x] §0.5 決策 **D**：FTS layout = **維持不動** — ✅ 2026-11-06 採納
- [x] §0.5 決策 **E**：先建 `20261106` 新備份，驗證完成後再請示清理 `20261104` 舊備份 — ✅ 2026-11-06 採納；備份已建立並驗證；`20261104` 已於 2026-11-06 經使用者授權刪除（回收 176MB）
- [x] §0.5 決策 **F**：`/opt/data/skills` 殘留（181 個）**本次不動**，另開議題 — ✅ 2026-11-06 採納
- [x] 使用者回覆「**Go**」（2026-11-06）後啟動 Phase 0 → A → B → C → D → E

---

## 8. 上游既有缺陷：`GET /v1/skills` 恆回 HTTP 500（**非本次升級引入，不修**）

> 部署後實測發現。已用 `git show` 逐 tag 比對 + GitHub issue 追查確認為**上游既有缺陷**，與 v0.23.0 無關。

### 8.1 現象

```
GET http://127.0.0.1:8642/v1/skills
→ HTTP 500
TypeError: find_all_skills() got an unexpected keyword argument 'include_editorial'
```

### 8.2 根因（上游 `upstream-v0.23.0` 原始碼）

| 檔案 | 行 | 內容 |
|---|---|---|
| `gateway/platforms/api_server.py` | 2388 | `find_all_skills(skip_disabled=False, include_editorial=True)` ← **呼叫端多傳了參數** |
| `tools/skills_tool.py` | 277 | `def find_all_skills(*, skip_disabled: bool = False) -> list[dict[str, Any]]:` ← **函式簽章沒有 `include_editorial`** |

### 8.3 判定為「既有缺陷」的三項證據

1. **逐 tag 逐位元組比對**：`upstream-v0.22.7` 的 `api_server.py:2388` 與 `skills_tool.py:277` **與 v0.23.0 完全相同** → 該 500 在我們升級前的 v0.22.7 上就已存在，**不是 v0.23.0 的 regression**。
2. **上游 `main` 仍存在**：缺陷在 `origin/main`（上游最新）同樣存在，尚未修復。
3. **上游 issue 群已回報且全部 OPEN**（2026-11-06 複查）：

| Issue | 標題 | 狀態 | 建立 |
|---|---|---|---|
| [#108967](https://github.com/NousResearch/hermes-agent/issues/108967) | [Bug]: GET /v1/skills always returns HTTP 500 | **OPEN** | 2026-09-12 |
| [#120831](https://github.com/NousResearch/hermes-agent/issues/120831) | TypeError: `_find_all_skills()` got an unexpected keyword argument `include_editorial` | **OPEN** | 2026-09-24 |
| [#124853](https://github.com/NousResearch/hermes-agent/issues/124853) | GET /v1/skills always returns 500 on v0.21.5 | **OPEN** | 2026-09-27 |
| [#132317](https://github.com/NousResearch/hermes-agent/issues/132317) | GET /v1/skills returns 500 — `_find_all_skills()` … unexpected keyword | **OPEN**（duplicate） | 2026-10-03 |
| [#142575](https://github.com/NousResearch/hermes-agent/issues/142575) | GET /v1/skills returns 500 - stale `include_editorial` kwarg after Collective Wisdom revert | **OPEN** | 2026-10-21 |
| [#148508](https://github.com/NousResearch/hermes-agent/issues/148508) | [Bug]: `/v1/skills` still returns HTTP 500 in latest Docker image (v0.22.6) | **OPEN** | 2026-11-03 |

> 最早回報於 **2026-09-12（v0.21.x）**，橫跨 4 個 minor 版本未被修。皆標註 `type/bug` + `comp/gateway`。

### 8.4 為什麼不修

| 理由 | 說明 |
|---|---|
| **不是本次引入** | 在 v0.22.7 即已存在 → 修它不屬於本次升級範圍，且會讓我們的分支與上游產生無謂分歧 |
| **無第一方消費路徑** | 我們的部署是 server-only（K3s 容器），**沒有任何第一方元件呼叫 `/v1/skills`**：Desktop 不部署、webapp 未啟用、CLI 走的是 `hermes skills list` 而非 HTTP |
| **核心 skill 載入完全正常** | 實測 `find_all_skills()` 直接呼叫 → **96 筆正常回傳**；CLI `hermes skills list` → **95 enabled / 0 disabled**（21 hub-installed + 1 builtin + 73 local）。受影響的**只有那 1 個 HTTP 端點** |
| **上游未修前動它會產生維護負擔** | 下次 rebase/cherry-pick 上游時必然衝突，且我們要替上游承擔 correctness 責任 |

### 8.5 實際影響

- **零功能影響**：我們的 Telegram bot 走 gateway 內部路徑，不經 `/v1/skills`。
- **僅 2 筆 ERROR log**：開機後的 2 筆 ERROR 全部來自**我方自己的 `/v1/skills` 探測**（07:45:13、07:45:25）。排除我方探測後 = **ERROR 0 / CRITICAL 0**。
- **對外揭露面**：`/v1/skills` 需 `API_SERVER_KEY` 認證；我們的 api_server 未對外公開（僅 Pod 內 `127.0.0.1:8642`）。

> 📌 若日後上游修復，本分支 rebase 時自然帶入；若我們先手動修，未來 rebase 必衝突 —— 故**保留原狀**。

---

## 9. Image stamp 與分支 HEAD 的差異（有意保留）

| 項目 | SHA | 說明 |
|---|---|---|
| 已部署 image 的 build stamp | `3d6cda5e0d` | 部署當下的分支 HEAD（GHCR run `42129150541` 的 `headSha`） |
| 分支現況 HEAD（`my-config-v0.23.0`） | `ae99ed9748` | 差 3 個 commit（全為 docs） |

差異內容**全部為文件**：`docs/worksheet-upgrade-hermes-v0.23.0-20261106.md` 的執行結果回填、`UPGRADE_LOG_v0.22.7_to_v0.23.0.md`。**runtime 程式碼零差異** —— 重新建置產出的 image 與現行 image 的執行行為完全相同。

**決策：不重新建置、不重新部署**（與 v0.22.7 升級的 §7 決策一致）。理由：

1. 現行部署已通過完整線上驗證（D1–D10a 全綠、排除我方探測後 0 ERROR）；
2. 重新建置會覆寫同一個 `v0.23.0` tag（Hard Rule 6 的既定行為），導致新 digest、需重新 pull + rollout + 重新驗證，**純粹為了讓 stamp 對齊一個文件 commit 而承擔風險**；
3. D11 的 24h 穩定性觀察窗口不應被無謂重置。

若日後因故需要讓 image stamp 與分支 HEAD 完全對齊，重跑同一條指令即可：

```bash
gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent \
  --ref my-config-v0.23.0 -f tag_name=v0.23.0 -f platforms=all
```

---

## 10. 對「Hermes 容器內自我檢查報告」的獨立稽核（2026-11-06）

> 容器內的 Hermes agent 主動向使用者提問四項疑點。逐項以**獨立量測**覆核後：1 項成立且已處理、2 項為誤判、1 項成立但非本次升級引入。完整證據見 `UPGRADE_LOG_v0.22.7_to_v0.23.0.md` §11。

| Hermes 的指控 | 稽核判定 | 依據 |
|---|---|---|
| 「磁碟 2 天 +83G」 | ✅ **成立，但與 Hermes 無關**（已處理） | `/opt/data` 全部資料僅 **3.5G**；真正來源是 Sonarr 寫入 `/data/services/k8s-media/tv/` 的 75G「Pursuit of Jade」+ containerd 4 層 hermes image。已 `crictl rmi --prune` 回收 **22G**（592G/35% → 570G/33%），v0.22.5–7 仍在 GHCR 可回拉，0 pod 受影響 |
| 「doctor 三個 workspace 都有顯示 ＝ node_modules 狀態改變」 | ❌ **誤判** | `hermes_cli/doctor_tools.py` 兩 tag **零 diff**；gate 只是 `PROJECT_ROOT/node_modules` 存在，`web/`、`ui-tui/` 的 node_modules 在 image 中本就不存在。workspace 列是 npm 以 `--workspace` 過濾**根 lockfile** 的結果，非已安裝樹掃描 |
| 「npm 真實 23 個（2 high / 21 moderate）」 | ⚠️ **數字為跨 scope 聚合** | 單 scope 實測：root `--workspaces=false` = **10 moderate + 0 high**（v0.22.7 為 10 moderate + **1 high**，上游已修）、`--workspace web` = 3 moderate + 0 high、`--workspace ui-tui` = 0。殘餘 2 high（`follow-redirects`←axios、`joi`←wait-on）lockfile 皆標 `dev: true` → **runtime 暴露面 = 0** |
| 「MEMORY.md 超限（2382/2200）」 | ⚠️ **成立，但 v0.22.7 時期既有** | `memory_char_limit` 預設 2200 兩 tag 未變；`tools/memory_tool*.py` **零 diff**；檔案 mtime 為 **2026-10-24**。→ 交由容器內 Hermes 自行精簡（截至稽核時尚未執行，仍 2382 chars） |
| 「Hermes Relay drained 2 orphaned scope(s)」 | ✅ **良性既有現象** | `errors.log` 中 2026-10-24 與 **2026-11-04（當時還是 v0.22.7）** 已有同樣紀錄，每回合一次，非新故障 |
| 「`/v1/skills` 500 ＝ v0.23.0 官方 bug」 | ✅ 結論一致，**措辭需校正** | 兩個 tag 程式碼逐位元組相同 + 上游 6 issue 自 2026-09-12 起 OPEN → 屬**上游既有缺陷**，**非 v0.23.0 回歸**（見 §8） |

### 10.1 稽核後剩餘待辦

- [ ] 容器內 Hermes 精簡 `/opt/data/memories/MEMORY.md`（2382 → ≤2200 chars）— 由 Hermes 自行執行，**不影響升級驗收**；本次不代為改寫（該檔為 agent 自身記憶，非本工作表範疇）
- [ ] D11 24h 觀察驗收 — durable cron `e5293376`，2026-11-07 07:47 觸發（自動檢查 RESTARTS / 記憶體趨勢 / ERROR-CRITICAL / `messages == messages_fts`）
