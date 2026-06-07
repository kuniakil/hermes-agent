# Upgrade Log: v2026.5.29.2 → v2026.6.5

## Date: 2026-06-07

## Summary

成功將 Hermes Agent 從 `v2026.5.29.2`（官方 `v0.15.2`）升級到 `v2026.6.5`（官方 `v0.16.0`）。

## Branch Structure

| Branch | Version | Status |
|--------|---------|--------|
| `backup/my-config-v2026.5.29.2` | v2026.5.29.2 | 舊版備份分支 |
| `my-config-v2026.6.5` | v2026.6.5 | 升級後新分支 |

## Official Changes (v0.16.0)
- **Progressive Tool Disclosure**：針對 MCP 與 plugin 工具引進漸進式揭露機制。
- **Consolidated Vision Fast-path**：重構與整合 vision 相關的 native fast-path 路由判斷。
- **Reliability Fixes**：修復了大量 gateway (例如 Telegram topic 綁定)、Docker socket 自動加入 group 等可靠性問題。

## Custom Commits Applied

在 `v2026.6.5` 官方 Tag 基礎之上，重新 cherry-pick 並套用了以下自定義提交：

| # | Commit | Original Commit | Description |
|---|--------|-----------------|-------------|
| 1 | `a57795131` | `c70f6b128` | feat: integrate SSH into official s6-overlay architecture |
| 2 | `73aac57f5` | `939002121` | chore: add .env with HERMES_IMAGE for docker-compose |
| 3 | `98ffc6f6a` | `44edbb7e0` | chore: add ghcr-publish workflow for Docker image build |
| 4 | `9803349e2` | `d497a69c9` | feat: add entrypoint-ssh.sh for Zeabur compatibility |
| 5 | `2c5831e94` | `ea40a0628` | fix: handle non-PID 1 environment (Zeabur) |
| 6 | `f12490929` | `aae3e3f8f` | fix: use su-exec instead of main-wrapper.sh for Zeabur |
| 7 | `c38e2a59e` | `055bedfd6` | fix: use su instead of su-exec for Zeabur |
| 8 | `40aad5d1c` | `1342f3067` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| 9 | `2b2676ed1` | `de7cc635f` | docs: add GEMINI.md upgrade SOP and behavior rules |

## Conflict Resolution

在套用第一個 commit `c70f6b128` 時，以下檔案發生衝突：

1. **`Dockerfile`**：
   - **衝突原因**：官方 upstream 增加了新依賴（如 `iputils-ping`, `python3-venv`, `libolm-dev`），與自定義 SSH 套件安裝與 `NODE_OPTIONS` 環境變數設定位置重疊。
   - **解決方式**：合併雙方所需的 dependencies，並保留 SSH 設定與 Node 記憶體上限變數。
2. **`docker/stage2-hook.sh`**：
   - **衝突原因**：官方 upstream 增加了拒絕非支援 `--user` 啟動的檢測邏輯，與自定義 SSH 啟動段落衝突。
   - **解決方式**：保留 `--user` 的安全檢測邏輯，並在其後緊接著啟動自定義 SSH 伺服器，使兩者共存。

## Testing Results

由於不需要在本地編譯 Docker 映像檔（後續將由 GitHub CI/CD 完成），我們使用 `uv sync --extra dev` 重建虛擬環境並執行本地單元測試：

| Test Target | Status | Notes |
|-------------|--------|-------|
| `tests/test_model_tools.py` | ✅ PASS | 25 個測試全數通過 |
| `tests/test_hermes_constants.py` | ✅ PASS | 43 個測試全數通過 |
| `tests/test_hermes_logging.py` | ✅ PASS | 59 個測試全數通過 |
| `tests/test_hermes_state.py` | ✅ PASS | 256 個測試全數通過 |
| Docker helper scripts (非 build 測試) | ✅ PASS | 8 個測試全數通過 |
