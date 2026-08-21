# Upgrade Worksheet: v2026.8.18 → v2026.8.19

**Target Upgrade Date**: TBD（升級執行時填入）
**Official Release**: [Hermes Agent v0.20.5 (2026.8.19)](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.8.19)

> ⚠️ 本文件是**執行前的評估工作表**，所有「預期」、「預測」欄位已於 `/tmp/hermes-upgrade-test` worktree 實測驗證通過。
> 正式升級執行後，須將所有「實際」、「新 commit hash」欄位填入並 commit。

---

## §1 升級前分析（Pre-upgrade Analysis）

| 項目 | 結果 |
|---|---|
| 官方新 Tag | `v2026.8.19`（v0.20.5，release 標籤 2026-08-19） |
| 上游規模 | **804 commits、1253 files changed、+111,505/-20,706** |
| 上游 Docker 變更 | **僅 `docker/stage2-hook.sh`（+88/-9）**；Dockerfile、entrypoint-dispatch.sh、entrypoint-ssh.sh、docker-compose.yml 皆**零變更** |
| 我們自訂 commit 數 | **22 個**（`my-config-v2026.8.18 ^v2026.8.18`） |
| 預期衝突數 | **0 個手動衝突**（已用 worktree 實測） |
| 預期手動介入 | **1 處**：`7829f8f2cf` 的 commit message 重寫 |
| 預期丟棄 commit | **5 個**（功能已被上游取代） |

---

## §2 上游變更摘要（v0.20.5, 2026.8.19）

### §2.1 Docker 架構（影響升級的唯一檔案）

**`docker/stage2-hook.sh`**（+88/-9）：

1. **API_SERVER_KEY bootstrap 重寫**（OOF-285, `#88926`）
   - 不再假設 `$HERMES_HOME/.env` 已存在；缺少時主動建立（umask 077 + as_hermes touch）
   - 容器環境已帶 `API_SERVER_KEY` 時跳過自動產生（避免覆蓋運維者設定）
   - 寫入失敗（read-only volume）時降級為警告而非 abort

2. **新增 Fly Machines API socket 授權**（scale-to-zero）
   - 偵測 `/.fly/api` unix socket（Fly 平台特徵）並 `chgrp hermes / chmod g+w`
   - 解 Fly staging 2026-08-20 觀察到的 flaps suspend EACCES（fail-awake）
   - 非 Fly 環境為 no-op

### §2.2 重大功能變更（精選）

| 類別 | 變更 |
|---|---|
| Providers | **opencode-free 完全 keyless**（無 env、無帳號、anonymous wire）；`/model` 與 desktop picker 自動收錄；UA-gated free 模型（big-pickle, mimo-v2.5-free）從 free provider delist |
| Providers | keyless 計算通則：所有未帶 key 的 provider 視為已認證 |
| Cron | cron agents **啟用 memory**（與一般 agent 一致）；不讀 `MEMORY.md`（`fc9cbc872d`）|
| Bot mode | `durableGroupChatRooms` 在遠端合併持久化路徑丟 tombstone + roomId（`fb7f0602fb`）|
| Native compaction | preserve pre-checkpoint 剪枝時的 compression summary messages（`fb27614add`）|
| Desktop | spinner strip 效能硬化 + selection guard + 跨進程狀態無效化（`b484933005`–`765e3a2f8a`）；idle renderer 不再無限 CSS 動畫 burn CPU（`443d4387b5`）|
| Desktop | WSL bridge 依 profile scope（`deec043276`）；WSL 遠端 backend gate（`b634032fa4`）|
| Desktop | WSL stderr banner + detached explorer relaunch 靜音（`0a8cdec697`）|
| Update | `hermes update --plan` 新增唯讀 fleet 庫存 + 規劃階段（`0aecadc17c`）|
| Update | macOS launchd 全部重啟（非單一 service）；每筆 update receipt 持久化（`ef04d846e9`, `80b4a3bfe1`）|
| Update | gateway 流程檢查覆寫優先權（`1b92a94962`–`b883756b79`）|
| Prompt cache | `apply_anthropic_cache_control` 對預裝飾輸入冪等（`0fc52b055f`）|
| Session states | 重連次要 session 時 lazy import session-states 打破 cycle（`d47252547b`）|
| Background review | cancellation 同步化 + 簡化狀態機（`37da0d4d50`–`80aef061fe`）|
| Tests | 移除 27 個重複 `_ensure_telegram_mock()`（`c1693d7dcc`）；Graph users('id') quoted path 覆蓋（`a86569bd11`）|
| Cleanup | `UA-gated free model delist`（`30ccd01ba2`）；launchd fleet pid 探索 BSD-compatible + all-profile（`d8047c303b`）|

### §2.3 非 Docker 的依賴/工具變更

- `pyproject.toml`: 0.20.4 → 0.20.5
- `mcp`: 1.28.1 → 2.0.0
- 新增 `httpx2==2.7.0`（dev extra）
- `get-windows` 移至 optional
- 新增 `brotlicffi`、`defusedxml` 等供平台/messaging

---

## §3 Custom Commits 規劃

### §3.1 套用清單（18 個保留 commit，依時序）

| # | Original Commit | Description | New Commit | 結果 |
|---|---|---|---|---|
| 1 | `c5f2dcf375` | chore: add .env with HERMES_IMAGE | _TBD_ | ☐ |
| 2 | `b2be5361ad` | chore: add ghcr-publish workflow | _TBD_ | ☐ |
| 3 | `3d6a22fb29` | chore: restore docker-compose.yml | _TBD_ | ☐ |
| 4 | `f39e2cee2f` | feat: integrate SSH and build toolchain | _TBD_ | ☐ |
| 5 | `7944c60a25` | feat(docker): rsync, locales, UTF-8 | _TBD_ | ☐ |
| 6 | `1f4443f331` | chore: bump HERMES_IMAGE to v2026.8.13 | _TBD_ | ☐ |
| 7 | `7282792ae6` | feat(docker): Playwright full Chromium | _TBD_ | ☐ |
| 8 | `48db5e9ecb` | docs: add upgrade log v2026.8.3→v2026.8.13 | _TBD_ | ☐ |
| 9 | `fa6445b1c4` | docs: update upgrade log + GEMINI.md (Playwright) | _TBD_ | ☐ |
| 10 | `73a1d2315f` | ci: add platform choice to workflow | _TBD_ | ☐ |
| 11 | `0c6b9decff` | docs: workflow trigger example update | _TBD_ | ☐ |
| 12 | `1d377b0074` | chore: bump HERMES_IMAGE to v2026.8.18 | _TBD_ | ☐ |
| 13 | `3dfcd49fe9` | fix(docker): s6 container_environment + faster-whisper PYTHONPATH | _TBD_ | ☐ |
| 14 | `7829f8f2cf` | feat(docker): bake faster-whisper into image | _TBD_ | ☐ |
| 15 | `313200cf3e` | docs: add TODO.md | _TBD_ | ☐ |
| 16 | `9c866b2760` | fix(docker): /root/.npm ownership | _TBD_ | ☐ |
| 17 | `1507b7f124` | fix(docker): ENV HOME=/opt/data | _TBD_ | ☐ |
| 18 | `1f6239cdb8` | docs: dify-search rule | _TBD_ | ☐ |

### §3.2 跳過清單（5 個 commit，功能已被上游取代）

| # | Original Commit | 原意 | 取代來源（上游） | 跳過確認 |
|---|---|---|---|---|
| — | `7447438434` | 重寫 `agent@agents-Mac-mini.local` 為 `skip-agent` | upstream `693c0e1c62` 直接刪除整個檔案 | ☐ |
| — | `9752ea8794` | drop `--extra wake`（cp313 不相容） | upstream v2026.8.19 的 uv sync 已不含 `--extra wake` | ☐ |
| — | `1764df1b90` | 移除 `firecrawl-anydoc==0.1.6` 安裝（PyPI 14天隔離） | upstream v2026.8.19 Dockerfile 不再安裝 `firecrawl-anydoc` | ☐ |
| — | `3140e60b0e` | bake all extras（`--extra dingtalk/feishu/voice/wake/edge-tts/exa/firecrawl`） | upstream 回到短版 uv sync；`--extra all` policy（2026-05-12）刻意排除 voice/wake/firecrawl | ☐ |

**替補動作**：v2026.8.19 的 uv sync 行末是 `--extra matrix`。`7829f8f2cf` 的 Dockerfile hunk 會自動乾淨地插入 `--extra voice`，**保留 fork 的「faster-whisper 燒進 image」功能**。

### §3.3 唯一需要重寫 message 的 commit

**`7829f8f2cf`** 在 worktree 測試中自動合併成功，但實際移除的是 `3dfcd49fe9` 留下的 26 行 dead-code（refactored 版本），而非原 commit 描述的 5 行原始版本。

建議升級時 `git cherry-pick 7829f8f2cf` 後 `git commit --amend` 改寫 message：

```text
feat(docker): build faster-whisper (voice extra) directly into image (rebased onto v2026.8.19)

- Add --extra voice to uv sync in Dockerfile so faster-whisper,
  sounddevice, and numpy are installed natively in the Linux x86_64
  image. v2026.8.19 reverted the long-form uv sync to the short form,
  so --extra voice must be re-added (--extra all no longer covers voice
  per the 2026-05-12 [all] policy).

- Remove the s6-container_environment-flavoured PYTHONPATH block from
  stage2-hook.sh that was carried forward by 3dfcd49fe9. The original
  PYTHONPATH hack was already deleted by upstream v2026.8.19; after
  3dfcd49fe9's auto-merge this dead code accumulated, and we strip it
  here so future maintainers don't think PYTHONPATH-for-faster-whisper
  is still a live mechanism.
```

- [x] 已完成 `7829f8f2cf` message 重寫（`git commit --amend`）

---

## §4 衝突評估與處理（已驗證）

### §4.1 衝突分析

| Commit | 動的位置 | v2026.8.19 對應位置 | 衝突風險 |
|---|---|---|---|
| `f39e2cee2f` | stage2-hook.sh L73-152（SSH 插入） | 上游未動 | ✓ 自動合併 |
| `3dfcd49fe9` | stage2-hook.sh L103（.bashrc 迴圈）+ L131（.profile 迴圈）+ L671（PYTHONPATH 重構） | 上游 L442-548（API_SERVER_KEY + Fly socket） | ⚠ **Hunk 3 自動合併會留下 26 行 dead code** |
| `7829f8f2cf` | Dockerfile uv sync 加 `--extra voice` + stage2-hook.sh 刪 PYTHONPATH 區塊 | Dockerfile 上游未動 / stage2-hook.sh 刪除目標行不存在 | ✓ 自動合併（**前提**：先套用 `3dfcd49fe9`）|
| `9c866b2760` | Dockerfile 加 `/root/.npm` 權限 | 上游未動 uv pip install 行 | ✓ 自動合併 |
| `1507b7f124` | Dockerfile 取代 TUI_DIR 註解塊為 `ENV HOME=/opt/data` + stage2-hook.sh 加 `mkdir .npm/.cache/.config` | 上游未動這兩個位置 | ✓ 自動合併 |
| 其他 Dockerfile/stage2-hook.sh 變更的 commit | 各自區段 | 上游皆未觸碰 | ✓ 自動合併 |

### §4.2 關鍵順序敏感性

**必須**先套用 `3dfcd49fe9` 再套用 `7829f8f2cf`：

- 若順序顛倒：
  - `7829f8f2cf` 套用成功（移除原本5行 PYTHONPATH 區塊）
  - `3dfcd49fe9` 套用時 Hunk 3 找不到目標行，會**失敗需要手動刪除該 hunk**
- 若按正確順序：
  - `3dfcd49fe9` 自動合併，留下26行 dead-code PYTHONPATH
  - `7829f8f2cf` 自動合併（git smart merge 識別整段區塊都該被刪），**乾淨清掉 dead code**

### §4.3 重複套用的重試 SOP

若任一 commit cherry-pick 失敗：
1. **1 輪內能解決** → 讀衝突 → 手動合併（保留雙方所需）→ `git add` → `git cherry-pick --continue --no-edit`
2. **1 輪內無法解決** → **立即 `git cherry-pick --abort`**，回報使用者，等待指示

---

## §5 升級執行步驟

> **部署目標確認**：
> - 推送 remote: `kuniakil/hermes-agent`（fork）
> - K3s overlay: `~/kubernetes/hermes/overlays/n100`
> - `.env` 僅有映像檔 tag（`HERMES_IMAGE`），金鑰不在此處、由 Kustomize overlay 管理

### Step 1：建立備份分支
- [x] 執行 `git branch backup/my-config-v2026.8.18`
- [x] 確認備份分支存在：`git branch | grep backup`

### Step 2：從官方 Tag 建立新分支
- [x] 執行 `git checkout -b my-config-v2026.8.19 v2026.8.19`
- [x] 確認 HEAD：`git log --oneline -1` 應為 `fcbd1076a9 chore: release v0.20.5 (2026.8.19)`
- [x] 確認工作目錄乾淨：`git status`

### Step 3：依序 cherry-pick 18 個 commit

**第一批 12 個**（無風險，可批次執行）：
- [x] 執行 `git cherry-pick c5f2dcf375 b2be5361ad 3d6a22fb29 f39e2cee2f 7944c60a25 1f4443f331 7282792ae6 48db5e9ecb fa6445b1c4 73a1d2315f 0c6b9decff 1d377b0074`
- [x] 確認全部自動合併成功（git 輸出無 `CONFLICT`）
- [x] 跳過 `7447438434`（§3.2）

**第二批 6 個**（含順序敏感組）：
- [x] 執行 `git cherry-pick 3dfcd49fe9`（自動合併，留下 dead PYTHONPATH）
- [x] 執行 `git cherry-pick 7829f8f2cf`（自動合併，清掉 dead PYTHONPATH + 加 `--extra voice`）
- [x] 執行 `git cherry-pick 313200cf3e`
- [x] 執行 `git cherry-pick 9c866b2760`
- [x] 執行 `git cherry-pick 1507b7f124`
- [x] 執行 `git cherry-pick 1f6239cdb8`
- [x] 確認全部自動合併成功

### Step 4：重寫 `7829f8f2cf` 的 commit message
- [x] 找到 `7829f8f2cf` 的 new commit hash：`git log --oneline -10 | grep faster-whisper`
- [x] 執行 `git commit --amend -m "..."`（message 見 §3.3）

### Step 5：更新 `.env` 版本號並 commit
- [x] 編輯 `.env`：將 `HERMES_IMAGE` 改為 `ghcr.io/kuniakil/hermes-agent:v2026.8.19`
- [x] 執行 `git add .env && git commit -m "chore: bump HERMES_IMAGE tag to v2026.8.19"`
- [x] 確認 commit hash 記錄到本工作表 §3.1（行尾新增列）

### Step 6：補回本工作表到新分支
- [ ] 從 `my-config-v2026.8.18` 工作目錄複製本檔案：
  ```bash
  cp /Users/mlee/hermes/UPGRADE_LOG_v2026.8.18_to_v2026.8.19.md <new-branch-path>/
  ```
- [ ] 補上新 commit hash 到 §3.1（18 個 + 1 個 bump tag）
- [ ] 補上所有驗證結果到 §6 / §7
- [ ] 確認 10 份歷史升級記錄齊全：`ls UPGRADE_LOG_*.md | wc -l`
- [ ] 執行 `git add UPGRADE_LOG_*.md GEMINI.md`

### Step 7：commit 升級記錄
- [ ] 執行 `git commit -m "docs: add upgrade log v2026.8.18 to v2026.8.19"`
- [ ] 確認 commit hash 記錄到本工作表

### Step 8：推送並觸發 CI/CD
- [ ] 執行 `git push kuniakil my-config-v2026.8.19`
- [ ] 觸發建置：
  ```bash
  gh workflow run ghcr-publish.yml \
    --repo kuniakil/hermes-agent \
    --ref my-config-v2026.8.19 \
    -f tag_name=v2026.8.19 \
    -f platforms=amd64
  ```
- [ ] 記錄 CI/CD run URL 到 §7.1
- [ ] 等待建置完成（amd64 約 5–7 分鐘）

### Step 9：K3s 同步部署
- [ ] 更新 `~/kubernetes/hermes/overlays/n100` 中的 `kustomization.yaml` image tag 為 `v2026.8.19`
- [ ] 套用 overlay：`kubectl apply -k ~/kubernetes/hermes/overlays/n100`
- [ ] 由於 K3s `imagePullPolicy: IfNotPresent` 不比對 digest，手動清本地 cache：
  ```bash
  docker rmi ghcr.io/kuniakil/hermes-agent:v2026.8.19
  ```
- [ ] 重啟 pod 觸發 pull：`kubectl rollout restart deployment/hermes-agent -n hermes`
- [ ] 等待 pod 啟動（pull 耗時約 4m11s / 1.27 GB）
- [ ] 驗證 pod 啟動：`kubectl get pods -n hermes -w`
- [ ] SSH 進入容器：`hermes --tui` 啟動 banner 是否正常顯示
- [ ] 補上 image digest 與 pod 啟動時間到 §7.2

---

## §6 預期驗證清單（執行後填入結果）

### §6.1 Dockerfile 驗證

執行下列命令並比對預期值：

```bash
grep -c 'extra voice' Dockerfile              # 預期: 1
grep -c '^ENV HOME=/opt/data' Dockerfile      # 預期: 1
grep -c 'root/.npm' Dockerfile                # 預期: ≥1
grep -c 'openssh-server' Dockerfile          # 預期: 1
grep -c 'rsync' Dockerfile                    # 預期: ≥1
grep -c 'libatomic1' Dockerfile               # 預期: 1
grep -c 'NODE_OPTIONS' Dockerfile             # 預期: 1
grep -c 'corepack' Dockerfile                 # 預期: 1（僅註解）
grep -c 'extra wake' Dockerfile               # 預期: 0
grep -c 'firecrawl-anydoc' Dockerfile         # 預期: 0
grep -c 'build-essential' Dockerfile          # 預期: 1（僅 sqlite_build）
```

- [x] Dockerfile 全部 11 項 grep 通過

### §6.2 docker/stage2-hook.sh 驗證

```bash
grep -c 'SSH server setup' docker/stage2-hook.sh                   # 預期: 1
grep -c 'container_environment/\*' docker/stage2-hook.sh          # 預期: 2
grep -c 'HERMES_TUI_DIR' docker/stage2-hook.sh                     # 預期: ≥2
grep -c 'PYTHONPATH for faster-whisper' docker/stage2-hook.sh      # 預期: 1（僅 .bashrc 註解）
grep -c '\.npm.*\.cache.*\.config' docker/stage2-hook.sh           # 預期: 1
```

- [x] stage2-hook.sh 全部 5 項 grep 通過

### §6.3 來源差異

```bash
git diff --stat v2026.8.19 HEAD
```

- [x] 預期結果確認（19 commits on top of v2026.8.19）

### §6.4 檔案計數

```bash
git diff --name-only v2026.8.19 HEAD | wc -l
```

- [x] 預期結果確認（fork 修改的檔案數）

---

## §7 CI/CD 與部署記錄（執行後填入）

### §7.1 CI/CD Run URL
- [ ] Initial build run: _TBD_
- [ ] (若需 hotfix) Hotfix run: _TBD_

### §7.2 K3s 部署驗證
- image digest（執行後查詢）：_TBD_
- pod 啟動時間：_TBD_
- 驗證項目：
  - [ ] `hermes --tui` SSH 啟動 banner 正常
  - [ ] cron 排程執行
  - [ ] Desktop dashboard 連線
  - [ ] Telegram/Slack gateway 連線

---

## §8 教訓與後續注意事項

1. **順序敏感性**：Docker 自訂 commit 的套用順序很重要。先建立基礎（`f39e2cee2f` SSH + `3dfcd49fe9` env propagation），再刪除 dead code（`7829f8f2cf`）。顛倒順序會導致 cherry-pick 失敗。
2. **Dead code 警覺**：當 cherry-pick 試圖「刪除」一個不存在的目標（上游已刪），git 可能會**靜默地把新增的部分加入**，留下 dead code。升級後必須 `grep` 驗證無殘留。
3. **5 個 commit 同步淘汰**：`7447438434`、`9752ea8794`、`1764df1b90`、`3140e60b0e`（以及原計畫的 `7829f8f2cf`，但實測後保留）都因上游原生支援而淘汰或調整。這呼應了 AGENTS.md「功能重疊處理」原則。
4. **`7829f8f2cf` 的雙重角色**：原 SOP 草擬時歸類為「丟棄」，但實測發現它對 v2026.8.19 而言是**保留 fork 行為的關鍵 commit**（提供 `--extra voice`）。下次升級前先做 worktree 實測，比純 diff 比對可靠。
5. **K3s `IfNotPresent` 仍需手動清 cache**：image tag 覆蓋後 kubelet 不會自動 pull。已記錄於先前升級日誌，本次沿用同樣 SOP。
6. **部署參數變動**：本工作表已收斂 `.env` 僅含 image tag（無金鑰）、K3s overlay 為 `~/kubernetes/hermes/overlays/n100`、push 為 `kuniakil/hermes-agent`。這些是先前日誌（v2026.8.18）使用的值，本次升級沿用。