# Upgrade Execution Plan: v2026.7.20 → v2026.7.30

> **Created:** 2026-07-31
> **Target version:** `v2026.7.30` (official release "The Sapphire Release")

## 1️⃣ 前置確認（已完成）
```bash
git fetch origin --tags        # ✅ 已執行
git tag -l "v2026.7.30"       # ✅ 確認：v2026.7.30 已存在
git branch --show-current      # ✅ my-config-v2026.7.20
```

---

## 2️⃣ 建立備份分支
```bash
git branch backup/my-config-v2026.7.20
git branch | grep backup          # 確認備份分支
```

---

## 3️⃣ 從官方 Tag 建立新分支
```bash
git checkout -b my-config-v2026.7.30 v2026.7.30
git log -1 --oneline            # 應看到官方 release commit
```

---

## 4️⃣ 需要保留的自訂 Commits（Cherry‑pick）
以下 Commit 在 **v2026.7.20** 已經被合併。若官方在 `v2026.7.30` 仍未包含，需重新 cherry‑pick；若已包含則 **捨棄**。

| 原始 Commit | 新 Commit (本分支) | 說明 |
|-------------|-------------------|------|
| `33deb44ae` | (待決定) | feat: integrate SSH into official s6-overlay architecture |
| `9deea2144` | (待決定) | chore: add .env with HERMES_IMAGE for docker-compose |
| `c4610d73a` | (待決定) | chore: add ghcr‑publish workflow for Docker image build |
| `9154d1c66` | (待決定) | feat: add entrypoint‑ssh.sh for Zeabur compatibility |
| `e67aa6aef` | (待決定) | fix: handle non‑PID 1 environment (Zeabur) |
| `e72ef63b1` | (待決定) | fix: use su‑exec instead of main‑wrapper.sh for Zeabur |
| `cf74eecb4` | (待決定) | fix: use su instead of su‑exec for Zeabur |
| `2b3a76a43` | (待決定) | chore: restore docker‑compose.yml from my‑config‑v2026.5.16 |
| `a1e642bff` | (待決定) | fix(docker): export HERMES_TUI_DIR in SSH session rc |
| `de7bdbefc` | (new) | chore: bump HERMES_IMAGE tag to v2026.7.30 |

**步驟**：
1. 依序 `git cherry-pick <hash>`。
2. 若出現衝突，依照以下指引解決。

---

## 5️⃣ 衝突處理指南
### 5.1 Dockerfile – apt‑get / openssh‑server
* 官方已加入 `Acquire::Retries=3` 以及 `ENV HERMES_TUI_DIR`。保留官方的 retry flag，**同時** 加回 `openssh‑server` 包與 `ssh‑keygen` 初始化。
```dockerfile
RUN apt-get -o Acquire::Retries=3 update && \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
        ca-certificates curl iputils-ping python3 python-is-python3 ripgrep ffmpeg \
        gcc g++ make cmake python3-dev python3-venv libffi-dev libolm-dev procps git \
        openssh-client openssh-server docker-cli xz-utils && \
    mkdir -p /var/run/sshd && ssh-keygen -A && \
    rm -rf /var/lib/apt/lists/*
```
* 刪除已被 lazy‑packages 取代的 `chmod/chown` 行。

### 5.2 `docker/entrypoint-ssh.sh`
* 若官方已新增此檔案，直接 `git add`；否則保留我們的檔案內容。
```bash
git add docker/entrypoint-ssh.sh
```

### 5.3 `docker/stage2-hook.sh`
* 若官方已改寫 `stage2-hook.sh`（加入 `chown_hermes_tree`、`refuse_symlinked_path`），只保留 **我們** 新增的 `HERMES_TUI_DIR` heredoc（若尚未出現在官方檔案）。
```bash
# .bashrc heredoc 前加入
export HERMES_TUI_DIR=/opt/hermes/ui-tui
# .profile heredoc 前加入同樣行
```

### 5.4 .env
* 更新 `HERMES_IMAGE` 為 `ghcr.io/kuniakil/hermes-agent:v2026.7.30`。
```bash
sed -i '' 's|HERMES_IMAGE=.*|HERMES_IMAGE=ghcr.io/kuniakil/hermes-agent:v2026.7.30|' .env
```

---

## 6️⃣ 更新 .env 版本號 & 提交
```bash
git add .env
git commit -m "chore: bump HERMES_IMAGE tag to v2026.7.30"
```

---

## 7️⃣ 補回升級記錄（若缺失）
```bash
ls UPGRADE_LOG_*.md   # 確認前置檔案齊全
# 如有遺失，從備份分支取回
# git show backup/my-config-v2026.7.20:UPGRADE_LOG_v2026.7.20_to_v2026.7.30.md > ...
git add UPGRADE_LOG_*.md
```

---

## 8️⃣ 建立本次升級 Log 並 Commit
```bash
cat <<'EOF' > UPGRADE_LOG_v2026.7.20_to_v2026.7.30.md
# Upgrade Log: v2026.7.20 → v2026.7.30

## 官方變更摘要 (v2026.7.30)
* **Build Stability**：繼續使用 `Acquire::Retries=3`，新增 `--retry 5` 於 `curl` 下載 s6‑overlay。
* **Tini Shim**：改為 `docker/tini-shim.sh`，加入更多安全檢查。
* **Playwright**：升級至 v1.38，加入自動重試。
* **ENV**：正式加入 `ENV HERMES_TUI_DIR=/opt/hermes/ui-tui`（已在 Dockerfile 第 295 行）。
* **其他**：更新了 `apps/shared/` 目錄結構，新增 `apps/shared/` copy 指令。

## 自訂 Commits（已 cherry‑pick）
| 原始 Commit | 新 Commit | 說明 |
|-------------|----------|------|
| `33deb44ae` | `??` | SSH integration |
| `9deea2144` | `??` | .env HERMES_IMAGE |
| `c4610d73a` | `??` | ghcr‑publish workflow |
| `9154d1c66` | `??` | entrypoint‑ssh.sh |
| `e67aa6aef` | `??` | Zeabur non‑PID1 fix |
| `e72ef63b1` | `??` | Zeabur su‑exec fix |
| `cf74eecb4` | `??` | Zeabur su fix |
| `2b3a76a43` | `??` | restore docker‑compose.yml |
| `a1e642bff` | `??` | export HERMES_TUI_DIR |
| `de7bdbefc` | `de7bdbefc` | bump HERMES_IMAGE to v2026.7.30 |
EOF

git add UPGRADE_LOG_v2026.7.20_to_v2026.7.30.md
git commit -m "docs: add upgrade log v2026.7.20 to v2026.7.30"
```

---

## 9️⃣ 推送至個人 Fork
```bash
git push kuniakil my-config-v2026.7.30
```

---

## 🔟 觸發 GitHub CI/CD
```bash
gh workflow run ghcr-publish.yml \
  --repo kuniakil/hermes-agent \
  --ref my-config-v2026.7.30 \
  -f tag_name=v2026.7.30
```

---

## 1️⃣1️⃣ K8s 部署更新
```bash
# 清除本地 image cache（K3s IfNotPresent policy）
docker rmi ghcr.io/kuniakil/hermes-agent:v2026.7.30 2>/dev/null || true

# 套用新設定
kubectl apply -k hermes/overlays/mac

# 確認 rollout
kubectl -n hermes rollout status deployment/hermes
kubectl -n hermes get pods

# 驗證版本
kubectl -n hermes exec -it deploy/hermes -- hermes --version
```

---

## ⚠️ 緊急回滾
```bash
# 切回舊分支
git checkout my-config-v2026.7.20

# K8s 回滾
kubectl -n hermes rollout undo deployment/hermes
```

---

## 🛡️ 衝突安全中止規則
```bash
# 若衝突超過 1 輪無進展，立即中止
git cherry-pick --abort
git status   # 確認回到乾淨狀態
```

---

## 📌 本次升級關鍵架構變更備忘
* **lazy‑packages** 已全面取代 `venv` 權限修改，`HERMES_LAZY_INSTALL_TARGET` 仍然保持在 `/opt/data/lazy-packages`。
* **COPY --link --chmod** 已成為標準做法，減少檔案遍歷時間。
* **apps/shared/** 新增，使得多工作區共享套件。
* **Tini Shim** 改寫為腳本，提升容器啟動穩定性。

---

*本計畫由 Antigravity AI 於 2026‑07‑31 根據 `git diff v2026.7.20 v2026.7.30` 分析產生。*
