# Upgrade Log: v2026.6.5 → v2026.6.19

## Date: 2026-06-20

## Summary

成功將 Hermes Agent 從 `v2026.6.5`（官方 `v0.16.0`）升級到 `v2026.6.19`（官方 `v0.17.0`）。

## Branch Structure

| Branch | Version | Status |
|--------|---------|--------|
| `backup/my-config-v2026.6.5` | v2026.6.5 | 舊版備份分支 |
| `my-config-v2026.6.19` | v2026.6.19 | 升級後新分支 |

## Official Changes (v0.17.0 — "The Reach Release")

**規模**：~1,475 commits、~800 merged PRs、1,693 files changed、235,390 insertions、50,730 deletions、300+ issues closed、245 位貢獻者

### 重大新功能

- **iMessage (Photon)**：無需 Mac relay 或 BlueBubbles bridge，`hermes photon login` 直接收發 iMessage
- **Raft agent network**：Hermes 加入 Raft agent 網路作為 gateway channel
- **WhatsApp Business Cloud API**：官方 Meta API（非 Baileys bridge）
- **Telegram rich text**：Bot API 10.1 rich messages，預設開啟
- **Background subagents**：`delegate_task(background=true)` 非阻塞執行
- **Image-to-image 編輯**：`image_generate` 可編輯現有圖片
- **Automation Blueprints**：無需 cron 語法的排程任務設定
- **memory 批次原子操作**：一次 call 完成 add/replace/remove
- **grok-composer-2.5-fast**：透過 xAI Grok OAuth 使用 Cursor 的 Composer 模型
- **Curator 成本優化**：例行 curation 不再消耗 aux-model budget
- **Desktop App 大幅強化**：VS Code Marketplace 主題、subagent watch-windows、可重綁鍵盤快捷鍵

### 架構重構

- `cli.py`: 3,297 → 954 行（28 個 subcommand parsers 移至 `hermes_cli/subcommands/`）
- `gateway/run.py`: 19,157 → 15,870 行（42 slash handlers → `GatewaySlashCommandsMixin`）
- `run_agent.py` turn loop：抽出 `TurnContext`、`finalize_turn`、`TurnRetryState`

## Custom Commits Applied

在 `v2026.6.19` 官方 Tag 基礎之上，重新 cherry-pick 並套用以下自定義提交：

| # | New Commit | Original Commit | Description |
|---|------------|-----------------|-------------|
| 1 | `c9be8cd6b` | `a57795131` | feat: integrate SSH into official s6-overlay architecture |
| 2 | `38e8c2c25` | `73aac57f5` | chore: add .env with HERMES_IMAGE for docker-compose |
| 3 | `fcbfbbe47` | `98ffc6f6a` | chore: add ghcr-publish workflow for Docker image build |
| 4 | `6796c18cf` | `9803349e2` | feat: add entrypoint-ssh.sh for Zeabur compatibility |
| 5 | `cacc8c997` | `2c5831e94` | fix: handle non-PID 1 environment (Zeabur) |
| 6 | `31300df3d` | `f12490929` | fix: use su-exec instead of main-wrapper.sh for Zeabur |
| 7 | `00fc0028b` | `c38e2a59e` | fix: use su instead of su-exec for Zeabur |
| 8 | `8816bafe7` | `40aad5d1c` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| 9 | `670ed5507` | `2b2676ed1` | docs: add GEMINI.md upgrade SOP and behavior rules |
| 10 | `64a8ca1ae` | `389b60d87` | docs: update GEMINI.md upgrade SOP to use GitHub CI/CD |
| 11 | `3b856fac4` | `7a39561d7` | docs: improve GEMINI.md conflict guidelines |
| 12 | `4cacc2864` | `8951c54ba` | chore: bump HERMES_IMAGE tag to v2026.6.5 and add upgrade log |
| 13 | `af397b491` | `54ef05046` | fix: add g++ make build-essential C/C++ toolchain to Dockerfile |
| 14 | `9965547b8` | `bcdc20710` | docs: update upgrade log with hotfixes and C/C++ toolchain |
| 15 | `2d0cbaae3` | —            | chore: bump HERMES_IMAGE tag to v2026.6.19 |
| 16 | `e3c554e24` | —            | fix(docker): export HERMES_TUI_DIR in SSH session rc to skip runtime npm install |

## Conflict Resolution

在套用 custom commits 時共發生 **3 次 Dockerfile 衝突**（`docker/stage2-hook.sh` 自動合併成功）：

### 衝突 1：commit #1（SSH 整合）

- **衝突原因**：官方 v0.17.0 的 `apt-get` 清單新增了 `g++ make cmake`，與我們自定義的 `openssh-server` + `ssh-keygen -A` 位置重疊。
- **解決方式**：合併雙方套件，保留兩側所有依賴：

  ```dockerfile
  ca-certificates curl iputils-ping python3 python-is-python3 ripgrep ffmpeg \
  gcc g++ make cmake python3-dev python3-venv libffi-dev libolm-dev \
  procps git openssh-client openssh-server docker-cli xz-utils && \
  mkdir -p /var/run/sshd && ssh-keygen -A && \
  ```

### 衝突 2：commit #4（entrypoint-ssh.sh）

- **衝突原因**：commit #1 已在 Dockerfile 末端加入 `hermes-exec-shim.sh` 的 COPY；commit #4 的基底版本認為該位置是空的，導致「空 vs. 兩行 COPY」衝突。
- **解決方式**：保留 commit #4 的兩行 COPY 指令（`hermes-exec-shim.sh` + `entrypoint-ssh.sh`）

  ```dockerfile
  COPY --chmod=0755 docker/hermes-exec-shim.sh /opt/hermes/bin/hermes
  COPY --chmod=0755 docker/entrypoint-ssh.sh /opt/hermes/docker/entrypoint-ssh.sh
  ```

### 衝突 3：commit #13（C/C++ toolchain）

- **衝突原因**：官方已新增 `cmake`（commit #1 解衝突時帶入），我們的 commit #13 要新增 `build-essential`，兩者在同一行衝突。
- **解決方式**：同時保留 `cmake` 和 `build-essential`：

  ```dockerfile
  gcc g++ make cmake build-essential python3-dev ...
  ```

## Hotfix: SSH `hermes --tui` EACCES（commit #16, 2026-06-20）

### 問題

從 SSH session 跑 `hermes --tui` 會印出：

```
$ hermes --tui
Installing TUI dependencies…
npm install failed.
```

第二行實際上是空的——`hermes_cli/main.py` 用 `--silent` 跑 npm install，stderr 被吞掉。

### 真正的 root cause

`HERMES_TUI_DIR=/opt/hermes/ui-tui` 是 Dockerfile `ENV` 設定的（line 293），但 **Dockerfile `ENV` 只作用於 container PID 1 跟它的 child process tree**。SSH login shell 是一個全新的 process tree，從 sshd 啟動，**不繼承** PID 1 的 env，所以在 SSH session 內 `HERMES_TUI_DIR` 是空字串。

`hermes_cli/main.py:_make_tui_argv()` 的 prebuilt-bundle fast path 條件是 `if ext_dir and (p / "dist" / "entry.js").is_file()`（line 1687-1692）。沒有 `HERMES_TUI_DIR` 就走不到 fast path，fall through 到 line 1714 的「runtime npm install if needed」分支，npm install 試圖寫入 `/opt/hermes/node_modules`——但 Dockerfile:216 `chmod -R a-w /opt/hermes` 把整個 install tree 設為 read-only，hermes user (uid 10000) 非 owner → `EACCES: permission denied, mkdir '/opt/hermes/node_modules/@emnapi/core'`。

### 為什麼之前 v0.16.x 沒撞到

官方 v0.17.0（PR #47490 "Harden hosted Docker install tree against self-modification"）撤掉了 PR #21267 原來的 `chown -R hermes:hermes /opt/hermes/ui-tui /opt/hermes/node_modules`（PR #47490:50-58），並且改用「靠 `HERMES_TUI_DIR` 走 prebuilt bundle fast path」的設計。官方假設 `hermes --tui` 永遠是從 container 內 process 啟動（有完整 env），沒考慮 SSH login shell 這個 edge case。我們 fork 因為 cherry-pick 了 SSH server（commit #1），這個 edge case 才被觸發。

### 修法

在 `docker/stage2-hook.sh` 寫 `.bashrc` / `.profile` 的 heredoc 內各加一行 `export HERMES_TUI_DIR=/opt/hermes/ui-tui`。stage2-hook 在 container first boot 透過 `/etc/cont-init.d/01-hermes-setup` 執行一次（line 79 的 `if [ -n "${SSH_PUBLIC_KEY:-}" ]` 區塊內），把 `$HERMES_HOME/.bashrc` 跟 `$HERMES_HOME/.profile` 寫進去。SSH login shell 是 login shell，會 source 這兩個 rc 檔，自動拿到 env。

### Diff（~9 行）

```diff
--- a/docker/stage2-hook.sh
+++ b/docker/stage2-hook.sh
@@ -97,6 +97,12 @@ if [ -f /opt/data/.env ]; then
     unset SSH_PUBLIC_KEY
 fi
 export PATH="/opt/hermes/.venv/bin:$PATH"
+# HERMES_TUI_DIR points the TUI launcher at the prebuilt ui-tui bundle,
+# which sidesteps the runtime `npm install` in _tui_need_npm_install().
+# Without this, an SSH login shell (a fresh process tree that does NOT
+# inherit container PID 1's env) hits EACCES trying to write to the
+# read-only /opt/hermes/node_modules. See v2026.6.19 TUI EACCES fix.
+export HERMES_TUI_DIR=/opt/hermes/ui-tui
 EOF
     chown hermes:hermes "$HERMES_HOME/.bashrc"
 
@@ -109,6 +115,9 @@ if [ -f /opt/data/.env ]; then
     unset SSH_PUBLIC_KEY
 fi
 export PATH="/opt/hermes/.venv/bin:$PATH"
+# HERMES_TUI_DIR points the TUI launcher at the prebuilt ui-tui bundle.
+# See comment in .bashrc above.
+export HERMES_TUI_DIR=/opt/hermes/ui-tui
 EOF
```

### 衝突評估

零衝突。既有 4 個 Zeabur custom commit 沒碰 stage2-hook.sh line 90-115 的 heredoc 區段。官方 v0.18.0 萬一改了這段，升級時 3-way merge 處理——是已知 SOP pattern。

### 部署 note：K3s `IfNotPresent` 不會自動感知 tag 覆蓋

K3s 預設 `imagePullPolicy: IfNotPresent`，**只看 image 是否在 node local cache**，**不比對 digest**。所以 CI/CD push 新 image 覆蓋 `v2026.6.19` tag 後，kubelet 不會自動 pull。workaround：

```bash
docker rmi ghcr.io/kuniakil/hermes-agent:v2026.6.19
kubectl apply -k hermes/overlays/mac
```

砍掉本地 cache 後，pod 重啟時 K3s 必須去 registry pull。Pull 耗時約 4m11s（1.27 GB）。未來可考慮改 `imagePullPolicy: Always` 或 bump tag 每次 build。

## Testing Results

本次升級採用 **不在 Mac 本地建置 Docker image** 的策略，直接推送至 GitHub 由 CI/CD 處理：

| Test Target | Status | Notes |
|-------------|--------|-------|
| 本地 Python 單元測試 | ⏭️ SKIP | 環境運行於 K8s，不在本地執行 |
| GitHub Actions `ghcr-publish.yml` (initial) | ✅ Success | amd64 + arm64 多平台建置 |
| GitHub Actions `ghcr-publish.yml` (TUI hotfix) | ✅ Success | 重 build 觸發 run `27861394781`，覆蓋 `v2026.6.19` tag |
| K8s rollout (TUI hotfix) | ✅ Verified | `docker rmi` + `kubectl apply -k` 後新 pod image digest = `sha256:e5f44f981fd9...`；SSH 進去 `hermes --tui` 正常啟動 TUI banner |

CI/CD Run (initial): https://github.com/kuniakil/hermes-agent/actions/runs/27854031850
CI/CD Run (TUI hotfix): https://github.com/kuniakil/hermes-agent/actions/runs/27861394781

## Next Upgrade SOP

1. `git fetch origin --tags`
2. 確認新版 Tag 存在：`git tag -l "v<新版本>"`
3. `git branch backup/my-config-v<舊版本>`
4. `git checkout -b my-config-v<新版本> v<新版本>`
5. 取得 custom commits 清單：`git log --oneline my-config-v<舊版本> ^v<舊版本>`
6. 依序 cherry-pick（由舊到新）
7. 衝突時：讀衝突 → 手動合併（保留雙方所需）→ `git add` → `git cherry-pick --continue`
8. 更新 `.env` 中的 `HERMES_IMAGE` 版本號並 commit
9. 建立本次升級記錄 `UPGRADE_LOG_v<舊>_to_v<新>.md`
10. `git push kuniakil my-config-v<新版本>`
11. `gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent --ref my-config-v<新版本> -f tag_name=v<新版本>`
