# 升級執行計畫：v2026.6.19 → v2026.7.7.2

> 建立：2026-07-12  
> 目前分支：`my-config-v2026.6.19`  
> 目標版本：`v2026.7.7.2`（官方 v0.18.2，~2,665 commits）  
> 遠端：`origin` = NousResearch/hermes-agent，`kuniakil` = 個人 fork

---

## 前置確認（已完成）

```bash
git fetch origin --tags        # ✅ 已執行
git tag -l "v2026.7.7.2"       # ✅ 確認：v2026.7.7.2 已存在
git branch --show-current      # ✅ my-config-v2026.6.19
```

---

## 第一步：建立備份分支

```bash
git branch backup/my-config-v2026.6.19
git branch | grep backup
```

---

## 第二步：從官方 Tag 建立新分支

```bash
git checkout -b my-config-v2026.7.7.2 v2026.7.7.2
git log --oneline -1
# 應輸出：9de9c25f6 chore: release v0.18.2 (2026.7.7.2) (#60651)
```

---

## 須捨棄的 Commits（不執行 cherry-pick）

以下 6 個 commits **不做 cherry-pick**：

| Commit | 描述 | 捨棄原因 |
|--------|------|---------|
| `f1ce436cf` | feat: grant hermes user write access to venv | 官方改用 lazy-packages 機制，venv 維持 sealed |
| `ae85a8ad4` | fix: grant write permission on venv in stage2-hook | 同上 |
| `e819fdb25` | fix: change /opt/hermes/.venv owner at image build time | 官方用 `COPY --link --chmod=go-w` 取代 |
| `efd9307ad` | debug: add before/after logging to venv chown | 純 debug 用，無需保留 |
| `cb1319b3b` | chore: clean up verbose permission debug logging | debug 清理，與上同捨棄 |
| `af397b491` | fix: add g++ make build-essential C/C++ toolchain | 官方 v2026.7.7.2 Dockerfile 已原生包含 `build-essential` |

---

## 第三步：依序 Cherry-pick

### 3-1. feat: integrate SSH into official s6-overlay architecture

```bash
git cherry-pick c9be8cd6b
```

**預期：`Dockerfile` 衝突**

衝突原因：官方 v0.18.x 的 apt-get 行移除了 `openssh-server`，與我方不同。

衝突處理 — `Dockerfile` apt-get 區段（約第 31 行）：

```
<<<<<<< HEAD         ← 官方 v2026.7.7.2（新 HEAD）
    ca-certificates ... gcc g++ make cmake python3-dev ... openssh-client docker-cli xz-utils && \
    rm -rf /var/lib/apt/lists/*
=======
    ca-certificates ... gcc g++ make cmake build-essential python3-dev ... openssh-client openssh-server docker-cli xz-utils && \
    mkdir -p /var/run/sshd && ssh-keygen -A && \
    rm -rf /var/lib/apt/lists/*
>>>>>>> c9be8cd6b   ← 我方 SSH commit
```

**解決後（保留官方套件清單，加入 SSH 相關）**：

```dockerfile
    ca-certificates curl iputils-ping python3 python-is-python3 ripgrep ffmpeg \
    gcc g++ make cmake python3-dev python3-venv libffi-dev libolm-dev \
    procps git openssh-client openssh-server docker-cli xz-utils && \
    mkdir -p /var/run/sshd && ssh-keygen -A && \
    rm -rf /var/lib/apt/lists/*
```

> ⚠️ **注意**：官方 v0.18.x 的 Permissions block 已改用 `COPY --link --chmod=a+rX,go-w . .`，
> 舊的 `chmod -R a-w /opt/hermes` 多行 RUN 已移除。
> 若衝突中出現我方的 `chown -R hermes:hermes /opt/hermes/.venv && chmod -R u+w /opt/hermes/.venv`，
> **刪除這兩行**（已被官方 lazy-packages 機制取代）。

```bash
git add Dockerfile
git cherry-pick --continue --no-edit
```

---

### 3-2. chore: add .env with HERMES_IMAGE for docker-compose

```bash
git cherry-pick 38e8c2c25
# 預期：無衝突
```

---

### 3-3. chore: add ghcr-publish workflow for Docker image build

```bash
git cherry-pick fcbfbbe47
# 預期：無衝突（官方未動 .github/workflows/ghcr-publish.yml）
```

---

### 3-4. feat: add entrypoint-ssh.sh for Zeabur compatibility

```bash
git cherry-pick 6796c18cf
```

**預期：可能有 Dockerfile COPY 區段輕微衝突**

若衝突，確認 Dockerfile 末段存在以下 COPY 指令即可解決：

```dockerfile
COPY --chmod=0755 docker/hermes-exec-shim.sh /opt/hermes/bin/hermes
COPY --chmod=0755 docker/entrypoint-ssh.sh /opt/hermes/docker/entrypoint-ssh.sh
```

```bash
git add Dockerfile docker/entrypoint-ssh.sh
git cherry-pick --continue --no-edit
```

---

### 3-5. fix: handle non-PID 1 environment (Zeabur)

```bash
git cherry-pick cacc8c997
# 預期：無衝突（改動 docker/entrypoint-ssh.sh，官方無此檔）
```

---

### 3-6. fix: use su-exec instead of main-wrapper.sh for Zeabur

```bash
git cherry-pick 31300df3d
# 預期：無衝突
```

---

### 3-7. fix: use su instead of su-exec for Zeabur

```bash
git cherry-pick 00fc0028b
# 預期：無衝突
```

---

### 3-8. chore: restore docker-compose.yml from my-config-v2026.5.16

```bash
git cherry-pick 8816bafe7
# 預期：無衝突（官方 v2026.7.7.2 未改動 docker-compose.yml）
```

---

### 3-9. fix(docker): export HERMES_TUI_DIR in SSH session rc

```bash
git cherry-pick e3c554e24
```

**預期：`docker/stage2-hook.sh` 可能衝突**

衝突原因：官方 v0.18.x 大量重構了 stage2-hook.sh（新增 `chown_hermes_tree`、`refuse_symlinked_path` 函式），SSH .bashrc/.profile heredoc 的行號已移動。

**情況 A：git 自動合併成功**

驗證 — 確認兩處 heredoc 均有 `HERMES_TUI_DIR`：

```bash
grep -n "HERMES_TUI_DIR" docker/stage2-hook.sh
# 應輸出兩行（.bashrc heredoc 內 + .profile heredoc 內）
```

**情況 B：發生衝突，手動定位**

搜尋 heredoc 位置：

```bash
grep -n "SSH_PUBLIC_KEY\|\.bashrc\|\.profile\|^EOF" docker/stage2-hook.sh | head -30
```

在新版 `.bashrc` heredoc 的 `EOF` 前加入：

```bash
# HERMES_TUI_DIR points the TUI launcher at the prebuilt ui-tui bundle,
# which sidesteps the runtime `npm install` in _tui_need_npm_install().
# Without this, an SSH login shell (a fresh process tree that does NOT
# inherit container PID 1's env) hits EACCES trying to write to the
# read-only /opt/hermes/node_modules. See v2026.6.19 TUI EACCES fix.
export HERMES_TUI_DIR=/opt/hermes/ui-tui
```

在 `.profile` heredoc 的 `EOF` 前加入：

```bash
# HERMES_TUI_DIR points the TUI launcher at the prebuilt ui-tui bundle.
# See comment in .bashrc above.
export HERMES_TUI_DIR=/opt/hermes/ui-tui
```

```bash
git add docker/stage2-hook.sh
git cherry-pick --continue --no-edit
```

---

### 3-10. revert: remove edge-tts from Dockerfile

```bash
git cherry-pick c9b73542f
# 預期：無衝突，或 git 提示 "nothing to commit"（因官方 base 就沒有 bake edge-tts）
# 若顯示 "nothing to commit"：
git cherry-pick --skip
```

---

### 3-11 ～ 3-16. 文件類 commits（全部無衝突）

```bash
git cherry-pick 670ed5507   # docs: add GEMINI.md upgrade SOP and behavior rules
git cherry-pick 64a8ca1ae   # docs: update GEMINI.md upgrade SOP to use GitHub CI/CD
git cherry-pick 3b856fac4   # docs: improve GEMINI.md conflict guidelines
git cherry-pick 9965547b8   # docs: update upgrade log (C/C++ toolchain hotfixes)
git cherry-pick 7ed71f975   # docs: add upgrade log v2026.6.5→v2026.6.19 + restore v5.16 log
git cherry-pick 1b50f5fb0   # docs: document SSH hermes --tui EACCES hotfix
```

---

## 第四步：更新 .env 版本號

```bash
sed -i '' 's/HERMES_IMAGE=.*/HERMES_IMAGE=ghcr.io\/kuniakil\/hermes-agent:v2026.7.7.2/' .env
cat .env
# 應輸出：HERMES_IMAGE=ghcr.io/kuniakil/hermes-agent:v2026.7.7.2

git add .env
git commit -m "chore: bump HERMES_IMAGE tag to v2026.7.7.2"
```

---

## 第五步：補回歷史升級記錄

```bash
ls UPGRADE_LOG_*.md
# 應有：
# UPGRADE_LOG_v2026.5.16_to_v2026.5.29.2.md
# UPGRADE_LOG_v2026.5.29.2_to_v2026.6.5.md
# UPGRADE_LOG_v2026.6.5_to_v2026.6.19.md

# 若有遺失，從備份分支取回：
git show backup/my-config-v2026.6.19:UPGRADE_LOG_v2026.5.16_to_v2026.5.29.2.md \
    > UPGRADE_LOG_v2026.5.16_to_v2026.5.29.2.md
# 依需要重複執行

git add UPGRADE_LOG_*.md
```

---

## 第六步：建立本次升級記錄並 Commit

建立 `UPGRADE_LOG_v2026.6.19_to_v2026.7.7.2.md`（記錄本次變更、衝突、測試結果）。

```bash
git add UPGRADE_LOG_v2026.6.19_to_v2026.7.7.2.md \
        UPGRADE_LOG_*.md \
        GEMINI.md \
        UPGRADE_PLAN_v2026.6.19_to_v2026.7.7.2.md
git commit -m "docs: add upgrade log v2026.6.19 to v2026.7.7.2"
```

---

## 第七步：推送至個人 Fork

```bash
git push kuniakil my-config-v2026.7.7.2
```

---

## 第八步：觸發 GitHub CI/CD

```bash
gh workflow run ghcr-publish.yml \
  --repo kuniakil/hermes-agent \
  --ref my-config-v2026.7.7.2 \
  -f tag_name=v2026.7.7.2

# 確認進度
gh run list --repo kuniakil/hermes-agent --limit 3
```

---

## 第九步：K8s 部署更新

```bash
# 清除本地 image cache（K3s IfNotPresent policy）
docker rmi ghcr.io/kuniakil/hermes-agent:v2026.7.7.2 2>/dev/null || true

# 套用新設定
kubectl apply -k hermes/overlays/mac

# 確認 rollout
kubectl -n hermes rollout status deployment/hermes
kubectl -n hermes get pods

# 驗證版本
kubectl -n hermes exec -it deploy/hermes -- hermes --version
```

---

## 緊急回滾

```bash
# 切回舊分支
git checkout my-config-v2026.6.19

# K8s 回滾
kubectl -n hermes rollout undo deployment/hermes
```

## 衝突安全中止規則

```bash
# 若衝突超過 1 輪無進展，立即中止：
git cherry-pick --abort
git status   # 確認回到乾淨狀態
```

---

## 本次升級關鍵架構變更備忘

### lazy-packages 新機制（取代 venv 權限修改）

| | 舊做法 (v2026.6.19) | 新做法 (v2026.7.7.2) |
|---|---|---|
| lazy_deps 安裝位置 | `/opt/hermes/.venv`（需 chmod u+w） | `/opt/data/lazy-packages`（data volume 可寫） |
| venv 狀態 | hermes user 可寫 | root-owned, read-only（sealed） |
| ENV 設定 | `HERMES_DISABLE_LAZY_INSTALLS=1` | `HERMES_LAZY_INSTALL_TARGET=/opt/data/lazy-packages` |

### COPY --link --chmod 效能優化

```dockerfile
# 舊做法（v2026.6.19）— amd64 需 21s，arm64 需 222s
COPY . .
RUN chown -R root:root /opt/hermes && chmod -R a+rX /opt/hermes && chmod -R a-w /opt/hermes

# 新做法（v2026.7.7.2）— 在 COPY 時就設好權限，跳過 ~30k 檔案走訪
COPY --link --chmod=a+rX,go-w . .
```

### apps/shared/ 新目錄

官方新增 `apps/shared/` 作為 web workspace 依賴，Dockerfile 在兩處新增了 `COPY apps/shared/ apps/shared/`。

---

## 衝突難度總表

| # | 衝突點 | 等級 | 操作摘要 |
|---|--------|------|---------|
| 1 | `Dockerfile` apt-get openssh-server | 🟡 中 | 手動合併，加回 SSH 套件 + ssh-keygen |
| 2 | `Dockerfile` COPY --chmod + venv 權限 | 🟢 自動 | 捨棄 venv commits，接受官方新架構 |
| 3 | `Dockerfile` apps/shared 新增 | 🟢 自動 | 無需干預 |
| 4 | `Dockerfile` HERMES_LAZY_INSTALL_TARGET | 🟢 自動 | 接受官方新增 |
| 5 | `stage2-hook.sh` venv write block | 🟢 自動 | 不 cherry-pick 相關 commits |
| 6 | `stage2-hook.sh` HERMES_TUI_DIR heredoc | 🟡 中 | 驗證自動合併，或手動定位 heredoc 插入 |
| 7 | `stage2-hook.sh` SSH 啟動邏輯 | 🟢 預計自動 | 3-way merge 通常可處理 |

---

*本計畫由 Antigravity AI 於 2026-07-12 根據 `git diff v2026.6.19 v2026.7.7.2` 分析產生。*
