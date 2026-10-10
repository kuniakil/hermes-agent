# Hermes Agent 升級工作表:v2026.9.24 → v0.21.6

- **目標版本**:`v0.21.6`(commit `818c13be1d`,2026-10-08 發佈,官方新 stable release pipeline 首發版)
- **當前版本**:`my-config-v2026.9.24`(基於官方 `v2026.9.24` = `f97608f178`,v0.21.5)
- **新分支**:`my-config-v0.21.6`(⚠️ 官方 tag 命名已由 `vYYYY.M.D` 改為 `v0.x.y`,分支命名跟隨)
- **目標**:對齊官方 tag、線性歷史、保留自定義層、Workflow Purge、GH Actions 雙架構建置、K8s 升版
- **狀態**:⏸ 規劃階段,**等待使用者 Go-Sign,尚未修改任何程式碼**

---

## 1. 官方 Release Notes 稽核(v0.21.6)

來源:GitHub Release body(API 取得)。

- 性質:Patch release,彙整 v0.21.5 以來 ~2,100 PRs(8,867 commits / 8,342 files / +772K −226K)。完整 curated notes 延至 v0.22.0。
- **無 Breaking Changes / Deprecations / Migration 章節**(官方明言 undocumented on purpose)。須以 diff 自行判斷(見 §2)。
- 更新方式:Docker `nousresearch/hermes-agent:stable`;git 安裝 `hermes update`。Desktop / Termux 本版無變動。
- **Security Fixes**(升級有益):
  - Dashboard 認證加固:`X-Forwarded-For` 偽造繞過 rate limit、auth audit log 無界寫入、`/auth/` 無 body size 限制、native sign-in 非 loopback redirect 可 session takeover(#133367/#133369/#133370/#130685)
  - Repo git filter 加固:自動 git 呼叫會執行不受信任 repo 的 clean/smudge/process filter(#130661)
  - Email gateway:`From` 引號 display name 可繞過 allowlist(#125212)
- 新功能(未詳述):`stt.streaming`、`auxiliary.voice_chat`、`plugins.isolation: host`、local models / llama.cpp CUDA、`hermes status` 改版、cron store 不可寫警告、approval flags、Kanban 統一 workflow、`activate.fish`、Claude Sonnet 5.5 / Haiku 5.5 與 GPT-6.1 Sol 入 catalog。
- 注意:upstream 已有 `v0.21.7` 的 rc 系列 tag(rc.7–rc.9)。本次依指示對齊 stable `v0.21.6`,不追 rc。

## 2. 由 diff 發現的結構性變更(官方未寫,但影響我們)

`git diff v2026.9.24..v0.21.6`:Dockerfile ±327 行、`pyproject.toml` ±549、`stage2-hook.sh` +46/−55、`package-lock.json` ±1115、workflows 大量新增。

| # | 變更 | 對我們的影響 |
|---|---|---|
| 1 | **Dockerfile 重構為多階段**(`sqlite_build` / `runtime_base` / `python_deps` / `icons` / `frontend_build` / `runtime`),Debian 13.4 pin digest | 🔴 自定義層無法 cherry-pick,須人工重新移植 |
| 2 | **引入 PM(package manager)**:python/node/npm/ffmpeg/ripgrep/chromium 由 `pm` 預先 stage 到 `/opt/hermes/tools`;`uv sync` 改為 `python3 -m pm.build_env` | 🔴 我們的 `uv sync --extra ...` 與 `playwright install --with-deps chromium` 需改寫 |
| 3 | **移除 Playwright install**:改 PM 釘版完整 Chromium,路徑寫入 `/etc/hermes/agent-browser-executable-path`;apt 另帶 Chromium 共享函式庫清單 | 🔴 我們的「全 Chromium + `--with-deps`」目標已由官方達成,**刪除該自訂 hunk** |
| 4 | apt 清單移除 `ffmpeg`、`ripgrep`(改走 PM) | 🟡 確認 ffmpeg 仍可用(faster-whisper 依賴) |
| 5 | **`lazy-packages` 目錄與 `HERMES_LAZY_INSTALL_TARGET` 廢除**,改為 `$HERMES_HOME/installs` 下的 PM generations;`stage2-hook.sh` 開機執行 `refresh_dependencies` | 🔴 影響 `edge-tts/firecrawl/exa/feishu/dingtalk/faster-whisper` 預裝方式與 PYTHONPATH hack |
| 6 | `stage2-hook.sh` Chromium 探索邏輯改為讀 baked 路徑檔 | 🔴 我們的 SSH 區塊與 `.bashrc` 需與新邏輯並存,且 `AGENT_BROWSER_EXECUTABLE_PATH` 經 s6 container_environment 傳遞仍須有效 |
| 7 | `pyproject.toml` `version = "0.0.0"`(動態版本)、`requires-python >=3.11,<3.15`;`hermes-agent = agent.legacy_cli:main`;移除 `termux-all`、`[dev]` extra 改 dependency group | 🟡 extras 名稱仍存在:`edge-tts firecrawl exa dingtalk feishu voice matrix google-chat bedrock azure-identity otlp anthropic`;`hindsight` 已無 |
| 8 | `docker-compose.yml` 上游本次無 diff | 🟢 沿用我們版本 |
| 9 | 新增 workflows:`stable-release*.yml`、`canary-release.yml`、`sandbox-image.yml` 等 | 🟢 依 Purge 規則全砍,只留 `ghcr-publish.yml` |
| 10 | 新增 `docker/build_agent.py`、`sandbox-desktop*` | 🟢 隨官方帶入,無須處理 |
| 11 | 本機 `v2026.9.24` tag 為我們自行移動過的版本,`git fetch --tags` 拒絕覆蓋(official = `f97608f178`) | 🟡 不影響流程;新分支基底用 `v0.21.6`,建議最後以新 tag 命名避免混淆 |

## 3. 需要攜帶的自定義 commit(自 merge-base `f97608f178` 起共 10 個)

| Commit | 內容 | 處置 |
|---|---|---|
| `413663402c` | feat(docker): 自定義層(SSH、locales、faster-whisper extras) | ✋ 人工移植(§4 Phase 3) |
| `f03c19dd8d` | fix(docker): SSH server setup + npm cache 隔離 | ✋ 人工移植 + 驗證 stage2 |
| `8ba12f2eb6` | docker/entrypoint-ssh.sh(Zeabur 相容) | ✅ 直接 checkout 檔案;確認 `entrypoint-dispatch.sh` 仍存在 |
| `3ec9f5af79` | docker-compose.yml(`HERMES_IMAGE`、TZ=Asia/Taipei) | ✅ cherry-pick |
| `0680849e81` | AGENTS.md Mac 資源限制規則 | ✅ cherry-pick,衝突則重新附加於檔尾 |
| `4cad3f0daa` | bump `HERMES_IMAGE` tag | 🔁 重做,改為 `v0.21.6` |
| `4337455dd0` | purge workflows 只留 `ghcr-publish.yml` | 🔁 重做(目標分支新增更多 workflow) |
| `df58345dc8` `c27e98e937` `d7e4fc7007` | 升級 log / worksheet 文件 | ✅ cherry-pick 歷史文件,新增本版 log |

> 註:Skill 文件寫保留 `docker-release.yml`,實際 repo 保留的是 `ghcr-publish.yml`,本計畫以實際為準。

## 4. 執行檢查清單

### Phase 0:前置(唯讀,已完成)
- [x] 讀取官方 release notes 與 breaking change 稽核
- [x] `git fetch origin --tags` 取得 `v0.21.6`
- [x] 分析 Dockerfile / stage2-hook / pyproject / workflows 差異
- [x] **取得使用者 Go-Sign**

### Phase 1:分支建立
- [x] 確認工作樹乾淨:`git status`
- [x] 備份:`git branch backup/my-config-v2026.9.24`
- [x] `git checkout -b my-config-v0.21.6 v0.21.6`
- [x] 確認 HEAD = `818c13be1d`

### Phase 2:Workflow Purge
- [x] `find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete`
- [x] `git checkout my-config-v2026.9.24 -- .github/workflows/ghcr-publish.yml`
- [x] 檢查 `ghcr-publish.yml` 是否引用已更名/移除的 Dockerfile build-arg 或 stage
- [x] commit:`chore(ci): purge official CI workflows; retain only ghcr-publish.yml`

### Phase 3:基礎檔案與 Dockerfile 自定義層 🔴
- [x] 移植 `docker-compose.yml` (`HERMES_IMAGE`、TZ=Asia/Taipei)
- [x] `git checkout my-config-v2026.9.24 -- docker/entrypoint-ssh.sh`
- [x] 附加 AGENTS.md Mac 資源限制規則
- [x] **Dockerfile 以官方 v0.21.6 為基底,逐項移植**:
  - [x] apt 清單加入 `openssh-server`、`rsync`、`locales`
  - [x] `mkdir -p /var/run/sshd && ssh-keygen -A`、locale-gen(`en_US.UTF-8`、`zh_TW.UTF-8`)、`/etc/default/locale`、profile export
  - [x] **不移植** `npx playwright install --with-deps chromium`(官方 PM 已提供完整 Chromium)
  - [x] extras 並入 `pm.build_env`:`--extra matrix --extra google-chat --extra bedrock --extra azure-identity --extra anthropic --extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa`
  - [x] `/tmp/.npm-cache`(1777)、`/root/.npm` chown 10000、`ENV HOME=/opt/data`
  - [x] `COPY --chmod=0755 docker/entrypoint-ssh.sh`
- [x] **`docker/stage2-hook.sh`**:以官方版為基底,重新插入
  - [x] SSH server 區塊(`SSH_PUBLIC_KEY`、authorized_keys、`.bashrc`/`.profile`、啟動 sshd)置於 UID/GID remap 之前
  - [x] `.bashrc` 載入 s6 `container_environment`
  - [x] `/tmp/.npm-cache` 自我修復、清理 `$HERMES_HOME/.npm`
- [x] 輕量檢查:`sh -n docker/stage2-hook.sh docker/entrypoint-ssh.sh`、`git diff v0.21.6 -- Dockerfile docker/` 人工審視

### Phase 4:Lockfile / npm audit(Hermes 規定)
- [x] 檢查 lockfile 狀態(保持上游 v0.21.6 原始乾淨 lockfile,不在本機執行高負載建置)

### Phase 5:版本與文件
- [x] bump `HERMES_IMAGE` → `ghcr.io/kuniakil/hermes-agent:v0.21.6`(`.env` / docker-compose)
- [x] 新增 `UPGRADE_LOG_v2026.9.24_to_v0.21.6.md`
- [x] 本 worksheet 勾選更新並 commit

### Phase 6:推送與 CI(需再次確認)
- [ ] `git push kuniakil my-config-v0.21.6`(remote:`kuniakil` = 個人 fork,`origin` = 官方)
- [ ] 使用者確認後打 tag 並推送,觸發 `ghcr-publish.yml`(amd64 + arm64 原生 runner)
- [ ] 記錄 GH Actions Run ID

### Phase 7:部署驗證(K3s)
- [ ] 更新 K8s manifest 映像 tag 為 `v0.21.6`
- [ ] 啟動後檢查:s6 服務、SSH 登入、`hermes --version`、dashboard 登入(安全修補)、browser tool(Chromium 路徑)、voice/STT(faster-whisper)、zh_TW locale、cron
- [ ] 備註:新版首次開機 `refresh_dependencies` 需網路;`/opt/data/lazy-packages` 舊目錄可保留,確認無害後再清理
- [ ] 回滾方案:K8s 映像退回 `v2026.9.24`(資料卷相容性:舊版忽略 `installs/`)

### Phase 8:收尾
- [ ] 全部勾選、撰寫 post-mortem(可用 `/session-wrapup` 發佈 WordPress)

## 5. 風險摘要

| 風險 | 等級 | 緩解 |
|---|---|---|
| Dockerfile / PM 架構重構,自訂層需重寫 | 🔴 | 人工移植 + 僅 CI 建置驗證;保留 backup 分支 |
| faster-whisper / extras 預裝在新 PM 機制下行為不同 | 🔴 | 先讀 `docker/build_agent.py`、`pm.build_env` 用法;CI 後在容器內 `python -c "import faster_whisper"` |
| stage2 SSH 區塊與新依賴刷新並存 | 🟡 | 分段插入,`sh -n` 檢查 |
| 官方無 breaking-change 文件 | 🟡 | 以 diff 稽核;v0.22.0 notes 出後再補核 |
| 資料卷由舊版升級(lazy-packages → installs) | 🟡 | 先備份 `/opt/data` PVC 快照 |
