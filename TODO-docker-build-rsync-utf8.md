# TODO: Hermes Docker Image Build Checklist

目前源碼已是對齊官方最新版。本任務目標為修改 Dockerfile 並打包新 Image。

---

### 📦 需修改事項與踩坑避坑指南

#### 1. Dockerfile 修改 (rsync + 完整 UTF-8 生產配置)
- 在 `apt-get install` 加入 `rsync` 與 `locales`。
- 必須使用 `locale-gen` 生成 UTF-8 locale 數據，並寫入 `/etc/default/locale`、`/etc/profile` 及全員 `.bashrc`，避免 SSH 登入時環境變數被 Client 端覆蓋導致中文顯示為八進位亂碼 (`\346\272\252...`)。

```dockerfile
# 範例參考：
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl git hostname lsof openssl procps python3 tini openssh-server openssh-client ffmpeg rsync locales && \
    mkdir -p /var/run/sshd && ssh-keygen -A && \
    update-ca-certificates && \
    echo "C.UTF-8 UTF-8" > /etc/locale.gen && \
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    echo "zh_TW.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen && \
    echo "LANG=C.UTF-8" > /etc/default/locale && \
    echo "LC_ALL=C.UTF-8" >> /etc/default/locale && \
    echo "export LANG=C.UTF-8" >> /etc/profile && \
    echo "export LC_ALL=C.UTF-8" >> /etc/profile && \
    echo "export LANG=C.UTF-8" >> /home/node/.bashrc 2>/dev/null || true && \
    echo "export LC_ALL=C.UTF-8" >> /home/node/.bashrc 2>/dev/null || true && \
    echo "export LANG=C.UTF-8" >> /root/.bashrc && \
    echo "export LC_ALL=C.UTF-8" >> /root/.bashrc

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LANGUAGE=C.UTF-8
```

#### 2. Workflow 正則標籤修復 (踩坑點 1)
- 檢查 `.github/workflows/docker-release.yml`（若有）的 Tag 驗證正則，確保支援帶後綴數字的標籤（如 `-2`）。
- 改為：`(-[0-9]+)?` 以免手動發起 Build 時出現 `Invalid release tag` 錯誤。

#### 3. 避免 GitHub Actions 背景排程耗盡時間 (踩坑點 2)
- **注意**：只在當前分支刪除 `.github/workflows/` 不夠！如果遠端存有舊歷史分支（如 `my-config-v2026.7.x`），GitHub 伺服器會持續針對舊分支跑排程測試。
- **作法**：在舊分支上刪除所有 Cron 工作流（或刪除 GitHub 上的舊分支），並在根目錄 `AGENTS.md` 加入升級規範。

#### 4. Kubernetes 部署更新 (踩坑點 3)
- 確保 Deployment 的容器 `imagePullPolicy` 設定為 **`Always`**。
- **原因**：若設為 `IfNotPresent`，即使重新打同名 Tag，`kubectl rollout restart` 也只會抓節點本機舊快取，不會下載 GHCR 的新層。`Always` 策略會發送 HEAD 請求比對 Digest，內容沒變時不會重複下載大檔案。

---

### 🚀 執行步驟簡介
1. 編輯 `Dockerfile` 套用上述 `rsync` 與 `locales` 修改。
2. 在分支 commit 並打上符合規範的 Git Tag（如 `v2026.x.x-2`）。
3. 透過 `gh workflow run docker-release.yml --ref <branch> -f tag=<tag>` 手動觸發 Build。
4. 打包完成後，前往 K8s 部署並執行：
   ```bash
   kubectl patch deployment <deployment-name> -n <namespace> -p '{"spec":{"template":{"spec":{"containers":[{"name":"<container-name>","imagePullPolicy":"Always"}]}}}}'
   kubectl rollout restart deployment <deployment-name> -n <namespace>
   ```
5. 驗證容器內 `which rsync` 及 `ls -al` 中文字元正常顯示。
