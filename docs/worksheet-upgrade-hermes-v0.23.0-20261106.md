# Hermes Agent 升級工作表：v0.22.7 → v0.23.0

- **目標版本**：`v0.23.0`（官方 commit `2bd378ed1b8d6bf2192cb26e0a55ff3091e6bd19`，2026-11-05 發佈，*"The Hearth Release"*）
- **升級前版本**：`my-config-v0.22.7`（HEAD `4d7973ece9`，基於官方 `v0.22.7` = `b200f5bc60e3`）
- **新分支**：`my-config-v0.23.0`（基底 = `upstream-v0.23.0`，**不是**本地 `v0.23.0` tag）
- **Remote**：`origin` = 官方（NousResearch）、`kuniakil` = 個人 fork（⚠️ 與 OpenClaw 相反）
- **發布模型**：`my-config-v0.23.0` 分支為 source of truth，由 `ghcr-publish.yml`（dispatch input **`tag_name`**）建置 `ghcr.io/kuniakil/hermes-agent:v0.23.0`
- **目前上線版本**：`v0.22.7`（K3s n100，pod `hermes-agent-58b98d987d-5nhh7`，Running，RESTARTS 0，age 47h）
- **狀態**：⏳ **待 Go-Sign**（本檔為 Phase 1 產出，未做任何修改）
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

- [ ] 0.1 確認無使用中：查 24h 內訊息數與最後一則時間（**預檢實測：`msgs_24h = 0`，最後一則 `2026-11-04 08:04:35` 台北**）
- [ ] 0.2 記錄升級前基線（部署後不得下降）：
  - **2026-11-06 預檢基線**：`sessions = 133`、`messages = 18,044`、`state.db = 184,508,416 B (176.0MB)`、`integrity = ok`
  - `session_admissions = 11`、`worker_executions = 0`、`worker_receipts = 0`
  - Pod：`hermes-agent-58b98d987d-5nhh7`，`Running`，`RESTARTS 0`，age `47h`
- [ ] 0.3 記錄 FTS 現況（維持 opt-in，本次不動）— `FTS_STORAGE_VERSION = 3` 於 v0.22.7 / v0.23.0 皆相同
- [ ] 0.4 記錄 config 基線：**實測 `_config_version: 52`**、`model.default: MiniMax-M3`、`terminal.backend: local`、`toolsets: [hermes-cli]`、`mcp_servers.camofox`（HTTP）、`browser.cdp_url: ''`
- [ ] 0.5 **備份 DB（`.db` + `.db-wal` + `.db-shm`，缺一不可）**：建立於 `~/backups/hermes-20261106/`
  - 前置：於 Pod 內執行 `PRAGMA wal_checkpoint(TRUNCATE)` → `(0,0,0)`
  - 傳輸：**tar streaming**（`kubectl exec -- tar -cf - -C /opt/data …`）— ⚠️ 不要用 `kubectl cp`，176MB 會 websocket 中斷（`close 1006`）
  - 產物：`state.db`、`state.db-wal`、`state.db-shm`、`config.yaml`
- [ ] 0.6 驗證備份完整性：`sqlite3 ~/backups/hermes-20261106/state.db "SELECT COUNT(*) FROM messages; PRAGMA integrity_check;"` → 預期 `18044` + `ok` ✅
- [ ] 0.7 盤點既有備份並記錄：`~/backups/hermes-20261104/`（v0.22.7 升級快照，176MB）— 待驗證完成後再請示刪除（決策 E）

### Phase A — 建立分支 + Purge Workflows + 移植自訂 Commits

- [ ] A0. **取得使用者 Go-Sign**（確認 §0.5 決策 A–F）
- [ ] A1. `git fetch origin refs/tags/v0.23.0:refs/tags/upstream-v0.23.0 --no-tags`（✅ 已完成，commit `2bd378ed1b8d6bf2192cb26e0a55ff3091e6bd19`）
- [ ] A2. `git checkout -b my-config-v0.23.0 upstream-v0.23.0`
- [ ] A3. Purge 官方 workflows，只留我們的 `ghcr-publish.yml`：
  ```bash
  find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete
  git checkout my-config-v0.22.7 -- .github/workflows/ghcr-publish.yml
  git add .github/workflows
  git commit -m "chore(ci): purge official CI workflows; retain only ghcr-publish.yml"
  ```
  - 預期：上游 **58 個** workflow → 保留 **1 個**
- [ ] A4. Cherry-pick 零衝突自訂 commits：`45c07a7c6f`、`28607c420f`、`faa80374cc`、`20264ca395`、`a8491124a7`
- [ ] A5. **Dockerfile 自訂層手動移植 7 hunks**（§3.1）— 對照 `git diff upstream-v0.23.0 my-config-v0.22.7 -- Dockerfile`
- [ ] A6. 確認 `git diff upstream-v0.23.0 HEAD -- Dockerfile | grep -c '^@@'` = **7**，且 7 個自訂標記全數存在
- [ ] A7. Cherry-pick 24 個歷史文檔 commits + 提交本工作表
- [ ] A8. **tracked-but-ignored 遺失偵測**（比對 `git ls-files` 舊/新）— 目標 **LOST = 0 檔**
- [ ] A9. 確認 `git log --oneline upstream-v0.23.0..HEAD` **完全線性**（merge commits = 0）

### Phase B — 本地輕量驗證（嚴禁跑重型測試或本機 docker build）

- [ ] B1. `git status` 乾淨
- [ ] B2. `.github/workflows/` 僅有 `ghcr-publish.yml`
- [ ] B3. 關鍵檔案完整性：`docker/entrypoint-ssh.sh` / `docker/stage2-hook.sh` / `docker-compose.yml` / `AGENTS.md` / `.env.example` 存在且行數合理
- [ ] B4. `ghcr-publish.yml` dispatch input = **`tag_name`** + `platforms`
- [ ] B5. `hermes_state_common.py` 的 `SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3`
- [ ] B6. `hermes_cli/config_defaults.py` 的 `_config_version = 52`
- [ ] B7. `.env` 仍在 working tree 且未被 git track
- [ ] B8. **上游 Dockerfile 僅註解變更** — `git diff upstream-v0.22.7 upstream-v0.23.0 -- Dockerfile` 逐行確認（實錘 R1）

### Phase C — 推送 Fork + 觸發 GHCR Build

- [ ] C1. `git push -u kuniakil my-config-v0.23.0`
- [ ] C2. `gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v0.23.0 -f tag_name=v0.23.0 -f platforms=all`
  - 若回 **HTTP 422**（Actions has been disabled）→ **不要重試、不要清 cache**，請使用者在 `https://github.com/kuniakil/hermes-agent/actions` 點 re-enable 橫幅
- [ ] C3. 驗證觸發的 run：`event=workflow_dispatch`、`headBranch=my-config-v0.23.0`、`headSha=**我們的 commit**`（非上游 `2bd378ed1b`）
- [ ] C4. **派背景子代理**監控 `gh run watch`（Hard Rule 9；主迴圈不得阻塞）
- [ ] C5. 驗證 multi-arch image tags：`ghcr.io/kuniakil/hermes-agent:v0.23.0` 與 `latest` 皆為 multi-arch index（`linux/amd64` + `linux/arm64`）
- [ ] C6. 確認 install stamp：`baseVersion` = `v0.23.0`（我們的 workflow 以 `--base-version "$TAG"` 傳入，`write_install_stamp.py` 的 CLI flags 在 v0.23.0 **完全未變**）

### Phase D — K3s 部署 + 全方位驗證

- [ ] D1. 更新 `~/kubernetes/hermes/overlays/n100/kustomization.yaml`：`newTag: "v0.22.7"` → **`"v0.23.0"`**，commit + push
- [ ] D2. `kubectl apply -k ~/kubernetes/hermes/overlays/n100`；**派背景子代理**監控 rollout
  - 期望：新 pod `Running` / `ready=true` / `RESTARTS 0`，image digest = 新 v0.23.0
- [ ] D3. **冒煙測試**（對照 v0.22.7 基線）：
  - Python `3.14.9`、`openai 2.54.0`、`pydantic 2.14.1`、`nemo_relay 0.11.0`
  - Node.js / npm 版本、Debian base = `13.7 (trixie)`
  - 3 種 locale（`C.utf8` / `en_US.utf8` / `zh_Tw.utf8`）全在
  - `sshd` / `rsync` / `tini` / `tmux` / `ffmpeg` 全在
  - Chromium binary 存在
  - Telegram connected、**0 ERROR / 0 CRITICAL**
- [ ] D4. **版本確認**：`hermes --version` = **`Hermes Agent vv0.23.0 (…) · upstream <我們的 short_sha>`**
- [ ] D5. **DB Schema 檢查**：`PRAGMA integrity_check` = `ok`；`SCHEMA_VERSION = 32`、`FTS_STORAGE_VERSION = 3` 零變更
- [ ] D6. **資料完整性**：`sessions >= 133`、`messages >= 18,044`（零損失）、`messages_fts` 計數 = messages
- [ ] D7. **Config 驗證**：`_config_version` 維持 **52**（無遷移）；`model.default: MiniMax-M3`、`terminal.backend: local`、`toolsets: [hermes-cli]`、`mcp_servers.camofox` 原封不動；`_left_core_used` **未出現**（= 不觸發外掛自動安裝）
- [ ] D8. **開機與穩定性驗證**（★ 本次重點，涵蓋 B1/B2）：`RESTARTS = 0`
  - `gateway.log` 開機段：`✓ telegram connected`、`api_server connected`、`Gateway running with 2 platform(s)`、`Channel directory built`
  - **B2 專項**：s6 slot 可被 hermes 使用者查詢（`s6-svstat` / `hermes doctor` 無 EACCES）
  - **B2 專項**：`02-reconcile-profiles` 執行無錯誤（單 profile，預期不註冊任何 profile-gateways service）
  - 關閉舊 Pod 為 graceful（`Shutdown phase: all adapters disconnected`）
- [ ] D9. **Camofox MCP 驗證**：端口 8080 通訊正常（帶 token 的 `initialize` → HTTP 200）
- [ ] D10. **真實 Telegram 訊息往返驗證** — 需使用者實測回報（`messages` +N、`sessions` +1、`messages_fts` 同步、0 ERROR）
- [ ] D11. **部署後 24h 觀察**：ERROR/CRITICAL 計數 = 0、`RESTARTS = 0`、記憶體趨勢平穩

### Phase E — 收尾與文件歸檔

- [ ] E1. 更新本工作表所有 checkbox 與實測數據
- [ ] E2. Commit + push `~/kubernetes/.../kustomization.yaml`
- [ ] E3. 產出 `UPGRADE_LOG_v0.22.7_to_v0.23.0.md`
- [ ] E4. 請示是否刪除舊備份 `~/backups/hermes-20261104/`（保留 `hermes-20261106/`）

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

- [ ] §0.5 決策 **A**：目標版本 = **`v0.23.0`**
- [ ] §0.5 決策 **B**：自訂 commits = **原樣 cherry-pick**（8 個核心）+ Dockerfile 7 hunks 手動移植
- [ ] §0.5 決策 **C**：npm 漏洞 = **維持不修**（上游已於本版修補）
- [ ] §0.5 決策 **D**：FTS layout = **維持不動**
- [ ] §0.5 決策 **E**：先建 `20261106` 新備份，驗證完成後再請示清理 `20261104` 舊備份
- [ ] §0.5 決策 **F**：`/opt/data/skills` 殘留（181 個）**本次不動**，另開議題
- [ ] 使用者回覆「**Go**」後啟動 Phase 0 → A → B → C → D → E
