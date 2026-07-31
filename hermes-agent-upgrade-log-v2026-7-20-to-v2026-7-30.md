# Hermes Agent Upgrade Log: v2026.7.20 -> v2026.7.30

本篇文件記錄自訂分支 `my-config-v2026.7.20` 升級至官方 `v2026.7.30` ("The Sapphire Release") 的完整過程、衝突解決細節與 Kubernetes 部署步驟。

---

## 1. 官方版本變更摘要 (v2026.7.30)

* **Build Stability 強化**：`apt-get` 繼續維持 `-o Acquire::Retries=3` 機制，並對 `curl` 下載 s6-overlay 檔案補上 `--retry 3` 防護，避免 CI 網路波動。
* **Tini Shim 重構**：由傳統 symlink 改為專屬腳本 `docker/tini-shim.sh`，修正舊版 entrypoint 引發的 boot-loop 異常。
* **Playwright 自動重試**：Dockerfile 中的 Playwright 安裝步驟改為最多重試 3 次。
* **原生 ENV 整合**：官方正式在 Dockerfile 第 295 行寫入 `ENV HERMES_TUI_DIR=/opt/hermes/ui-tui`。
* **Monorepo Workspace**：新增 `apps/shared/` 目錄，並於 Dockerfile 中完成 `COPY apps/shared/ apps/shared/` 階段處理。

---

## 2. Cherry-Pick 自訂 Commits 列表

基於官方 `v2026.7.30` 標籤，依序 Cherry-pick 重新套用以下 9 個自訂 commits：

| 原始 Commit | 新 Commit | 說明 |
|-------------|-----------|------|
| `33deb44ae` | `bc325133a` | `feat: integrate SSH into official s6-overlay architecture` |
| `9deea2144` | `eb7e5dcb8` | `chore: add .env with HERMES_IMAGE for docker-compose` |
| `c4610d73a` | `8c65f00af` | `chore: add ghcr-publish workflow for Docker image build` |
| `9154d1c66` | `adb7f5713` | `feat: add entrypoint-ssh.sh for Zeabur compatibility` |
| `e67aa6aef` | `f255af53c` | `fix: handle non-PID 1 environment (Zeabur)` |
| `e72ef63b1` | `5152c99a5` | `fix: use su-exec instead of main-wrapper.sh for Zeabur` |
| `cf74eecb4` | `75e0c5f5f` | `fix: use su instead of su-exec for Zeabur` |
| `2b3a76a43` | `e3252b8da` | `chore: restore docker-compose.yml from my-config-v2026.5.16` |
| `a1e642bff` | `fc9de73ed` | `fix(docker): export HERMES_TUI_DIR in SSH session rc` |

---

## 3. 衝突與合併細節 (Conflict Resolution)

### 3.1 Dockerfile (`apt-get` / SSH 套件)
* **衝突原因**：官方 `v2026.7.30` 加入了全新 SQLite 獨立構建階段 (sqlite_build) 與 `NODE_OPTIONS`，而我方的 SSH 相關 commit 試圖變更相鄰行。
* **合併原則**：完整保留官方的 SQLite 構建與環境變數設定，同時在 `apt-get` 列表內保留我方 `openssh-server`、`openssh-client` 以及 SSH Host Key 初始化：

```dockerfile
RUN apt-get -o Acquire::Retries=3 update && \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
    ca-certificates curl iputils-ping python3 python-is-python3 ripgrep ffmpeg gcc g++ make cmake python3-dev python3-venv libffi-dev libolm-dev procps git openssh-client openssh-server docker-cli xz-utils && \
    mkdir -p /var/run/sshd && ssh-keygen -A && \
    rm -rf /var/lib/apt/lists/*
```

### 3.2 stage2-hook.sh (`HERMES_TUI_DIR` 清理)
* **優化項目**：官方已有 `ENV HERMES_TUI_DIR=/opt/hermes/ui-tui`，因此清理了 stage2-hook 中重複的 export 設定，維持邏輯簡潔。

---

## 4. Git 歷史與 Prompt Cache 保護策略分析

在升級方案評估中，我們對比了 `cherry-pick` 與 `rebase` 兩種方式：
* **為什麼選擇 `cherry-pick`**：Hermes Agent 核心原則強調「Per-conversation prompt caching is sacred」。Cherry-pick 能精準重現自訂修復，維持乾淨且明確的演進歷史，避免 rebase 改寫 commit graph 對上下文所產生的非必要影響。

---

## 5. GitHub CI/CD 與 Kubernetes 部署驗證

1. **推送分支與 CI/CD 觸發**：
   ```bash
   git push kuniakil my-config-v2026.7.30
   gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v2026.7.30 -f tag_name=v2026.7.30
   ```
2. **Kubernetes Deployment 滾動更新**：
   ```bash
   kubectl rollout restart deployment/hermes-agent -n hermes
   kubectl rollout status deployment/hermes-agent -n hermes
   ```
3. **Container 內部版本確認**：
   ```text
   Hermes Agent v0.19.1 (2026.7.30)
   Install directory: /opt/hermes
   Install method: docker
   Python: 3.13.5
   OpenAI SDK: 2.24.0
   ```
