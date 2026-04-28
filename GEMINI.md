# Hermes Agent Project Guidelines & Upgrade Context

本文檔記錄了本專案的特定開發規範、環境配置及技術升級歷史，供 Gemini CLI 與開發者參考。

## 🚀 專案狀態 (截至 2026-04-25)
- **核心版本**: v0.11.0 (Hermes-Agent v2026.4.23)
- **部署環境**: Docker (MacOS 宿主機)
- **遠端倉庫**: `kuniakil` (GitHub)
- **CI/CD**: GitHub Actions (Matrix Build + Manifest Merge)

## 🛠️ 重大技術修正 (踩雷紀錄)

### 1. Docker 建構與 TUI 組件修復
*   **問題**: 升級後 TUI 缺失 `ink-bundle.js` 導致當機。
*   **解決方案**: 
    - 重構 `Dockerfile` 確保 `COPY . .` 優先於建構步驟。
    - 全域安裝 `esbuild` 與 `typescript`。
    - **強行手動建構**: 進入 `ui-tui/packages/hermes-ink` 顯式產出 bundle，並使用 `npx tsc` 編譯 `ui-tui`。
*   **路徑驗證**: 建構腳本中加入了 `ls -l` 強制檢查，防止 broken image 推送到 GHCR。

### 2. 權限與進程管理
*   **權限修復**: 實作了 `chmod -R a+rX /opt/hermes`，解決了 Node 模組被鎖在 root 權限下導致的 `Cannot find module` 錯誤。
*   **進程管理**: 加入了 `tini` 作為 Entrypoint 封裝，處理僵屍進程（Zombie Processes），提高長效運行穩定性。

### 4. SSH 服務整合與自動化 (2026-04-27)
*   **整合問題**: 原先 SSH 啟動需手動下指令且容易遺失 `gateway run` 參數。
*   **解決方案**: 
    - 實作了 `docker/entrypoint-ssh.sh`，負責在啟動時先行拉起 `sshd`。
    - **參數透傳**: 使用 `exec ... "$@"` 確保 `docker-compose.yml` 中的 `command` 能被正確傳遞至底層 `entrypoint.sh`，解決了 Gateway 無法自動啟動的 Bug。
    - **環境變數自動化**: 在 `entrypoint-ssh.sh` 中加入自動生成 `.bashrc` 與 `.profile` 的邏輯，解決了 SSH 登入後無法讀取 `.env` 與 `hermes` 路徑的問題。
*   **正式化**: 此功能已從 `ssh` 實驗分支合併回 `my-config-*` 主線，並成為正式影像 `v2026.4.23` 的標配功能，部署時只需指定 `command: gateway run` 即可自動啟動 SSH 服務。

## 📋 維護與升級規範

### 1. 升級 SOP
*   下次升級請參閱 `data/hermes_upgrade/UPGRADE_STRATEGY.md`。
*   必須保留 `Dockerfile` 中自定義的建構順序與權限修正。
*   務必維持 GitHub Actions 中的 Matrix Build 邏輯以避免 OOM。

### 2. 嚴格影像重建規則 (Image Build Freeze) 🚨
*   **先商量、後執行**：禁止在未經開發者明確核准的情況下，進行任何會觸發 Docker 影像重建（Rebuild）的修改。
*   **跨平台相容性優先**：任何修改必須同時考慮 Mac (Docker Desktop) 與 Zeabur (VPS) 的執行環境差異，嚴禁「顧此失彼」。
*   **環境差異化啟動規範**：
    - **Mac 端**：使用 `docker-compose.yml` 預設的 `command: gateway run`。
    - **Zeabur 端**：由於環境特殊會繞過 Entrypoint，必須在 Zeabur 界面指定啟動指令為：
      `sh -c "mkdir -p /run/sshd && /usr/sbin/sshd && /opt/hermes/.venv/bin/hermes gateway run"`

### 3. 標準開發與分支管理規範 (Standard Development Workflow)
為了確保生產環境（主線分支）的穩定性，本專案嚴格執行以下開發規範：

*   **實驗隔離 (Sandboxing)**：
    - 所有新功能（Feature）或實驗性修改（Experiment）嚴禁直接在 `my-config-*` 主線分支進行。
    - 必須由主線切出功能分支（例如 `ssh`, `feat-web-ui`）作為沙盒環境。
*   **影像標籤驅動 (Tag-Driven Testing)**：
    - **實驗階段**：建構影像時必須附加功能後綴（例如 `v2026.4.23-ssh`）。這能確保測試環境與生產環境的影像不會發生覆蓋（Shadowing）。
    - **驗證階段**：在實驗分支進行功能驗證、權限修復及效能測試。
*   **回歸與正式化 (Promote to Main)**：
    - 唯有在實驗分支確認「功能無誤且不影響現有穩定性」後，方可執行 Git Merge 合併回主線。
    - 合併後，必須建構「不帶實驗後綴」的正式標籤影像（如 `v2026.4.23`）作為正式發佈版。
*   **紀錄持久化**：
    - 所有的實驗計畫、Debug 日誌及合併策略應存放在 `data/hermes_upgrade/` 供後續追蹤。
    - 重大變更同步更新至 `GEMINI.md` 的「重大技術修正」章節。

## ⚠️ 已知殘留問題與溝通建議
*   **Docker TUI 限制**: 在 Docker 環境下執行 `hermes --tui` 時，`Shift+Enter` 會被誤認為 `Enter` 直接送出，目前尚無解法（官方 Issue 追蹤中）。
*   **輸入框當機風險**: 直接在 Gemini CLI 對話框貼上超長內容（>2000字）可能觸發自動偵錯頁面導致當機。
*   **推薦做法**: 
    - 使用 **`pbpaste`** 讀取剪貼簿。
    - 或將內容存入 `data/` 目錄後要求「請讀取檔案」。

---
*Created by Gemini CLI on 2026-04-25*
