# Hermes Agent 升級原則與標準作業程序 (SOP)

為了確保 Hermes Agent 的個人 Fork 既能緊跟官方 (upstream) 更新，又能確保個人自定義配置的安全與整潔，請遵循以下原則：

## 1. 核心原則
- **退可守**：在大規模升級（Rebase）前，必須建立備份分支（Checkpoint）。
- **對齊官方 Release**：升級必須以官方的 Release Tag（如 `v0.15.0`）作為基準，而非直接對齊主分支的提交點。
- **線性歷史 (Rebase)**：使用 `rebase` 或 `cherry-pick` 將個人修改重新應用在新的官方 Tag 之上，保持 Git 歷史乾淨。
- **K8s 部署同步**：完成升級並確保測試通過後，同步更新 Kubernetes 中 `hermes` 命名空間的服務與部署。

## 2. 升級標準流程 (Standard Upgrade Workflow)

### 第一階段：準備與備份
1. **清理環境**：刪除本地臨時備份檔。
2. **建立檢查點**：建立備份分支，格式為 `backup/my-config-v[舊版本號]`。
   ```bash
   git branch backup/my-config-v0.14.0
   ```

### 第二階段：同步與對齊
1. **抓取官方進度**：
   ```bash
   git fetch upstream --tags
   ```
2. **建立並切換至新版本分支**（以目標官方 Release Tag 為起點，維持線性歷史且不修改舊分支）：
   ```bash
   git checkout -b my-config-v[新版本號] v[新版本號]
   ```
3. **櫻桃挑選（Cherry-pick）自定義 commits**（依時間序從舊到新套用）：
   ```bash
   git cherry-pick <commit-hash-1> <commit-hash-2> ...
   ```
   *註：絕不使用 `git merge`，確保 Commit 歷史為純粹的單一軸線。*

### 第三階段：測試與觸發 GitHub CI/CD
1. **測試確認**：確保本地執行 `scripts/run_tests.sh` 通過（僅進行 Python 單元測試，**不**在 Mac 本地執行耗時的 Docker image 建置）。
2. **提交與推回**：將自訂 commit、更新後的 `.env` 以及新版升級日誌推送至您的 GitHub 倉庫。
   ```bash
   git push [remote名稱] my-config-v[新版本號]
   ```
3. **觸發 GitHub CI/CD**：使用 GitHub CLI 觸發 `ghcr-publish.yml` 來進行多平台映像檔建置，並指定對應的 Docker image tag。
   ```bash
   gh workflow run ghcr-publish.yml --repo [帳號]/hermes-agent --ref my-config-v[新版本號] -f tag_name=v[新版本號]
   ```

## 3. 常見衝突與合併指引 (Conflict Resolution Guide)

當升級時在 `cherry-pick` 自定義提交發生衝突，請依照以下原則進行手動合併：

### A. `Dockerfile` 衝突
* **衝突場景**：官方 upstream 更新了系統套件（`apt-get install` 內容增加），與自定義的 SSH 套件安裝與 `NODE_OPTIONS` 設定衝突。
* **解決方式**：
  1. 將官方新增的依賴套件（如 `iputils-ping` 等）與我們自定義的 `openssh-server` **合併在同一個 `apt-get install` 列表內**。
  2. 確保 `mkdir -p /var/run/sshd && ssh-keygen -A` 初始化指令緊隨其後。
  3. 保留自定義的 Node 記憶體限制環境變數 `ENV NODE_OPTIONS="..."`。

### B. `docker/stage2-hook.sh` 衝突
* **衝突場景**：官方 upstream 增加了對 `docker run --user` 的安全防錯檢測，與自定義的 SSH 伺服器啟動邏輯位置重疊。
* **解決方式**：
  * **兩者共存**：保留官方的 `--user` 啟動防錯檢測（若不合規會 exit 1）。在其下方（確認以 root 引導後），再安全地植入我們的 SSH 伺服器配置與 `/usr/sbin/sshd` 背景啟動邏輯。

---

## 🤖 AI 行為鐵律 (AI Behavior Rules)

- **優先徵求使用者同意 (Prioritize User Permission)**：在修改任何程式碼、設定檔（特別是 `Dockerfile`、`.env`、`config.yaml`）或連線資料庫之前，AI **必須**先在對話框中報告修改計畫，並獲得使用者明確同意後才可動手。
- **動手前必先讀檔 (Look Before You Leap)**：禁止憑空猜測設定檔結構。在進行任何編輯前，AI **必須**先調用 `view_file` 工具閱讀目標檔案內容，理解當前結構後再做修改。
- **功能重疊處理**：若自訂 Commit 的功能已在官方新版本中被原生支援，必須直接捨棄該自訂 Commit，改用官方的設定方式。
- **衝突安全中止 (Safe Rollback)**：
  - 當 `rebase` 或 `cherry-pick` 發生衝突，且無法在 1 輪內自動解決時，必須**立刻執行 `git rebase --abort` 或 `git cherry-pick --abort` 恢復原狀**。
  - 禁止在衝突狀態下憑空猜測並修改程式碼。
  - 中止後，向使用者詳細回報衝突檔案與原因，並提出建議方案，等待使用者指示。
