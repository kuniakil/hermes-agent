# Hermes Agent Project Guidelines & Upgrade Context

本文檔記錄了本專案的特定開發規範、環境配置及技術升級歷史，供 Gemini CLI 與開發者參考。

## 🚀 專案狀態 (截至 2026-04-30)
- **核心版本**: v0.12.0 (Hermes-Agent v2026.4.30)
- **部署環境**: Docker (MacOS 宿主機) + Zeabur (VPS)
- **遠端倉庫**: `kuniakil` (GitHub)
- **CI/CD**: GitHub Actions (Multi-arch Matrix Build)

## 🛠️ 重大技術修正 (踩雷紀錄)

### 1. Docker 建構與 TUI 組件修復
*   **問題**: 升級後 TUI 缺失 `ink-bundle.js` 導致當機。
*   **解決方案**: 
    - 重構 `Dockerfile` 確保 `COPY . .` 優先於建構步驟。
    - 全域安裝 `esbuild` 與 `typescript`。
    - **正式化建構**: 於 v2026.4.30 中正式整合 `ui-tui` 的自動建構邏輯，確保影像內包含完整的 `ink-bundle.js`。
*   **啟動優化 (2026-05-03)**:
    - **問題**: 儘管影像已內建 TUI，但在掛載 Volume 的環境下，Hermes 啟動時仍會因 Lockfile 微差而觸發 `npm install`，導致啟動緩慢。
    - **解決方案**: 在 `Dockerfile` 中加入 `sed` patch，修改 `hermes_cli/main.py`。若 `dist/entry.js` 已存在，則直接跳過 `_tui_need_npm_install` 檢查，實現秒開。

### 2. 權限與進程管理
*   **權限修復**: 實作了 `chmod -R a+rX /opt/hermes`，解決了 Node 模組權限問題。
*   **進程管理**: 沿用 `tini` 作為 Entrypoint 封裝，有效處理 MCP 產生的僵屍進程。

### 4. SSH 服務整合與跨平台相容性 (2026-04-30 更新)
*   **整合問題**: 原先 SSH 啟動在 Zeabur 等受限環境會因為 `/run/sshd` 目錄缺失或 Entrypoint 被繞過而失敗。
*   **解決方案**: 
    - **影像層級**: 在 `entrypoint-ssh.sh` 加入 `mkdir -p /run/sshd` 保護邏輯，確保服務啟動安全。
    - **引數透傳**: 確保 `exec ... "$@"` 完整傳遞指令，解決 `gateway run` 參數遺失問題。
*   **正式化**: 此功能已在 `v2026.4.30` 中成為標配。

## 📋 維護與升級規範

### 1. 升級 SOP
*   **流程**: 建立新版本分支（如 `my-config-v2026.4.30`）-> 合併官方 Tag -> 解決衝突（優先保留 Dockerfile 自定義修正）-> 建構 `-upgrade` 實驗影像驗證 -> 推送正式影像。
*   **快取優化**: 善用 GitHub Actions 的快取，同代碼不同標籤的建構應在數分鐘內完成。
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
