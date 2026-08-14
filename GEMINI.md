# Hermes Agent 升級原則與標準作業程序 (SOP)

為了確保 Hermes Agent 的個人 Fork 既能緊跟官方 (upstream) 更新，又能確保個人自定義配置的安全與整潔，請遵循以下原則：

## 1. 核心原則

- **退可守**：在大規模升級前，必須建立備份分支（Checkpoint）。
- **對齊官方 Release**：升級必須以官方的 Release Tag（如 `v2026.6.19`）作為基準，而非直接對齊主分支的提交點。
- **線性歷史 (Cherry-pick)**：使用 `cherry-pick` 將個人修改重新應用在新的官方 Tag 之上，保持 Git 歷史乾淨。絕不使用 `git merge`。
- **不在本地建置 Docker image**：Mac 本地只執行 Python 單元測試（如有需要），Docker image 統一推送至 GitHub 由 CI/CD 建置。
- **K8s 部署同步**：CI/CD build 完成後，同步更新 Kubernetes 中 `hermes` 命名空間的服務與部署。

## 2. 升級標準流程 (Standard Upgrade Workflow)

### 第零步：升級前分析

在動手前，先確認官方變更與潛在衝突：

```bash
# 抓取官方最新 tags
git fetch origin --tags

# 確認 tag 存在
git tag -l "v<新版本>"

# 取得目前的 custom commits 清單（由舊到新）
git log --oneline my-config-v<舊版本> ^v<舊版本>

# 預覽官方對關鍵 Docker 檔案的修改
git diff v<舊版本> v<新版本> -- Dockerfile docker/stage2-hook.sh
```

### 第一步：建立備份分支

```bash
git branch backup/my-config-v<舊版本>
```

### 第二步：從官方 Tag 建立新分支

```bash
git checkout -b my-config-v<新版本> v<新版本>
```

> ⚠️ 注意：此時 HEAD 指向官方 Tag，尚未套用任何自定義 commits。

### 第三步：依序 Cherry-pick 自定義 commits

```bash
# 依時間序（舊 → 新）逐一套用
git cherry-pick <commit-hash-1>
git cherry-pick <commit-hash-2>
# ...
```

**衝突處理規則：**

1. 發生衝突時，**先讀衝突內容**（`view_file` 或 `cat`），再判斷合併策略
2. 合併原則：**兩側都要保留**（官方新增的功能 + 我們的自定義）
3. 修改完後：`git add <衝突檔案>` → `git cherry-pick --continue --no-edit`
4. 若衝突超過 1 輪無法解決：**立即 `git cherry-pick --abort`**，回報使用者

### 第四步：更新 `.env` 版本號並 commit

```bash
# 編輯 .env，將 HERMES_IMAGE 版本號改為新版本
# HERMES_IMAGE=ghcr.io/kuniakil/hermes-agent:v<新版本>

git add .env
git commit -m "chore: bump HERMES_IMAGE tag to v<新版本>"
```

### 第五步：補回遺失的歷史升級記錄

> 每次從新 Tag 建立分支時，若舊的升級記錄不在官方 Tag 內，需手動 `git add` 補回。

```bash
# 確認所有歷史升級記錄都在 working tree
ls UPGRADE_LOG_*.md

# 若有遺失，用 git show 從舊分支取回
git show my-config-v<舊版本>:UPGRADE_LOG_<舊>.md > UPGRADE_LOG_<舊>.md
git add UPGRADE_LOG_*.md
```

### 第六步：建立本次升級記錄

建立 `UPGRADE_LOG_v<舊版本>_to_v<新版本>.md`，記錄：
- 官方版本變更摘要
- 套用的 custom commits 清單（含新 commit hash 對照）
- 發生的衝突與解決方式
- 測試結果

### 第七步：commit 所有文件並推送

```bash
git add UPGRADE_LOG_v<舊版本>_to_v<新版本>.md UPGRADE_LOG_*.md GEMINI.md
git commit -m "docs: add upgrade log v<舊版本> to v<新版本>"

git push kuniakil my-config-v<新版本>
```

### 第八步：觸發 GitHub CI/CD

```bash
gh workflow run ghcr-publish.yml \
  --repo kuniakil/hermes-agent \
  --ref my-config-v<新版本> \
  -f tag_name=v<新版本>
```

---

## 3. 常見衝突與合併指引 (Conflict Resolution Guide)

當升級時 `cherry-pick` 發生衝突，請依照以下原則手動合併：

### A. `Dockerfile` — apt-get install 衝突

- **衝突場景**：官方新增系統套件（如 `libatomic1`），與我們自定義的 `openssh-server`、`ssh-keygen -A` 等在同一行衝突。
- **解決方式**：**合併雙方所有套件**在同一個 `apt-get install` 列表內。

  ```dockerfile
  # 保留格式：官方套件 + 我們的套件，全部在同一行
  ca-certificates curl iputils-ping python3 python-is-python3 ripgrep ffmpeg \
  gcc g++ make cmake python3-dev python3-venv libffi-dev libolm-dev libatomic1 \
  procps git openssh-client openssh-server docker-cli xz-utils && \
  mkdir -p /var/run/sshd && ssh-keygen -A && \
  rm -rf /var/lib/apt/lists/*
  ```

  確保同時保留：
  - `openssh-server`（SSH 伺服器）
  - `mkdir -p /var/run/sshd && ssh-keygen -A`（SSH 初始化）
  - `ENV NODE_OPTIONS="--max-old-space-size=4096"`（記憶體限制）
  - `libatomic1`（官方新增依賴）

### B. `Dockerfile` — COPY / ENTRYPOINT 衝突

- **衝突場景**：官方 v2026.8.3 起 ENTRYPOINT 改為 `entrypoint-dispatch.sh`（非直接 `/init`），且 Node 從 22 升級到 26（corepack 移除）。
- **解決方式**：接受官方 `entrypoint-dispatch.sh` 和 Node 26，額外 COPY 我們的 `entrypoint-ssh.sh`：

  ```dockerfile
  COPY --chmod=0755 docker/hermes-exec-shim.sh /opt/hermes/bin/hermes
  COPY --chmod=0755 docker/entrypoint-dispatch.sh /opt/hermes/docker/entrypoint-dispatch.sh
  COPY --chmod=0755 docker/entrypoint-ssh.sh /opt/hermes/docker/entrypoint-ssh.sh
  ENTRYPOINT [ "/opt/hermes/docker/entrypoint-dispatch.sh" ]
  ```

### C. `docker/stage2-hook.sh` 衝突

- **衝突場景**：官方新增 `tree_has_non_hermes_owner()` 和 warm-boot chown 優化，行號大幅移位。
- **解決方式**：不要 cherry-pick 舊 commit，改為在官方版本上**手動重新插入** SSH setup block（在 `--user` 安全防錯 `fi` 之後、`Bootstrap HERMES_HOME as root` 之前）和 PYTHONPATH block（在檔案末尾 `Setup complete` 之前）。

### D. `docker/entrypoint-ssh.sh` — 功能被官方覆蓋

- **衝突場景**：官方 `entrypoint-dispatch.sh` 已原生處理 non-PID 1 環境（Zeabur、Fly Machines 等）。
- **解決方式**：將 `entrypoint-ssh.sh` 簡化為純粹委派給 `entrypoint-dispatch.sh` 的包裝腳本，僅保留向後相容性。SSH 啟動邏輯統一由 `stage2-hook.sh` 處理。

---

## 4. 我們的自定義 Commits 清單（相對 v2026.8.13）

以下為套用在官方 `v2026.8.13` Tag 上的所有自定義 commits：

| 功能 | 描述 |
|------|------|
| SSH + 建置工具鏈整合 | Dockerfile 加入 `openssh-server`、`ssh-keygen`、`NODE_OPTIONS`；`stage2-hook.sh` 整合 SSH 啟動 + `HERMES_TUI_DIR` export + `faster-whisper` PYTHONPATH；簡化版 `entrypoint-ssh.sh` 委派給官方 `entrypoint-dispatch.sh` |
| UTF-8 / Locales & rsync 支援 | Dockerfile 加入 `rsync` 與完整的 `zh_TW.UTF-8` / `en_US.UTF-8` locale 設定 |
| Playwright Full Chromium 支援 | Dockerfile 安裝完整版 Playwright Chromium 並賦予權限 |
| `.env` with HERMES_IMAGE | docker-compose 使用的 image tag 設定 |
| ghcr-publish workflow | GitHub Actions 自動建置並推送多平台 Docker image |
| docker-compose.yml | 還原為自定義版本 |

---

## 🤖 AI 行為鐵律 (AI Behavior Rules)

- **優先徵求使用者同意 (Prioritize User Permission)**：在修改任何程式碼、設定檔（特別是 `Dockerfile`、`.env`、`config.yaml`）或連線資料庫之前，AI **必須**先在對話框中報告修改計畫，並獲得使用者明確同意後才可動手。
- **動手前必先讀檔 (Look Before You Leap)**：禁止憑空猜測設定檔結構。在進行任何編輯前，AI **必須**先調用 `view_file` 工具閱讀目標檔案內容，理解當前結構後再做修改。
- **衝突前先分析**：在開始 cherry-pick 前，必須先用 `git diff v<舊> v<新> -- Dockerfile` 預覽官方對關鍵檔案的修改，評估潛在衝突點。
- **功能重疊處理**：若自訂 Commit 的功能已在官方新版本中被原生支援，必須直接捨棄該自訂 Commit，改用官方的設定方式。
- **衝突安全中止 (Safe Rollback)**：
  - 當 `cherry-pick` 發生衝突，且無法在 1 輪內自動解決時，必須**立刻執行 `git cherry-pick --abort` 恢復原狀**。
  - 禁止在衝突狀態下憑空猜測並修改程式碼。
  - 中止後，向使用者詳細回報衝突檔案與原因，並提出建議方案，等待使用者指示。
- **補回升級記錄**：每次升級完成後，必須確認所有歷史 `UPGRADE_LOG_*.md` 均已加入 git tracking，不可遺失。
