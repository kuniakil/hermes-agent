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
2. **執行 Rebase / Cherry-pick**：將目前的 `main` 分支 rebase 到目標官方 Tag。
   ```bash
   git rebase v0.15.0
   ```
   *若有衝突，由 AI 協助分析並解決，優先保留個人自定義邏輯與配置文件。*

### 第三階段：建立新版里程碑分支
1. **測試確認**：確保本地執行 `scripts/run_tests.sh` 通過。
2. **建立新版分支並推回**：
   ```bash
   git branch my-config-v0.15.0
   git push origin my-config-v0.15.0
   ```

---

## 🤖 AI 行為鐵律 (AI Behavior Rules)

- **優先徵求使用者同意 (Prioritize User Permission)**：在修改任何程式碼、設定檔（特別是 `Dockerfile`、`.env`、`config.yaml`）或連線資料庫之前，AI **必須**先在對話框中報告修改計畫，並獲得使用者明確同意後才可動手。
- **動手前必先讀檔 (Look Before You Leap)**：禁止憑空猜測設定檔結構。在進行任何編輯前，AI **必須**先調用 `view_file` 工具閱讀目標檔案內容，理解當前結構後再做修改。
- **功能重疊處理**：若自訂 Commit 的功能已在官方新版本中被原生支援，必須直接捨棄該自訂 Commit，改用官方的設定方式。
- **衝突安全中止 (Safe Rollback)**：
  - 當 `rebase` 或 `cherry-pick` 發生衝突，且無法在 1 輪內自動解決時，必須**立刻執行 `git rebase --abort` 或 `git cherry-pick --abort` 恢復原狀**。
  - 禁止在衝突狀態下憑空猜測並修改程式碼。
  - 中止後，向使用者詳細回報衝突檔案與原因，並提出建議方案，等待使用者指示。
