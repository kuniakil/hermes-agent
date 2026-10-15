# UPGRADE LOG：v0.22.0 → v0.22.1

- **日期**：2026-10-15
- **工作表**：`docs/worksheet-upgrade-hermes-v0.22.1-20261015.md`
- **官方 tag**：`v0.22.1` = commit `297552a9d646119871391d202509822cd86330df`（2026-10-14 發佈）
- **升級分支**：`my-config-v0.22.1`
- **最終 HEAD**：`81bc37f7965ffd055c966d05bc8b06237977c884`
- **結果**：✅ **升級成功並已部署到 n100 K3s**

---

## 1. 官方 Release 稽核結論

### 1.1 規模

官方自稱「patch release」，實為 **2,216 commits / 2,170 files / +190,328 −49,590**。`v0.22.1` 為 `v0.22.0` 的線性後代（`git merge-base --is-ancestor` = true），無 fork/rebase 拓撲問題。

主題為 **canonical session authority 重構**：把 CLI / Desktop / TUI / ACP / REST / Bot relay 的所有 session 寫入路徑收斂到統一 durable storage + mutation receipts + owner bridge。新增 state 模組 `hermes_state_worker_lifecycle.py`、`hermes_state_worker_compression.py`、`hermes_state_worker_context.py`、`hermes_state_runtime.py`（state 層 +3,723 行）。

### 1.2 Breaking Changes

**Release Notes 無 `Breaking Changes` / `Deprecation` 章節。** 全篇掃描 `breaking|migrat|upgrade|deprecat|removal|⚠`，命中全部是內部 worker / bot mailbox / fixtures 的資料搬遷，由程式碼自動完成，不涉及使用者設定或 CLI/JSON 介面。

### 1.3 Schema 版本（決定是否不可逆）

| 常數 | v0.22.0 | v0.22.1 | 部署後實測 |
|---|---|---|---|
| `hermes_state_common.py:283 SCHEMA_VERSION` | 31 | 31 | **`state.db` 實際 = 31** ✅ |
| `hermes_state_common.py:306 FTS_STORAGE_VERSION` | 3 | 3 | — |
| `RETIRED_GENERATION_MANIFEST_VERSION` | 1 | 1 | — |

✅ **Schema 未變 → 無人工 DB 遷移、回滾不需預先複製 DB。** 精簡升級路徑成立。

### 1.4 Dependency / Runtime

| 項目 | 變化 |
|---|---|
| `requires-python` | `>=3.11,<3.15` **未變**（實測 `Python 3.14.7` 相容） |
| `pm/lock.json` | **零 diff** → pm 套件版本全不變 |
| `pyproject.toml` | `httpx2==2.7.0 → 2.12.0`（mcp / computer-use / dev 三處） |
| `uv.lock` | +34 行（httpx2 升版 + `httpx2-jsfetch` indirect） |
| 根 `package-lock.json` `overrides` | `{}` → `{}` **位元組相同** |
| `scripts/whatsapp-bridge/package-lock.json` | +169 −121（官方刻意修 npm audit，我們未部署該功能） |

---

## 2. 衝突處理

### 2.1 衝突面

自定義觸及 65 檔 ∩ 上游變更 2,170 檔 = **37 個 `.github/workflows/`（Purge 直接刪）+ 1 個 Dockerfile**。

### 2.2 Dockerfile（唯一實質衝突）🔴

上游在 `@@ -280,7 +280,13 @@` 新增：

```dockerfile
    --cache /opt/hermes/uv-cache \
```

我們的 `@@ -283,7 +296,8 @@` 在同一區段加 baked-in extras → **cherry-pick 必衝突**。

**處置：不盲選 ours/theirs，以 `upstream-v0.22.1` 為基底手動套用 8 處自訂補丁，兩者並存。** 兩項改動語義不相衝：

- 上游 `--cache`：修 uv cache 落在無人讀的 `/root/.hermes/cache/uv` 的問題
- 我們 `--extra ...`：把 edge-tts / firecrawl / dingtalk / feishu / exa 烤進 image

最終 `build_env`：

```dockerfile
RUN python3 -m pm.build_env --source /opt/hermes --python /usr/local/bin/python3 \
    --cache /opt/hermes/uv-cache \
    --out /opt/hermes/.venv --no-install-project --sealed --record-selection \
    --extra all --extra messaging --extra otlp --extra anthropic --extra bedrock \
    --extra azure-identity --extra matrix --extra google-chat \
    --extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa
```

**驗證：`git diff upstream-v0.22.1 HEAD -- Dockerfile` = 恰好 8 個 hunk**（與工作表預期完全一致），11 個標記全部到位。

### 2.3 攜帶的自定義 commit

| 原 commit | 新 commit | 處置 |
|---|---|---|
| `abb31ba773` | `1fc47d42ac` | 🔁 purge 重做（55 → 1 workflow） |
| `9e41629666` | `08fa3fc96e` | ✅ cherry-pick 乾淨 |
| `63e50c9885` | `1e87666e04` | ✅ |
| `8648243390` | `b85ee26ccb` | ✅ |
| `9c0eebd450` | `b4e66c5ecb` | ✅ |
| `4f88c09175` | `be2a5bab24` | 🔴 **手動重做**（Dockerfile 8 補丁） |

**4 個 cherry-pick 零衝突。** 5 個攜帶檔案 blob 雜湊與 `my-config-v0.22.0` **完全相同**：`docker/entrypoint-ssh.sh`、`docker/stage2-hook.sh`、`docker-compose.yml`、`AGENTS.md`、`.github/workflows/ghcr-publish.yml`。

---

## 3. 建置

| 項目 | 值 |
|---|---|
| 推送 | `git push -u kuniakil my-config-v0.22.1` ✅ |
| GitHub Actions Run | **38691266688** |
| `event` | `workflow_dispatch` ✅ |
| `headBranch` | `my-config-v0.22.1` ✅ |
| `headSha` | `81bc37f7965ffd055c966d05bc8b06237977c884` = **我方 HEAD**（官方碼不可能混入）✅ |
| Jobs | prepare / linux-amd64 / linux-arm64 / merge — **全部 success** ✅ |
| Image digest | `sha256:c98934da35a5ea6e26930b6cf5ed843b9b4ca0da877e0aeb5d90f9d33d3776f6` |
| Tags | `ghcr.io/kuniakil/hermes-agent:v0.22.1` + `latest`（registry API HTTP 200 驗證）✅ |

**未 force-push 版本 tag**（分支即 source of truth）。

---

## 4. 部署驗證（n100 K3s）

### 4.1 部署

| 項目 | 結果 |
|---|---|
| k8s overlay | `~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag: v0.22.0 → v0.22.1` |
| render | `kubectl kustomize .` → `ghcr.io/kuniakil/hermes-agent:v0.22.1` ✅ |
| rollout | `successfully rolled out` ✅ |
| Pod | `hermes-agent-86bc5b5899-tkzwx` 1/1 Running，**0 restart**，舊 pod 已 Terminating→移除 |
| Node | n100，IP `10.42.0.118` |

### 4.2 冒煙測試

| 檢查 | 結果 |
|---|---|
| Python runtime | `Python 3.14.7` ✅ |
| locale | `C.utf8`、`en_US.utf8`、`zh_TW.utf8` ✅ |
| openssh-server / rsync / tini | `/usr/sbin/sshd`、`/usr/bin/rsync`、`/usr/bin/tini` ✅ |
| ffmpeg / agent-browser | `/usr/local/bin/ffmpeg`、`/usr/local/bin/agent-browser` ✅ |
| baked-in extras | `edge_tts` ✅、`dingtalk_stream` ✅、`lark_oapi` ✅、`firecrawl` ✅ |
| `sessions.auto_prune: false` | **仍在**（config.yaml 第 507 行，`sessions:` 區塊下）✅ |
| `entrypoint-ssh.sh` 權限 | `-rwxr-xr-x` ✅ |
| sshd 進程 | 存活 ✅ |
| Telegram | `Connected to Telegram (polling mode)` ✅ |
| 啟動日誌 | **0 條 ERROR / Traceback** ✅ |
| 穩定性 | 部署 45s 後仍 ready，0 restart，0 新錯誤 ✅ |

### 4.3 Session authority 重構專項（D5/D6）

本次最大改動是 session authority 重構，故特別驗證舊資料無損：

| 檢查 | 結果 |
|---|---|
| `state.db` `schema_version` | **31**（與升級前一致）✅ |
| `sessions` 資料表 | **127 rows** ✅ |
| `messages` 資料表 | **17,632 rows** ✅ |
| 含歷史訊息的 session | 123 個 ✅ |
| `worker_executions` / `worker_receipts` | 表已建立 ✅（本次新增的 worker 生命週期表） |
| 最新 session 可讀 | ✅（`title='hi'`） |
| config schema 遷移 | `[config-migrate] Migrating config schema 50 -> 51`，自動完成 ✅ |

**結論：127 個既有 session 與 17,632 條訊息在 authority 重構後全部完好可讀，無遺失。**

---

## 5. npm 漏洞決策複驗（承 v0.22.0 §8.3）

| 檢查 | 結果 |
|---|---|
| ① 根 `package-lock.json` `overrides` 前後是否變動 | ❌ **未變動**（皆 `{}`）→ 原決策前提成立 |
| ② 容器內實際 node_modules 樹 | 維持 v0.22.0 實測結論：僅 photon sidecar 一棵真實 runtime 樹，且未啟用 |
| ③ 只對實際存在的樹跑 npm audit | 本次無需重測（暴露面未變） |

額外收穫：官方本次 `Deps: bump the WhatsApp bridge lock past its npm-audit findings` 與 `Doctor: clarify Docker npm audit remediation` —— 已修項目我們本來就沒部署。

**維持「不修」決策，觸發條件不變**：啟用 photon / iMessage sidecar、web dashboard、或 ui-tui（node 執行而非純靜態產物）時必須重評。

---

## 6. 遺留事項

### 6.1 待使用者手動處理

- [ ] `.env` 的 `HERMES_IMAGE` → `ghcr.io/kuniakil/hermes-agent:v0.22.1`
      （該檔受 `**/*.env` 讀取防護，agent 無法代改；僅影響本機 `docker compose` 路徑，k8s 走 overlay `newTag`，已完成）

### 6.2 歷史遺留（本次未觸及）

- [ ] `overlays/mac/kustomization.yaml` 仍停在 `v2026.8.3`

---

## 7. 本次驗證新增的 SOP 教訓

1. **`docker buildx imagetools inspect` 在本機對 ghcr.io 不可靠**（Mac 網路/Docker daemon 限制），會誤報 MISSING。應改用 registry API：
   ```bash
   TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:kuniakil/hermes-agent:pull&service=ghcr.io" | python3 -c "import json,sys;print(json.load(sys.stdin)['token'])")
   curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" \
     -H "Accept: application/vnd.oci.image.index.v1+json" \
     https://ghcr.io/v2/kuniakil/hermes-agent/manifests/<tag>
   ```
2. **`gh api /user/packages/...` 需要 `read:packages` scope**，目前 token 無此權限 → 用 registry API 驗證 tag 存在性。
3. **`config.yaml` 內有多處同名 key**（`cron.auto_prune` 與 `sessions.auto_prune`）。複驗時必須帶上下文行確認所屬區塊，不能只 grep key 名。
4. **上游 Dockerfile 的小改動也可能與自訂補丁重疊**：即使只有 1 個 hunk／+6 行，只要落在同一區段就會讓 cherry-pick 失敗。判斷基準是「行範圍是否重疊」，不是「上游改了幾行」。