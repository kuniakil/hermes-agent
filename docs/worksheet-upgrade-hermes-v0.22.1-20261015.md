# Hermes Agent 升級工作表：v0.22.0 → v0.22.1

- **目標版本**：`v0.22.1`（commit `297552a9d6`，2026-10-14 發佈，標題 "rc.5-v0.22.1"）
- **當前版本**：`my-config-v0.22.0`（HEAD `f3a9343213`，基於官方 `v0.22.0` = `e06df9c2ea`）
- **新分支**：`my-config-v0.22.1`
- **Remote**：`origin` = 官方（NousResearch）、`kuniakil` = 個人 fork
- **發布模型**：`my-config-v0.22.1` 分支為 source of truth，由 `ghcr-publish.yml`（dispatch input **`tag_name`**）建置 `ghcr.io/kuniakil/hermes-agent:v0.22.1`
- **狀態**：✅ **已完成升級並部署**（2026-10-15）。GH Actions Run **38691266688** 全部成功；n100 已 rollout 至 `v0.22.1`，冒煙測試全數通過
- **最終 HEAD**：`81bc37f7965ffd055c966d05bc8b06237977c884`
- **GHCR digest**：`sha256:c98934da35a5ea6e26930b6cf5ed843b9b4ca0da877e0aeb5d90f9d33d3776f6`
- **升級紀錄**：`UPGRADE_LOG_v0.22.0_to_v0.22.1.md`
- **日期**：2026-10-15

---

## 1. 官方 Release Notes 稽核（v0.22.1）

官方自稱「patch release」，但**實際規模不小**：2,216 commits / **2,170 files / +190,328 −49,590**。Full Changelog 為 `v0.22.0...rc.5-v0.22.1`，`v0.22.1` 已驗證為 `v0.22.0` 的線性後代（`git merge-base --is-ancestor` = true），**無 fork/rebase 拓撲問題**。

### 1.1 主題：canonical session authority 大重構

本次核心是「session authority / mutation receipt」架構的收斂——把原本散落在 CLI、Desktop、TUI、ACP、REST、Bot relay 的所有 session 寫入路徑，統一收斂到 **canonical durable storage + mutation receipts + owner bridge**。

| 面向 | 代表條目 |
|---|---|
| 統一寫入層 | `Centralize durable session admissions in canonical storage`、`Route REST imports and deletion through mutation receipts`、`Commit sidebar edits with canonical mutation receipts` |
| Worker 生命週期 | 新增 `hermes_state_worker_lifecycle.py`、`hermes_state_worker_compression.py`、`hermes_state_worker_context.py`（共 +3,723 行 state 層） |
| Desktop / TUI / Ink | `Attach Desktop local launches to canonical gateway`、`Bind Ink sessions and controls to canonical authority envelopes`、`Route native CLI and ACP actions through prepared controls` |
| Bot relay | `Expose profile-scoped Bot relay mailbox RPCs`、`Migrate queued Bot mailbox identities without replaying claims` |
| 本機啟動路由 | `Route normal classic and one-shot launch through the gateway`、`Define frozen local session launch policy` |
| MCP / ACP | `Expose verified canonical ACP editor MCP attachment`、`Isolate execution-owned MCP registry overlays` |

### 1.2 與我們部署相關的具體修正（Bug Fixes）

| 官方條目 | 對我們的意義 |
|---|---|
| `Compression): fallback summaries, multiline setup notes and parallel loads keep skill markers right`（本 tag 的 HEAD commit `297552a9`） | 壓縮後 skill marker 正確性修正 — 我們 container-only（無 UI session picker）但有壓縮流程 🟢 |
| `Mcp): preserve server deadlines through outer tool execution` | MCP 逾時不再被外層吞掉 🟢 |
| `Plugins): honor portable per-server call deadlines` | 同上 🟢 |
| `Agent): rewrite split tool ids before Mistral sees them` | Mistral 工具 id 修正 🟢 |
| `Profiles): align model seed with provider resolution` / `inherit canonical and legacy custom endpoints` | profile 模型解析修正 🟢（我們單 profile） |
| `Drop the VPN/proxy advice from the CDN-block message` | 訊息文字 🟢 |
| `Doctor: clarify Docker npm audit remediation` | 與我們 §8.3 npm 決策相關 🟢 |
| `Deps: bump the WhatsApp bridge lock past its npm-audit findings` | **官方本次修了一個 npm audit 問題**（我們未部署 whatsapp-bridge）🟢 |
| `Gateway: gateway ensure starts on a systemd host whose user bus is unreachable` | systemd host 開機 🟢（我們 K3s） |
| `Cron): Bot Chat delivery creates the missing Bot Chat instead of failing the run` | cron 🟢 |
| `Desktop: update notes keep full text, re-read merged PRs per check, respect custom branches` | Desktop 🟢（我們不用 Desktop） |

### 1.3 Breaking Changes / Deprecations 稽核

**Release Notes 中沒有 `Breaking Changes` 章節**，也沒有 Deprecation 章節。逐項掃過全篇的 `breaking|migrat|upgrade|deprecat|removal|⚠` 關鍵字，命中的全部是**內部 worker/bot 資料搬遷**（queued identities、worker rotation、fixtures、callbacks），無一面向使用者設定或 CLI/JSON 介面：

- `Migrate queued Bot mailbox identities without replaying claims` / `Recover bot mailbox receipts and migrate queued inputs at owner startup` → Bot mailbox **內部資料搬遷**，code 自動完成
- `Migrate worker rotation automation inside owner publication` / `Migrate cron lifecycle invariants to canonical owner execution` → **cron/worker 內部重構**
- `Retain legacy session writers during reader migration` / `Retain explicit verified deletion after read-only export migration` → 明確標示**保留 legacy 相容路徑**
- `Retain native media and context before durable admission` / `Import drained legacy admissions atomically with unknown recovery` → 舊資料自動匯入

> 唯一需要留意的 interface 變更是 **tool 改名**（`todo`→`todo_list` 等）——但那是 **v0.22.0** 已發生的變更，v0.22.1 沿用；且我們無自訂 plugin。

### 1.4 Dependency / Runtime 稽核（機器可讀真相）

| 項目 | v0.22.0 | v0.22.1 | 判定 |
|---|---|---|---|
| `pyproject.toml` `version` | `0.0.0` | `0.0.0` | 無動態版本號；實際版本由 tag 決定 |
| `requires-python` | `>=3.11,<3.15` | `>=3.11,<3.15` | **未變** → 我們 `python 3.14.7` 相容 |
| `package.json` `version` | `1.0.0` | `1.0.0` | 未變 |
| `pm/lock.json` | — | — | **上游零 diff** → pm 套件版本全數不變（`agent-browser 0.26.0` 等） |
| `mcp` extra | `httpx2==2.7.0` | `httpx2==2.12.0` | ↑ 升版（非我們修改範圍） |
| `computer-use` extra | `httpx2==2.7.0` | `httpx2==2.12.0` | ↑ |
| `dev` extra | `httpx2==2.7.0` | `httpx2==2.12.0` | ↑（僅 CI） |
| `uv.lock` | — | 34 行 | 對應 httpx2 升版 + `httpx2-jsfetch` 新 indirect |
| 根 `package-lock.json` `overrides` | `{}` | `{}` | **位元組相同** → §8.3 npm 決策前提未變 |
| 根 `package-lock.json` 其他 | `js-yaml 4.3.1` / `yaml 2.8.1` / `vitest 4.1.10` | `js-yaml 4.3.2` / `yaml 2.9.1` / `vitest 4.1.11` / **新增 `ws 8.21.1`** | 官方例行 bump |
| `scripts/whatsapp-bridge/package-lock.json` | — | +169 −121 | 官方刻意 bump 過 npm audit |

### 1.5 ⚠️ Schema 版本判定（決定是否不可逆）

| 常數 | v0.22.0 | v0.22.1 |
|---|---|---|
| `hermes_state_common.py:283 SCHEMA_VERSION` | **31** | **31** |
| `hermes_state_common.py:306 FTS_STORAGE_VERSION` | **3** | **3** |
| `hermes_state_dbfile.py:408 RETIRED_GENERATION_MANIFEST_VERSION` | **1** | **1** |

**結論：`SCHEMA_VERSION` 未變（31 → 31）。本次新增的 worker lifecycle / mutation receipt 資料表由既有 migration 機制建立，不需人工 DB 遷移，回滾不需要預先複製 DB。**

> 官方有 commit `State): keep FTS migration fixtures on historical versions` 與 `Verify runtime schema upgrades and genuine SQLite full rollback`——那是**測試強化**，不是 schema 號碼變更。兩邊號碼相同即為證。

✅ **升級路徑為 lean（精簡路徑），回滾成本低，無強制 DB 備份前置條件。**

---

## 2. Diff 稽核（`upstream-v0.22.0..upstream-v0.22.1`）

### 2.1 關鍵路徑

| # | 路徑 | 上游變更 | 影響 |
|---|---|---|---|
| 1 | **`Dockerfile`** | **1 hunk / +6 行**：`--cache /opt/hermes/uv-cache \` + 5 行註解 | 🔴 **唯一實質衝突點**，見 §3 |
| 2 | `docker/`（`stage2-hook.sh` 等） | **零 diff** | 🟢 我們的 `docker/stage2-hook.sh` 乾淨沿用 |
| 3 | `docker/entrypoint-ssh.sh` | 上游**不存在此檔**（我們自創） | 🟢 乾淨 |
| 4 | `docker-compose.yml` | 零 diff | 🟢 沿用我們版本 |
| 5 | `AGENTS.md` | 零 diff | 🟢 Mac host 保護規則保留 |
| 6 | `.env` | 零 diff | 🟢 |
| 7 | `.github/workflows/` | **37 檔 M/A** | 🟢 依 Purge 規則全刪，只留我們的 `ghcr-publish.yml` |
| 8 | `pyproject.toml` / `uv.lock` | httpx2 升版 | 🟢 非我們修改範圍 |
| 9 | `package-lock.json` ×2 | 例行 bump + whatsapp 修 audit | 🟢 見 §6 |
| 10 | 其餘 ~2,130 檔（agent/、gateway/、hermes_state_*、tools/、apps/、ui-tui/、plugins/、website/ 等） | 官方程式碼 | 🟢 隨版帶入 |

### 2.2 衝突面計算

```
自定義 commit 觸及：65 檔
上游 v0.22.0→v0.22.1 變更：2,170 檔
重疊：37 檔  ← 全部是 .github/workflows/（我們分支皆為 DELETED → 依 Purge 規則直接刪，不需解決）
        1 檔  ← Dockerfile（唯一實質衝突）
```

### 2.3 🔴 Dockerfile 衝突分析（唯一需人工處理的點）

上游 hunk：

```diff
@@ -280,7 +280,13 @@ FROM runtime_base AS python_deps
 COPY pyproject.toml uv.lock ./
 RUN touch ./README.md
+# --cache puts uv's cache at /opt/hermes/uv-cache, the seed path that
+# pm.packages.uv_cache_dir() merges into $HERMES_HOME/cache/uv on first use.
+# ...
 RUN python3 -m pm.build_env --source /opt/hermes --python /usr/local/bin/python3 \
+    --cache /opt/hermes/uv-cache \
     --out /opt/hermes/.venv --no-install-project --sealed --record-selection \
```

我們的第 4 處自訂補丁：

```diff
@@ -283,7 +296,8 @@ RUN touch ./README.md
 RUN python3 -m pm.build_env --source /opt/hermes --python /usr/local/bin/python3 \
     --out /opt/hermes/.venv --no-install-project --sealed --record-selection \
     --extra all --extra messaging --extra otlp --extra anthropic --extra bedrock \
-    --extra azure-identity --extra matrix --extra google-chat
+    --extra azure-identity --extra matrix --extra google-chat \
+    --extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa
```

**兩 hunk 行範圍重疊（上游 280–292 vs 我們 283–290）→ `cherry-pick` 必在此報衝突。**

**處置方式（不盲選 ours/theirs）：** 兩個改動**語義不相衝**，目標是兩者並存：

```dockerfile
RUN touch ./README.md
# --cache puts uv's cache at /opt/hermes/uv-cache, the seed path that
# pm.packages.uv_cache_dir() merges into $HERMES_HOME/cache/uv on first use.
# Do not leave the cache at its default: HERMES_HOME is not set yet in this
# stage, so the default is /root/.hermes/cache/uv, which nothing reads. A plugin
# install then runs with an empty cache and builds python-olm from source.
RUN python3 -m pm.build_env --source /opt/hermes --python /usr/local/bin/python3 \
    --cache /opt/hermes/uv-cache \
    --out /opt/hermes/.venv --no-install-project --sealed --record-selection \
    --extra all --extra messaging --extra otlp --extra anthropic --extra bedrock \
    --extra azure-identity --extra matrix --extra google-chat \
    --extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa
```

→ **以 `upstream-v0.22.1` 的 Dockerfile 為基底，套用我們 8 處自訂補丁**（見 §4 清單），而非 cherry-pick 該 commit。

---

## 3. 需攜帶的自定義補丁（8 處，全在 Dockerfile + 4 個獨立檔）

我們的 Dockerfile 對上游的差異共 **8 個 hunk**：

| # | 行 | 內容 |
|---|---|---|
| 1 | `@@ -75,8 +75,21 @@` | apt：`openssh-server` `rsync` `locales`；`mkdir /var/run/sshd` + `ssh-keygen -A`；`locale-gen`（`C.UTF-8` / `en_US.UTF-8` / `zh_TW.UTF-8`）+ `/etc/default/locale` + `/etc/profile` + `.bashrc` |
| 2 | `@@ -172,7 +185,7 @@` | `useradd ... -s /bin/bash hermes` |
| 3 | `@@ -209,8 +222,8 @@` | pm ensure + symlink 加入 **`agent-browser`** |
| 4 | `@@ -283,7 +296,8 @@` | `build_env` extras：`edge-tts` `firecrawl` `dingtalk` `feishu` `exa` 🔴 **與上游重疊** |
| 5 | `@@ -348,6 +362,11 @@` | `/tmp/.npm-cache`（sticky bit 1777） |
| 6 | `@@ -361,6 +380,10 @@` | `/root/.npm` `/root/.cache` chown 10000 |
| 7 | `@@ -454,6 +477,9 @@` | `ENV HOME=/opt/data` |
| 8 | `@@ -479,6 +505,10 @@` | `COPY docker/entrypoint-ssh.sh`（Zeabur 相容 shim） |

自訂 commit 清單（`upstream-v0.22.0..my-config-v0.22.0`，13 個）：

| # | commit | 說明 | 處置 |
|---|---|---|---|
| 1 | `abb31ba773` | `chore(ci)`:purge 官方 CI | 🔁 重做（在新分支 purge） |
| 2 | `9e41629666` | `fix(docker)`:還原 `docker/entrypoint-ssh.sh` | ✅ cherry-pick |
| 3 | `63e50c9885` | `chore`:帶入 `docker-compose.yml` | ✅ |
| 4 | `8648243390` | `chore`:Mac host 資源限制規則 → AGENTS.md | ✅ |
| 5 | `9c0eebd450` | `fix(docker)`:stage2 SSH 設定 + npm cache | ✅ |
| 6 | `4f88c09175` | `feat(docker)`:re-port custom layer（8 處補丁） | 🔴 **手動重做**（見 §2.3） |
| 7 | `13481ae63a` | `chore`:bump HERMES_IMAGE → v0.21.7（**修改 `.env`**） | ❌ **誤判為跳過** |
| 8 | `42a144db61` | `docs`:v0.21.7 升級紀錄 + 工作表 | ✅（歷史文檔） |
| 9 | `0bd6084e8d`、`ab0fd082b1`、`c0888ada33`、`8b28a5d1a5` | `docs`:v0.22.0 驗證/紀錄 | ✅（歷史文檔） |
| 9b | `b6ca87c8d0` | `chore`:bump HERMES_IMAGE → v0.22.0（**修改 `.env`**） | ❌ **誤歸類為 docs** |
| 9c | `f3a9343213` | `docs`:npm 漏洞附錄 | ✅（歷史文檔） |

> 🔴 **執行後修正**：#7 與 #9b **兩個 commit 修改的都是 `.env`**（非 docs）。當時把 #9b 誤歸類為「docs 歷史文檔」而標記為「⏭ 跳過（改由 §5 處理）」，導致 **`.env` 未被帶入 `my-config-v0.22.1`**。
> 因 `.env` 在 `my-config-v0.22.0` 是**被 git 追蹤**的，`git checkout -b ... upstream-v0.22.1` 時 git 直接將其**從 working tree 刪除**。
> 影響僅限本機 `docker compose` 路徑（k8s 走 overlay `newTag`，不受影響）。修復方式見 `UPGRADE_LOG_v0.22.0_to_v0.22.1.md` §6.1。

---

## 4. 執行步驟 checklist

### Phase A — 建分支 + Purge + 攜帶自定義
- [x] A1. `git fetch origin refs/tags/v0.22.1:refs/tags/upstream-v0.22.1 --no-tags`
- [x] A2. `git checkout -b my-config-v0.22.1 upstream-v0.22.1` → `297552a9d6`
- [x] A3. Purge 官方 workflows，只留我們的 `ghcr-publish.yml`（55 → 1，blob `efa2eac12` 與 v0.22.0 相同）→ `1fc47d42ac`
- [x] A4. cherry-pick commit #2、#3、#4、#5（**4 個全部零衝突**）→ `08fa3fc96e` `1e87666e04` `b85ee26ccb` `b4e66c5ecb`
- [x] A5. **手動重做 Dockerfile 8 處自訂補丁** → `be2a5bab24`（+35 −5）
  - [x] A5.1 apt：`openssh-server` `rsync` `locales` + `ssh-keygen -A` + locale-gen（C / en_US / zh_TW）
  - [x] A5.2 `useradd -s /bin/bash`
  - [x] A5.3 pm ensure + symlink 加 `agent-browser`
  - [x] A5.4 `build_env --extra edge-tts firecrawl dingtalk feishu exa`（**保留上游 `--cache /opt/hermes/uv-cache` 行**）
  - [x] A5.5 `/tmp/.npm-cache` 1777
  - [x] A5.6 `/root/.npm` `/root/.cache` chown 10000
  - [x] A5.7 `ENV HOME=/opt/data`
  - [x] A5.8 `COPY docker/entrypoint-ssh.sh`
- [x] A6. 複驗 `git diff upstream-v0.22.1 HEAD -- Dockerfile` = **恰好 8 個 hunk**、且含 `--cache /opt/hermes/uv-cache`
- [x] A7. 確認 `--record-selection` 仍在（Dockerfile:303）

### Phase B — 本地輕量驗證（不做重測 / 不本機 build）
- [x] B1. `git status` 乾淨
- [x] B2. `git diff upstream-v0.22.1 HEAD -- Dockerfile | grep -c '^@@'` → **8**
- [x] B3. `.github/workflows/` 僅 `ghcr-publish.yml`
- [x] B4. `openssh-server` / `edge-tts` / `uv-cache` 11 個標記全部 **OK**
- [x] B5. blob 雜湊比對：`docker/entrypoint-ssh.sh`、`docker/stage2-hook.sh`、`docker-compose.yml`、`AGENTS.md`、`ghcr-publish.yml` → **5/5 SAME**
- [x] B6. dispatch input 仍為 **`tag_name`**

### Phase C — 推送 + 建置
- [x] C1. `git push -u kuniakil my-config-v0.22.1` → remote HEAD `81bc37f796` = local
- [x] C2. dispatch（**input 為 `tag_name`**）→ Run **38691266688**
- [x] C3. `event=workflow_dispatch`、`headBranch=my-config-v0.22.1`、`headSha=81bc37f796`（**我方 commit**）✅
- [x] C4. `gh run watch` → prepare / linux-amd64 / linux-arm64 / merge **全部 success**
- [x] C5. image tags 存在：`v0.22.1` HTTP 200、`latest` HTTP 200（registry API 驗證）
- [x] C6. **未 force-push 版本 tag**

### Phase D — 部署 + 驗證
- [x] D1. `~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag: "v0.22.0"` → `"v0.22.1"`
- [x] D2. `kubectl kustomize .` render 出 `ghcr.io/kuniakil/hermes-agent:v0.22.1`；rollout **successfully rolled out**
- [x] D3. **`sessions.auto_prune: false` 仍在**（config.yaml:507，位於 `sessions:` 區塊；第 72 行 `auto_prune: true` 是 `cron:` 區塊，勿混淆）
- [x] D4. 冒煙測試全數通過：Python 3.14.7 / locale 3 種 / sshd+rsync+tini / ffmpeg+agent-browser / edge_tts+dingtalk_stream+lark_oapi+firecrawl / Telegram connected / **0 ERROR**
- [x] D5. **session authority 專項**：**127 sessions / 17,632 messages / 123 個含歷史的 session 全部可讀**；`worker_executions`、`worker_receipts` 新表已建立
- [x] D6. `state.db` `schema_version` 實測 = **31**（與升級前一致）；`[config-migrate] 50 -> 51` 自動完成；部署 45s 後 0 restart

### Phase E — 收尾
- [x] E1. 全部勾選完成
- [x] E2. 產出 `UPGRADE_LOG_v0.22.0_to_v0.22.1.md`
- [x] E3. 本工作表已同步「實際執行結果」

---

## 5. 專案特定備註（Hermes）

- **Fork remote**：`kuniakil`；**Upstream remote**：`origin`（⚠️ 與 OpenClaw 相反）
- **Workflow**：`ghcr-publish.yml`
- **dispatch input**：**`tag_name`**（**不是** `tag`；傳錯會被靜默忽略，只會產出 `latest`）
- **HERMES_IMAGE**（compose `.env`，受 `**/*.env` 防護，**需使用者手動改**）：`v0.22.0` → `v0.22.1`
- **k8s overlay**：`~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag` → `v0.22.1`
- **Host 保護**：本機**不**跑 pytest / docker build / 全面 typecheck；僅 `git diff` / `git status` + 單檔語法檢查；編譯與完整測試交由 GitHub Actions

## 6. npm 漏洞決策複驗（承 v0.22.0 §8.3 的三個檢查動作）

| 檢查 | 結果 |
|---|---|
| ① 根 `package-lock.json` `overrides` 前後是否變動 | ❌ **未變動**（皆為 `{}`）→ 原決策前提成立 |
| ② 容器內 `find /opt/hermes -name node_modules -type d` | ✅ 維持 v0.22.0 實測結論（僅 photon sidecar 一棵樹，未啟用） |
| ③ 只對實際存在的樹跑 `npm audit` | ✅ 暴露面未變，無需重測 |

**額外收穫**：官方本次 `Deps: bump the WhatsApp bridge lock past its npm-audit findings` + `Doctor: clarify Docker npm audit remediation` —— 已修的項目我們本來就沒部署。**維持「不修」決策**，觸發條件不變（啟用 photon/iMessage sidecar、web dashboard、ui-tui 即須重評）。

## 7. Go-Sign

- [x] 使用者回覆「Go」，授權執行 Phase A–E → 已於 2026-10-15 執行完畢

---

## 8. 風險總結

| 風險 | 等級 | 緩解 |
|---|---|---|
| Dockerfile hunk 衝突 | 🔴 高（必然發生） | §2.3 已給出並存寫法；改以手動重做取代 cherry-pick |
| Session authority 大重構（2,170 檔） | 🟡 中 | Schema 版本未變（31→31）可回滾；D5/D6 專項實測 |
| 37 個 workflow 衝突 | 🟢 低 | Purge 規則直接刪除，不需解決 |
| pm 套件版本 | 🟢 無 | `pm/lock.json` 零 diff |
| DB 遷移不可逆 | 🟢 **無** | `SCHEMA_VERSION 31 → 31`，回滾不需預備份 |
| npm 漏洞 | 🟢 無變化 | `overrides` 位元組相同 |

**整體評估：低風險、可乾淨升級。唯一硬性人工步驟是 Dockerfile 合併。**