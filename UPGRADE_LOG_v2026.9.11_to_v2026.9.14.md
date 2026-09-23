# 升級記錄：v2026.9.11 → v2026.9.14

## 官方版本摘要

- **版本 Tag**：`v2026.9.14` (Hermes Agent v0.21.3)
- **官方 Commits**：1,036 個 non-merge commits（異動 2,642 個檔案，338 個 PR）
- **發布日期**：2026-09-14
- **主要更新**：
  - **Remote Gateway / Desktop / Cloud 登入 session 穩定性** (#110061, fixes #55712)：
    - Gateway 的 cookie gate 與 desktop 原生 bearer route 針對相同的 rotating refresh token 併發請求進行合併 (coalescing)，避免 Desktop wake burst 重送已輪轉的 token 觸發 Portal reuse detection 導致整個工作階段被撤銷。
    - Token refresh 改至 event loop 外部執行，避免 slow identity provider 卡死 `/api/status`。
  - **避免長時間運行程序洩漏重複的 state.db writer handle** (#110934, fixes #100896 #103339)：
    - Gateway、dashboard/Desktop backend、ACP 與 CLI readers 預設以唯讀模式掛載。
    - 行程內多個 writers 共享同一個 registry handle，徹底解決 `N live SessionDB handles` 警報。
  - **其他重要更新**：
    - Server→client JSON-RPC 請求與 Pydantic wire-contract registry (#110521, #110522)。
    - Model picker 增加 reasoning-effort 選擇控制。
    - OpenRouter OAuth PKCE 登入支援。
    - 原生支援 HEIF/HEIC/AVIF 圖像解碼 (`pillow-heif>=1.4.0,<2`)。
    - 官方 `Dockerfile` 新增 `--extra google-chat`。

## 套用的 Custom Commits

以下為套用至 `my-config-v2026.9.14` 分支的自定義 commits 清單：

| 新 Commit Hash | 原始 Commit Hash | 說明 |
|---|---|---|
| `39c3651dc2` | `022818679e` | chore: add .env with HERMES_IMAGE for docker-compose |
| `4940969734` | `12afb76b1a` | chore: add ghcr-publish workflow for Docker image build |
| `4bae54c108` | `22e92eea77` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| `da38f364d1` | `de6f13a8ab` | feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture |
| `761315d38b` | `bb03e822c0` | feat(docker): add rsync, locales, and full UTF-8 support |
| `b1e33beb17` | `47451a4381` | feat(docker): install full Playwright Chromium with proper permissions |
| `004cc86bca` | `cab338141e` | ci: add platform choice to workflow defaulting to amd64 |
| `0a47022938` | `a3fd97e655` | fix(docker): propagate s6 container_environment to SSH sessions and fix faster-whisper PYTHONPATH |
| `ef16ec3a4b` | `db5c0dab0f` | feat(docker): build faster-whisper (voice extra) directly into image (rebased onto v2026.8.19) |
| `633fced96f` | `cdc0e024cb` | fix(docker): ensure /root/.npm ownership is granted to hermes user (UID 10000) |
| `c55294c28a` | `a96b9ae818` | fix(docker): set ENV HOME=/opt/data to prevent non-root processes from accessing /root |
| `cfd886859c` | `edcf01f35a` | feat(docker): restore dropped extras (edge-tts, firecrawl, dingtalk, feishu, exa) and install playwright |
| `759c14bd8b` | `55a4763bda` | chore: add Mac host resource constraint rule to AGENTS.md |
| `efeb5dcd78` | `cce7ba5796` | fix(docker): bake playwright CLI globally and isolate npm cache to /tmp |
| `a383c3d304` | `6f00fd3b95` | fix(docker): persist fixed package-lock.json and enforce post-copy npm audit fix |
| `eab8c46301` | `0544fff0c9` | chore(ci): upgrade to native arm64 runner (ubuntu-24.04-arm) and purge non-essential workflows |
| `2337247513` | `cb0413feeb` | ci: default platforms to all for dual-arch build (amd64 + arm64) using native runners |
| `0b28e683b8` | - | docs: restore historical upgrade logs from my-config-v2026.9.11 |
| `3a67bb1b7b` | `c10e662e7d` | chore: bump HERMES_IMAGE tag to v2026.9.14 |

## 衝突與解決方式

- **衝突檔案 1**：`Dockerfile` (RUN uv sync 行)
  - **原因**：官方 upstream 在 `v2026.9.14` 新增 `--extra google-chat`，與我們原本自定義的 `--extra voice` 以及後續各類 extras 在同一行發生衝突。
  - **解決方式**：依照合併指引保留雙方設定，將官方的 `--extra google-chat` 與自定義的 `voice`, `edge-tts`, `dingtalk`, `feishu`, `firecrawl`, `exa` 等完整合併進 `RUN uv sync`。
- **衝突檔案 2**：`TODO.md` (modify/delete conflict)
  - **原因**：HEAD 未追蹤 TODO.md，而自定義 commit `cce7ba5796` 中修改了 TODO.md。直接保留並 `git add TODO.md` 順利繼續。
- **衝突檔案 3**：`.github/workflows/` (modify/delete conflict)
  - **原因**：官方在 `v2026.9.14` 修改了 `install-e2e.yml`, `osv-scanner.yml`, `skills-index.yml`, `tests-os.yml`，在套用 Workflow Purge 時產生衝突。
  - **解決方式**：遵循 Workflow Purge Protection 原則，刪除非 `ghcr-publish.yml` 的所有 workflow 檔案，順利解決。
- **衝突檔案 4**：`GEMINI.md` (modify/delete conflict)
  - **原因**：官方 Tag 無 GEMINI.md，直接保留並 `git add GEMINI.md`。

## 驗證結果與系統檢查 (Verification)

- [ ] GitHub Actions `ghcr-publish.yml` Docker 映像檔雙架構建置 (amd64 + arm64)
- [ ] Kubernetes 叢集映像檔更新至 `v2026.9.14`
- [ ] Pod 正常啟動與基本功能驗證
- [ ] `hermes doctor` 驗證
- [ ] API 連線、SSH 登入與 state.db 運作驗證
