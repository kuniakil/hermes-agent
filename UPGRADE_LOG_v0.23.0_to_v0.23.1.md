# Hermes Agent 升級紀錄：v0.23.0 → v0.23.1

- **升級日期**：2026-11-10
- **目標版本**：`v0.23.1`（官方 commit `3b421578588243f920886e6fe79a6faa87ea026e`，2026-11-10 01:42Z 發佈，immutable）
- **升級前版本**：`v0.23.0`（基於官方 `v0.23.0` = `2bd378ed1b8d`）
- **新分支**：`my-config-v0.23.1`（基底 = **`upstream-v0.23.1`**，非本地 `v0.23.0` tag）
- **Image source SHA**：`9527d9b9b973220055b1e0b3aab8cfaa997290b6`（= GHCR run `42741971255` 的 `headSha`，亦即 `hermes --version` 顯示的 `upstream 9527d9b9`）
- **GH Actions Run**：[`42741971255`](https://github.com/kuniakil/hermes-agent/actions/runs/42741971255)（prepare / build-and-push amd64 / build-and-push arm64 / merge 全 success，總耗時 10m03s）
- **發布映像**：`ghcr.io/kuniakil/hermes-agent:v0.23.1`（與 `latest`），雙架構 multi-arch index
  - index digest：`sha256:6546fcb872d6f6b75031b0d153e8556a906556b9ed6dc8fe108917ed8e56c055`
  - `linux/amd64` → `sha256:b57aacbdd575c5ef48db363b0d49472505b93abb839f25370e4e72cf493f1cf9`
  - `linux/arm64` → `sha256:c0eb6e361cf415cac16026ea9331367fd92d8673ddb49879a6a5f4999f5d36c5`
- **部署環境**：K3s n100，pod `hermes-agent-6587cc854c-464mf`（舊 pod `hermes-agent-f9496b576-wcxg8` 已移除）
- **schema_version**：32 → **33**（🔴 **單向遷移，不可逆**）
- **config_version**：52 → **53**（單向，僅在使用者仍是預設值時改寫 `agent.clarify_timeout`）
- **FTS_STORAGE_VERSION**：3 → **3**（不變）
- **備份**：`~/backups/hermes-20261110/`（185 MB，integrity ok，messages 18,067 / sessions 134）
- **工作表**：`docs/worksheet-upgrade-hermes-v0.23.1-20261110.md`

---

## 1. 一句話總結

> 官方把 v0.23.1 標成 patch，但它是 **2,578 commits / 2,781 檔 / 618 PRs** 的大視窗（官方明說完整 curated notes 延到 v0.24.0，本視窗內容「刻意未文件化」）。
>
> 對我們而言是**資料面有單向遷移、程式面零衝突**的一次：
> 1. **DB schema 32→33 是單向的**：移除已淘汰的 `messages_fts_cjk` 索引（改走 trigram）、重標 `source='subagent'` 的 session、加一個一次性 legacy-refusal 修復 → **回退必須還原備份**，不能只改回舊 image；
> 2. **但對我們而言 v33 近乎 no-op**：我們的 v32 DB **本來就沒有** `messages_fts_cjk` 索引（Phase 0 實測 `sqlite_master` 查 `%cjk%` → 空），CJK 搜尋當下就已經走 trigram → 移除動作回傳 `False`，**不寫 log 屬正確行為**；
> 3. **自訂層 100% 零衝突**：上游 pnpm 化的 Dockerfile 改動與我們 14 個自訂 hunk **完全不重疊**，`git apply -3` 乾淨套用（+33/−3）；49 個自訂 commits、**0 merges**、0 conflicts；
> 4. **線上全面檢查全綠**：D3–D9 / D11 全數通過 —— schema=33、integrity ok、sessions/messages 數量與升前**完全一致**、中文搜尋經 trigram 命中、D8 config 未被改動、D11 實測 catalog 2.25 MiB > 2 MiB 舊上限證明 16 MiB 修正生效；**D10 使用者 Telegram 實測往返通過**（§5）；
> 5. **兩個上游既有問題（非本次升級造成，維持不修）**：
>    - v0.23.1 改用 pnpm 後，`pm/lock.json` 多出 `pnpm` 條目，但 runtime image 從未安裝它 → 每次啟動多一行 `pnpm: not installed or outdated` 警告。**純外觀，gateway 運作正常；我們的 Dockerfile 不加 pnpm（上游明載 pnpm 不進 runtime image）**（§6.1 / §6.6）；
>    - `GET /v1/skills` 恆回 HTTP 500（`find_all_skills()` 簽章不符）—— v0.23.0 與 v0.23.1 逐位元組相同、`origin/main` 未修、對我們無影響（§6.8）。

---

## 2. 官方 Release Notes 稽核

### 2.1 唯一明列的修正

- **plugin-catalog 超過客戶端 2 MiB 上限** → `hermes plugins install` **靜默退回內建目錄**，使用者看不到較新的移除項目。修正：上限調為 **16 MiB**（#151860），上游 commit `6cff782b8d fix(plugin-catalog): accept the published catalog past 2 MiB`。
  - 客戶端上限程式碼：`hermes_cli/plugin_catalog.py:41-42`
    > The published doc passed 2 MiB on 2026-11-09 (2,109,306 bytes for 1,268 entries, about 1.7 KB each), and a client that refuses it silently installs its own in-tree pins and misses newer removals. 16 MiB leaves …
  - **D11 實測**：我們的 catalog 快取 `/opt/data/cache/plugin-catalog.json` = **2,361,352 bytes（2.25 MiB）> 2 MiB 舊上限**，`entries = 1,378` → 證明修正確實生效。

### 2.2 沒有 Breaking Changes / Deprecations 章節

官方明說完整 curated notes 隨 **v0.24.0** 發布 → **本視窗內容「刻意未文件化」**。所以下面 §2.3 的風險全部來自我們自己對 diff 的稽核，**不能靠 notes**。

### 2.3 未文件化但確認存在的變更（與我們相關者）

| 變更 | 對我們的影響 |
|---|---|
| **Telegram plugin 大改**（33 檔，+3775/−1195） | 我們唯一的平台 → D 階段必須實測往返（Q3 已確認） |
| workspaces 由 npm 改 **pnpm**（`7062229090`） | Dockerfile 兩個 build stage 改寫；根目錄 `package-lock.json` → `pnpm-lock.yaml` + `pnpm-workspace.yaml` |
| `pyproject.toml` 新增 `av==18.1.0` pin | 修 faster-whisper 1.2.1 與 PyAV 19 的 `metadata_errors` TypeError（#135245）→ **對我們的語音自訂層有利** |
| 移除 py3.14 的 `tenacity`；新增 `update-startup-files`、`hermes_agent` package | 無影響 |
| TUI/CLI Esc backtrack、`hermes gateway attach`、`hermes clipboard image --json`、新 plugin API（`on_session_open` / `post_curator_run` / `llm.oneshot`…） | 未使用，無影響 |

---

## 3. 關鍵技術調整與解決

### 3.1 自訂層 14 個 marker：零衝突原樣移植

我們的 Dockerfile 自訂 hunk 與上游 v0.23.1 的 pnpm 化改動**區段完全不相交**，因此採「以 `upstream-v0.23.1` 為底 + `git apply -3` 套用 v0.23.0 自訂 patch」的路徑（commit `ab78b29e23`，+33/−3），**乾淨套用、零衝突**。

上游 v0.23.1 對 Dockerfile 的改動（全部保留、未被我們覆寫）：

- `COPY pyproject.toml setup.py uv.lock ./`（新增 `setup.py`）
- `frontend_build` / `webapp_build` 兩 stage 改用 `pm ensure("pnpm")` + `COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./`
- `COPY scripts/build/node-deps*.mjs … pnpm-lock.mjs`
- `frontend_build` 末尾 `cp -RL node_modules/typescript /opt/products/typescript`；runtime stage 改 `COPY --from=frontend_build /opt/products/typescript …`
- 移除 `ENV npm_config_install_links=false`

我們保留的自訂層（14/14 marker 全部在位，B3 原始碼確認 + D9 容器內實測）：

`openssh-server` / `rsync` / `ssh-keygen -A` / `zh_TW.UTF-8` / `en_US.UTF-8` / `useradd -u 10000` / `--extra edge-tts` / `firecrawl` / `dingtalk` / `feishu` / `exa` / `/tmp/.npm-cache` / `entrypoint-ssh.sh` / `ENV HOME=/opt/data`

### 3.2 其他自訂 commit 的處置

| 檔案 | 上游 v0.23.0→v0.23.1 是否變動 | 動作 |
|---|---|---|
| `docker/entrypoint-ssh.sh` | **上游無此檔** | cherry-pick `52a01e46c2` → `0f367b0953`（純新增） |
| `docker/stage2-hook.sh` | **未變動** | cherry-pick `da94722ce4` → `1ee17b3540`（零衝突） |
| `docker-compose.yml` | **未變動** | cherry-pick `ea9b93a6d2` → `8fb55cef85` |
| `AGENTS.md` | 結構大改（`just`、boundary lint、Project Structure 縮減） | 取上游版 + **重新 append**「Local Resource Constraint (Mac Host Protection)」章節（`31299dd341`） |
| `.env.example` | 移除 Honcho 區塊 | 取上游版 + **只加回** 13 行 `HERMES_IMAGE` 註解（`d23343f13a`）；Honcho 區塊**不復原**（依上游） |
| `.github/workflows/*` | 大改 + 新增 `repo-guards.yml` | **全部 purge**（46 檔），只留我們的 `ghcr-publish.yml`（154 行，checkout 自 `my-config-v0.23.0`，commit `72d61c1e56`） |
| `docs/**`（41 commits） | **上游 v0.23.1 無 `docs/` 目錄** | 全部零衝突 cherry-pick |

### 3.3 衝突面稽核方法

```
comm -12 <(git diff --name-only upstream-v0.23.0..my-config-v0.23.0 | sort -u) \
         <(git diff --name-only upstream-v0.23.0 upstream-v0.23.1 | sort -u)
```

結果（扣除本來就會 purge 的 `.github/workflows/*`）僅 **5 檔**：`Dockerfile`、`AGENTS.md`、`.env.example`、`docker-compose.yml`、workflows。其中 `docker-compose.yml` 上游**未變動** → 實際需人工處理的只有 3 檔。

### 3.4 lockfile 策略

- 分支內**無** `package-lock.json`（上游改用 `pnpm-lock.yaml` + `pnpm-workspace.yaml` + `.npmrc`）。
- **我們未手動修改任何 lockfile**（v0.23.0 曾對 `package-lock.json` 做 npm audit 修補 —— 該前提在 v0.23.1 已不適用）。
- 對應的 `pnpm audit` 檢查交由 CI build（`ghcr-publish.yml`）在容器內完成；Mac 本機不跑 pnpm（資源保護規則）。

---

## 4. DB / Config 遷移實際結果

### 4.1 schema 32 → 33

上游 v33 做了三件事（讀 `hermes_state_schema.py` diff）：

1. 重標 `source='subagent'` 且缺 `_delegate_from` 的 session（`UPDATE sessions … json_set`）— 資料改寫
2. **移除已淘汰的 `messages_fts_cjk` 索引**（CJK 搜尋改走 trigram）；log 會提示 `~/lib/libfts5_cjk.so` 可刪
3. 新增 `LEGACY_REFUSAL_REPAIR_DONE` 一次性修復（`hermes_state_legacy_refusal.py`）

**對我們的實測結果**：

| 項目 | 升前（v32） | 升後（v33） | 判定 |
|---|---|---|---|
| `schema_version` | 32 | **33** | 遷移生效 ✅ |
| `PRAGMA integrity_check` | ok | **ok** | ✅ |
| `PRAGMA user_version` | 0 | 0 | Hermes 用自建 `schema_version` 表，非 SQLite user_version |
| `sessions` | 134 | **134** | ✅ 零損失 |
| `messages` | 18,067 | **18,067** | ✅ 零損失 |
| `messages_fts` | 18,067 | **18,067** | ✅ |
| `messages_fts_trigram` | 18,067 | **18,067** | ✅ |
| `sqlite_master` 查 `%cjk%` | 空 | 空 | ✅ v33 的移除動作對我們為 **no-op** |

> **注意（避免誤判）**：工作表原以「開機 log 出現『Removed the retired messages_fts_cjk index』」為 D4 通過條件。實測**該訊息不會出現** —— 因為我們的 v32 DB 本來就沒有該索引，上游 `drop_retired_cjk_index()`（`hermes_state_fts.py:178`）在索引不存在時回傳 `False`。**訊息缺席是正確行為，不是遷移失敗。** 工作表已於 Phase D 前修正此條件。

### 4.2 config 52 → 53

上游 `52 -> 53` 遷移（`hermes_cli/config_migrations.py:876`）只改寫 `agent.clarify_timeout`，且**僅當舊值為 `3600`（預設）**時改為 `90`。

我們的 `config.yaml` 顯式設為 **`600`**（非預設）→ **未被改寫**。實測：`_config_version = 53`、`clarify_timeout = 600` ✅

### 4.3 其他 config 覆核

| 鍵 | 值 | 判定 |
|---|---|---|
| `model.default` | `MiniMax-M3` | ✅ 未被改動 |
| `model.provider` | `minimax` | ✅ 未被改動 |

---

## 5. 線上全面檢查結果（2026-11-10 實測）

| 檢查 | 結果 |
|---|---|
| Pod | `hermes-agent-6587cc854c-464mf`，`1/1 Running`，`RESTARTS=0` |
| imageID | `ghcr.io/kuniakil/hermes-agent@sha256:6546fcb872d6f6b75031b0d153e8556a906556b9ed6dc8fe108917ed8e56c055` ≡ C5 index digest ✅ |
| Deployment | `observedGeneration=94`、`updatedReplicas=1 / readyReplicas=1 / availableReplicas=1` ✅ |
| `hermes --version` | `Hermes Agent vv0.23.1 (2026.9.24) · upstream 9527d9b9` ✅ |
| `hermes doctor` | 21 ✓ / 7 ⚠ / `Found 1 issue(s)` — **與升前基線完全一致**（⚠ 為既有狀態：5 個 system dependency + 3 個缺 API key） |
| s6 supervision | `s6-svscan → rc.init top → main-wrapper.sh → profile-gateways → s6-svscan /run/hermes-service → gateway-default → gateway python` ✅ 完整 |
| 開機後 ERROR / CRITICAL | **0**（`/opt/data/logs/errors.log` 第 16713 行之後） |
| Telegram | `10:32:52 Connected to Telegram (polling mode)` ✅；**使用者實測往返通過**（10:48 CST，由 Telegram 下達指令並收到完整回覆） |
| 中文搜尋 | trigram `MATCH '繁體中文'` → **21** hits（base FTS 同詞僅 5）；`SessionDB.search_messages('繁體中文')` → 5 rows，高亮 `>>>繁體中文<<<` 正確；`'升級'`、`'記憶'` 各 5 rows ✅ |
| locale | `C.utf8` / `en_US.utf8` / `zh_TW.utf8` ✅ |
| 工具鏈 | `sshd` `/usr/sbin/sshd`、`rsync`、`tini`、`tmux`、`ffmpeg` `/usr/local/bin/ffmpeg`、`ffprobe` ✅ |
| SSH | host keys 已產生、`/opt/hermes/docker/entrypoint-ssh.sh` 在位 ✅ |
| 權限 | `HOME=/opt/data`、`/root/.npm` 屬主 `hermes(10000)`、`/tmp/.npm-cache` = `1777` ✅ |
| extras | `edge_tts` / `firecrawl` / `lark_oapi` / `exa_py` / `dingtalk_stream` 皆可 import ✅ |
| plugin catalog | `hermes plugins browse` 輸出完整 table；快取 2,361,352 B / 1,378 entries ✅ |
| 資源（開機 13 分鐘） | CPU `65m` / MEM `329Mi` ✅ |

### 5.1 升前基線 vs 升後：唯一差異

升級前後**唯一**的行為差異是那行 `pnpm: not installed or outdated` 警告（見 §6）。除此之外，`hermes doctor` 輸出、DB 內容、config 值、s6 樹、tool schema 數量（21）皆一致。

---

## 6. `pnpm: not installed or outdated` — **上游 v0.23.1 缺陷**，非本次升級造成

### 6.1 症狀

每次 CLI dispatch 的 stderr、以及 gateway 啟動的 WARNING：

```
⚠ install out of sync (pnpm: not installed or outdated) — this docker-managed install must rebuild the artifact to fix
```

### 6.2 根因（逐步實測確認）

1. 上游 commit `7062229090 chore(js): switch the workspaces from npm to pnpm` 讓 `pm/lock.json` **新增 `pnpm` 套件條目**
   - 實測：`pm/lock.json` 在 v0.23.0 有 `pnpm` **0** 筆；在我們 v0.23.1 分支有 **19** 筆；`json.load(...)["packages"]["pnpm"]` 確實存在（含 `darwin-arm64` 等 artifacts）
2. `Dockerfile` **runtime_base** stage 的安裝清單在 v0.23.0 與 v0.23.1 **完全相同**，**沒有 pnpm**：
   ```dockerfile
   RUN python3 -c 'from pm import ensure; [ensure(name, explicit=True) for name in ("uv", "chromium", "npm", "ffmpeg", "ripgrep")]'
   ```
   `pnpm` 只在 `frontend_build`（Dockerfile:334）與 `webapp_build`（Dockerfile:362）stage 被 `ensure("pnpm")` — 這兩個 stage **不會**進 runtime image
3. runtime image 內 `/opt/hermes/tools/facts.json` **沒有 pnpm 條目**，`/usr/local/bin/pnpm` **不存在**（容器內實測）
4. `pm/install.py:1023 drift()` 迭代 `lockfile.names()`（= lockfile 全部套件，含 pnpm），對每個非 optional / 非 internal 的套件檢查 `_installed_location(...)`；找不到 → `problems[name] = "not installed or outdated"`
5. `hermes_cli/venv_sync.py:51 check_runtime()` → `hermes_cli/main.py:3380` 印到 stderr；`gateway/run.py:5101` 記為 WARNING

### 6.3 為什麼不是我們的自訂層造成

我們的 Dockerfile 在 pm 相關區段與 upstream **逐行相同**（已 diff 確認）。我們的自訂 hunk 全部落在 locale / ssh / `useradd` / extras / npm-cache / `HOME=/opt/data` 區段，**與 pm 無任何交集**。

### 6.4 上游是否已修

**否**。`origin/main` 目前只比 `upstream-v0.23.1` 多 5 個 commit（`8b50838443`、`331a41a81f`、`8edd3120da`、`b3746e35dd`、`d1aed60ec1`），**沒有任何一個** 動到 `pm/` 或 `hermes_cli/venv_sync.py`。

### 6.5 影響與處置

- **影響：純外觀**。一行 stderr + 一條 gateway WARNING。gateway 正常運作（`Turn machinery warmed in 2.0s (21 tool schema(s))`）。
- **處置：不動**。我們不自行在 Dockerfile 加 `ensure("pnpm")` —— 那會讓我們的 image 偏離 upstream，應由上游修（把 pnpm 加進 runtime_base 的 ensure 清單，或標為 optional / internal）。若日後確認要本地 workaround，必須另開一個可追溯的 commit 並記錄於本升級日誌。

### 6.6 「v0.23.1 是否改用 pnpm？我們的 Dockerfile 要不要加 pnpm？」

容器內 agent 的自我檢查報告提出了這個問題（並建議在容器內驗證 `packageManager` 欄位）。完整答覆：

**Q1：v0.23.1 是否改用 pnpm？→ 是。**

- 上游 commit `7062229090 chore(js): switch the workspaces from npm to pnpm`
- 容器內實測：`/opt/hermes/pnpm-lock.yaml`（464,400 B）與 `/opt/hermes/pnpm-workspace.yaml` 存在；`/opt/hermes/package-lock.json` **已不存在**

**Q2：我們的 Dockerfile 需要加 pnpm？→ 不需要，且不該加。**

上游 Dockerfile 自己就寫明了（`Dockerfile:330-333`）：

```dockerfile
# Frontend dependencies never enter the runtime layers.
FROM runtime_base AS frontend_build
# pnpm installs the workspaces; nothing in the runtime image runs it, so only
# the build stages (this one and webapp_build) stage it.
```

pnpm 只在 `frontend_build`（`Dockerfile:334`）與 `webapp_build`（`Dockerfile:362`）兩個 stage 被 `ensure("pnpm")`。**runtime image 內沒有任何東西會執行它**（容器內實測：`which pnpm` → 不存在；`/usr/local/bin/pnpm` → 不存在；`_pm_tool_path("pnpm")` → `None`）。

在 runtime_base 加 pnpm 會同時造成四個後果，全為負：

| 後果 | 說明 |
|---|---|
| 違背上游明載設計 | 上游註解直說「nothing in the runtime image runs it」 |
| image 偏離 upstream | 我們的分支定位是「官方程式碼 + 自訂層」，不是「官方 + 自訂 + 對上游設計的異議」 |
| 體積增加 | pnpm 12.15.0 + 其閉包 |
| **仍然無效** | 加上 pnpm 也**不會**讓 web / ui-tui 的 audit row 回來（見 §6.7） |

**真正的上游缺陷在 `pm`，不在 Dockerfile**：`pm/lock.json` 把 pnpm 列為一般可安裝套件，但 `pm.drift()` 拿 lockfile 的**全部**套件名稱去比對 runtime facts，只跳過 `package.optional` / `package.internal` 的套件 —— pnpm 兩者皆非 → 每次報 "not installed or outdated"。上游修法（擇一）：(a) pnpm 加進 runtime_base 的 ensure 清單；(b) lockfile 把 pnpm 標為 build-only / optional；(c) `drift()` 忽略不在目標 facts 裡的 build-time 套件。

### 6.7 doctor 的 npm/pnpm audit 列消失 — 上游兩個獨立改動疊加，**不是** pnpm 缺失的連帶效果

`_check_npm_audit`（`hermes_cli/doctor_tools.py:439`）的 gate 在兩版之間**同時**變了兩件事：

| | v0.23.0 | v0.23.1 |
|---|---|---|
| 工具 | `npm` | `pnpm`（WhatsApp bridge 仍用 `npm`） |
| 存在性檢查 | `((PROJECT_ROOT if audit_extra else npm_dir) / "node_modules").exists()` — **只查 root** | `tool and (tree / "node_modules").exists()` — **查該 workspace 自己的** |

v0.23.1 的三個 pnpm row 各被**兩個獨立條件**擋掉：

1. `pnpm_bin = _pm_tool_path("pnpm")` → `None` → `tool` falsy → 跳過（連 "Root npm package" 也是）
2. `(PROJECT_ROOT / "web" / "node_modules").exists()` → **False**（容器內實測 `web/node_modules` 與 `ui-tui/node_modules` **不存在**）→ **即使裝了 pnpm，web / ui-tui 兩列仍然不會出現**

**淨效果是改善。** v0.23.0 升級日誌 §9.4 早就記載：「`web` / `ui-tui` workspace 沒有 node_modules，容器內 `hermes doctor` 報的 npm 數字**不可信**」。v0.23.1 把這些 JS 依賴樹**整個移出 runtime image**（`Dockerfile:330`：「Frontend dependencies never enter the runtime layers」）→ 那批帶漏洞的套件**本來就不在 image 裡**，audit row 消失是**誠實**的結果，而不是檢查被跳過。

容器內 JS tree 現況（實測）：

| 路徑 | 狀態 |
|---|---|
| `/opt/hermes/node_modules` | 存在，**1 個 entry**（僅 typescript） |
| `/opt/hermes/web/node_modules` | **不存在** |
| `/opt/hermes/ui-tui/node_modules` | **不存在** |
| `/opt/hermes/scripts/whatsapp-bridge/node_modules` | **不存在**（我們不用 WhatsApp） |
| `/opt/hermes/plugins/platforms/photon/sidecar/node_modules` | 存在，71 entries（`npm ci --no-audit` 烤進 image；兩版一致，我們不啟用 photon） |

→ **runtime 暴露面維持 0，且比 v0.23.0 更乾淨**（v0.23.0 那些帶漏洞的 web / ui-tui 依賴已不在 image 內）。

### 6.8 `GET /v1/skills` **仍回 HTTP 500** — 上游既有缺陷，v0.23.0 與 v0.23.1 相同

> 容器內 agent 的自我報告稱「`/v1/skills` 今日沒有再出現」。**此判斷為誤判** —— 實測（帶正確 `Authorization: Bearer $API_SERVER_KEY` 查 `127.0.0.1:8642/v1/skills`）**仍是 500**：

```
HTTP 500
{"error": {"message": "Failed to enumerate skills", "type": "server_error", ...}}
```

traceback（`/opt/data/logs/errors.log`）：

```
ERROR gateway.platforms.api_server: GET /v1/skills failed
  File "/opt/hermes/gateway/platforms/api_server.py", line 2387, in _handle_skills
    find_all_skills(
TypeError: find_all_skills() got an unexpected keyword argument 'include_editorial'
```

**根因**：呼叫端 `gateway/platforms/api_server.py:2387-2389` 傳 `find_all_skills(skip_disabled=False, include_editorial=True)`，但定義端 `tools/skills_tool.py:277` 是 `find_all_skills(*, skip_disabled: bool = False)` —— **沒有** `include_editorial`。

**判定**：v0.23.0 與 v0.23.1 的呼叫端**逐位元組相同**；`origin/main` 仍未修 → **上游既有缺陷，維持不修**（與 v0.23.0 升級日誌 §6 一致）。

**上游 CI 為何沒抓到**：`tests/gateway/test_api_server.py:987` 用 `patch("tools.skills_tool.find_all_skills", return_value=list(fake_skills))` —— mock 接受任意 kwargs，真實簽章不符被完全遮蔽。

**對我們的影響：無。** 該 endpoint 只被外部 API client 消費；repo 內無 `.ts` / `.tsx` / `.mjs` 呼叫者，我們不使用 Desktop app / Webapp。日常入口 Telegram 的 `/skills list` slash command 走**另一條**程式路徑（直接呼叫 `tools/skills_tool`），不受影響。

---

## 7. 其他觀察（非缺陷）

### 7.1 Telegram adapter 網路中斷後的重建路徑

舊 Pod（v0.23.0）於 `2026-11-10 07:11:49` 出現：

```
ERROR hermes_plugins.platforms__telegram.adapter: [Telegram] Telegram updater.stop() did not finish before the network-recovery deadline; rebuilding the adapter instead of reusing an Updater whose lifecycle lock may still be held. (likely CLOSE-WAIT socket)
ERROR gateway.run: Fatal telegram adapter error (telegram_network_error): ...
```

這是 Telegram API 連線中斷（`149.154.166.110` ConnectTimeout，連續 8 次重試）後的 **adapter 重建**路徑；隨後 `07:12:20 Connected to Telegram (polling mode)` 恢復正常。v0.23.1 開機後**未再復現**。屬**升級前**事件，非 v0.23.1 迴歸。

### 7.2 `faster-whisper` / `av` 無法在 baked image 內驗證

`voice` extra 為**惰性安裝**（lazy-install），`faster-whisper` / `av` **不在 image 內** —— 與 v0.23.0 相同，**非本次升級退化**。

`av==18.1.0` pin（修 PyAV 19 造成的 `metadata_errors` TypeError，上游 #135245）確實存在於 image 內的 `pyproject.toml`（`[voice]` 與 `[stt-whisper]` 兩處皆有），但**只有在實際 lazy-install 時才會生效**（落地到 `/opt/data/installs/<generation>/`）。故「無 `metadata_errors` TypeError」必須在使用者**首次觸發語音輸入**後才能實測。

---

## 8. 備份與資產處置

| 項目 | 內容 |
|---|---|
| 升級前備份 | `~/backups/hermes-20261110/`（185 MB）— `state.db` 184,508,416 B / `state.db-wal` 0 B / `state.db-shm` 32,768 B / `config.yaml` 13,234 B / `.env` 997 B / `.hermes/config.yaml` 6,598 B / `.hermes/skills` 11 MB |
| 備份方法 | Pod 內 `PRAGMA wal_checkpoint(TRUNCATE)` → `(0,0,0)`，再 **tar streaming** 傳回（`kubectl cp` 在 ~176 MB 的 `state.db` 上會 `websocket: close 1006` 中途斷流） |
| 備份驗證 | `PRAGMA integrity_check = ok`、`messages = 18,067`、`sessions = 134`、`schema_version = 32`、`_config_version = 52` — **與線上基線完全一致** |
| 舊備份 | `~/backups/hermes-20261106/`（v0.23.0 快照，176 MB）**待 D 全綠 + 使用者授權後刪除**（v0.23.0 先例亦為取得明授權後才刪） |
| 說明 | **hermes namespace 無 PVC**，資料走 hostPath `/data/services/hermes/data`；`~/kubernetes/hermes/backups/` 為**空目錄**，從未使用過 |

---

## 9. 回滾方案

因 DB 已升 v33（**不可逆**），回退**必須**同時還原資料：

1. `kubectl --context n100-cf -n hermes scale deploy/hermes-agent --replicas=0`（或先改 `newTag` 並讓 pod 停止寫入）
2. 從 `~/backups/hermes-20261110/` 還原 `/opt/data`（`state.db` / `state.db-wal` / `state.db-shm` / `config.yaml` / `.env` / `.hermes/config.yaml` / `.hermes/skills`）到 hostPath `/data/services/hermes/data`
3. `~/kubernetes/hermes/overlays/n100/kustomization.yaml` 的 `newTag` 改回 `v0.23.0`，`kubectl apply -k ~/kubernetes/hermes/overlays/n100`
4. 驗證 Pod 1/1、DB `schema_version = 32`、Telegram 往返

> ⚠️ **不可**只把 `newTag` 改回 `v0.23.0` 就起 Pod —— v0.23.0 的程式碼開 v33 DB 的行為未驗證（可能拒絕或重建 CJK 索引）。

---

## 10. Image stamp 與分支 HEAD 的差異（有意保留）

| 項目 | SHA | 說明 |
|---|---|---|
| 已部署 image 的 build stamp | `9527d9b9b9` | GHCR run `42741971255` 的 `headSha`（= `hermes --version` 的 `upstream 9527d9b9`） |
| 分支現況 HEAD（`my-config-v0.23.1`） | `a4adce1b1b` | 差數個 commit，**全為 docs** |

差異內容**全部為文件**：`docs/worksheet-upgrade-hermes-v0.23.1-20261110.md` 的執行結果回填與本 `UPGRADE_LOG_v0.23.0_to_v0.23.1.md`。**runtime 程式碼零差異**（`git diff --name-only 9527d9b9b9..a4adce1b1b` → 只有 `docs/worksheet-upgrade-hermes-v0.23.1-20261110.md`）。

**決策：不重新建置、不重新部署。** 理由與 v0.23.0 相同：

1. 現行部署已通過完整線上驗證（D3–D9 / D11 全綠、開機後 0 ERROR、RESTARTS 0）；
2. 重新建置會覆寫同一個 `v0.23.1` tag（既定行為），導致新 digest、需重新 pull + rollout + 重新驗證，純粹為了讓 stamp 對齊一個文件 commit 而承擔風險；
3. D12 的 24h 穩定性觀察窗口不應被無謂重置。

若日後需要讓 image stamp 與分支 HEAD 完全對齊，重跑同一條指令即可：

```bash
gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent \
  --ref my-config-v0.23.1 -f tag_name=v0.23.1 -f platforms=all
```

---

## 11. 尚待完成

| # | 項目 | 狀態 |
|---|---|---|
| D10 | **使用者實測 Telegram 往返** | ✅ **通過**（2026-11-10 10:48 CST）。實際由 Telegram 下達「升級後檢查」，agent 回覆完整報告：sessions 134、integrity ok、config v53、API 44 項全通、Skills Hub 22 skills、Tools 30 active、磁碟 1.8T/35%、記憶體 30Gi/14Gi available。`messages` 18,067 → 18,073（+18 = 本次往返本身產生） |
| D12 | 24h 觀察：RESTARTS / 記憶體 / ERROR 數（on-demand 手動檢查） | ⏳ 2026-11-11 複查。基線：`RESTARTS=0`、MEM `329Mi`、開機後 ERROR `0` |
| D9 | `faster-whisper` / `av` 實測（首次語音輸入觸發 lazy-install 後驗 `metadata_errors`） | ⏳ 待觸發語音功能 |
| E1 | 刪除 `~/backups/hermes-20261106/`（保留 `hermes-20261110`） | ⏳ 待 D12 完成 + 使用者授權 |
| E4 | （視需要）以 `doc-and-wp-publish` 發佈至 wp.3pm.lol | ⏳ 選用 |

> 註：容器內 agent 的自我檢查報告有**兩處判斷需修正** —— (1) 「`/v1/skills` 今日沒有再出現」為**誤判**，實測仍回 500（§6.8）；(2) 「Dockerfile 需要加 pnpm」的建議**不採用**，上游明載 pnpm 不進 runtime image（§6.6）。報告的其餘數據均已獨立複驗。

---

## 12. 附錄 A — 本次升級的「刻意未文件化」風險應對

v0.23.1 的官方 notes 刻意不完整，因此我們用**四道獨立量測**替代它們：

1. **機器可讀真相**：`SCHEMA_VERSION`、`FTS_STORAGE_VERSION`、`_config_version` 直接讀程式碼常數與 DB 表，不依賴 notes。
2. **衝突面數學化**：`comm -12` 求交集 + `git apply -3` 實測，不依賴「應該沒事」。
3. **升前基線快照**：Phase 0 先記錄 DB 計數、config 值、`hermes doctor` 輸出、s6 樹、locale、extras 清單 → D 階段逐項比對，**升級前後差異必須為零或可解釋**。
4. **回退可行性先於升級驗證**：備份先做、先驗 integrity 與計數，再動任何程式碼。

結果：除 §6 的上游 pnpm 警告外，**升級前後無任何可觀察差異**。
