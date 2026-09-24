# Hermes Agent 升級工作表：v2026.9.21 → v2026.9.24

- **目標版本**:`v2026.9.24` (Hermes Agent v0.21.5, commit `f97608f178`)
- **當前版本**:`my-config-v2026.9.21` (基於 `v2026.9.21` / v0.21.4)
- **工作目標**:對齊官方 release tag `v2026.9.24`,維持線性歷史 (Cherry-pick),保留所有自定義層(SSH、Playwright Chromium、rsync、locales、faster-whisper、edge-tts/firecrawl/extras 等),套用 Workflow Purge Protection,觸發 GitHub Actions CI/CD(雙架構 amd64 + arm64),同步升級 Kubernetes 叢集。

---

## 官方 Release (v2026.9.24) 重點摘要與變更分析

### 1. Release 性質(官方原文)
> Patch release. This tag rolls up the ~460 PRs merged since v0.21.4 into a stable tagged release for downstream consumers (Docker images, Hermes Cloud, hosted deployments). **Full curated notes for this window are deferred to v0.22.0.**

- 1,610 non-merge commits / 4,828 changed files / +164,132 / −149,440
- 460 merged PRs / 475 closed issues
- **無 breaking changes 章節**(延後 v0.22.0)

### 2. 變更熱點分布(commit type)
| 類別 | 數量 | 影響面 |
|---|---|---|
| `fix(desktop)` | 206 | Desktop SDK、UI、settings |
| `fix(bot-screen)` | 79 | Bot Screen (`-desktop` 映像) |
| `fix(gateway)` | 50 | Gateway、adapters |
| `feat(desktop)` | 42 | Desktop 新功能 |
| `fix(plugins)` / `chore(plugin-catalog)` | 31 / 28 | 插件系統 |
| `fix(agent)` / `refactor(agent)` | 23 / 12 | Agent core |
| `fix(cli)` | 21 | CLI |
| `fix(update)` | 21 | `hermes update` |
| `feat(catalog)` | 19 | Plugin catalog |

### 3. 重大官方變更(從原始 release body + commit log 拼湊)
- **Desktop plugin SDK wave**:composer draft API、session-list/row-decoration slots、sidebar nav prefs、model-pill label providers、typed settings/skills/toolsets/profiles bridges、sandboxed embed primitive、appearance-settings slot、public event bridge for plugin backends
- **Simple/Advanced Desktop interface mode**
- **Connectors page 取代 MCP tab**,並提供 "Connect now" for 剛安裝插件的 MCP servers;installed plugins' tools/skills 立即在每個開啟的 chat 生效
- **Onboarding 對 catalog plugins 與 connectors 雙向導引**
- **完整法/德/西語 Desktop catalogs + RTL/LTR 文字方向設定**
- **Composer 與 Settings picker 自訂模型輸入**
- **函數鍵與聽寫語音快捷鍵**
- **Per-profile stop/start/restart under host multiplexer** + `gateway.standalone` opt-out
- **CLI 與 TUI live dock** 顯示 standing `/goal` 與 queued prompts
- **Kanban 設計更新**:兩欄 ticket modal + markdown task text
- **Webhook deliveries 鏡像到目標 chat session**
- **Bot Screen on hosted `-desktop` images**(對應 Dockerfile 新 `HERMES_BOT_DESKTOP=1` build arg)
- **GPT-6 Sol/Terra/Luna + Claude Opus 5.5** 加入 Nous 與 OpenRouter catalogs
- 官方 **Blender Lab 整合** + **NVIDIA app/Broadcast plugins**
- 大量 hot-path 效能工作:config loading、tool registry、gateway message handling、model picker
- 數十個 community plugins 加入 catalog

### 4. 對齊衝突風險評估(核心基礎設施)
| 檔案 | 官方 v2026.9.24 變更 | 我們客製 | 風險等級 |
|---|---|---|---|
| **`Dockerfile`** | +59 / −11。新增 `HERMES_BOT_DESKTOP=1` opt-in(Xfce/Xvnc/chromium,apt 約 930 MB);Playwright install 改為 `chrome-headless-shell --only-shell`;新增 `/tmp/.X11-unix`、`/tmp/hermes-runtime`;移除 `hindsight` extra | SSH server、locales (`zh_TW.UTF-8`、`en_US.UTF-8`)、rsync、openssh-server、faster-whisper、edge-tts/firecrawl/dingtalk/feishu/exa extras、`/root/.npm` ownership 給 UID 10000、`ENV HOME=/opt/data`、Playwright CLI 全域、`/tmp/.npm-cache`、固定 package-lock.json | 🔴 **HIGH** — 9 個 Dockerfile 自定義 commit 必須重套 |
| **`docker/stage2-hook.sh`** | 新增 `XDG_RUNTIME_DIR` 安全邊界(395-425 行);Chromium 二進位搜尋順序調整為 shell-first | SSH server 完整區塊(~77-160 行於 my-config 版本);`.bashrc` auto-source `/opt/data/.env`;`HERMES_TUI_DIR` + `npm_config_cache`;container_environment 傳遞至 SSH 登入 shell | 🔴 **HIGH** — SSH 區塊整段重套,且須與官方 XDG_RUNTIME_DIR 邏輯並存不互相干擾 |
| **`docker/entrypoint-ssh.sh`** | (官方無此檔) | 我們新增的 Zeabur/legacy 向後相容 shim | 🟡 **LOW** — 直接從 my-config-v2026.9.21 取回 |
| **`docker/main-wrapper.sh`** | +16 / 0。修正 `-p` flag 解析(不被誤判為 executable) | 無 | 🟢 **NONE** |
| **`pyproject.toml`** | version `0.21.4 → 0.21.5`;**移除 `--extra hindsight`**(hindsight 已離開 tree);**`hermes-agent` script 入口從 `run_agent:main` 改為 `agent.legacy_cli:main`**(重大);新增 `hermes_platform` package;uv sync 命令去掉 `--extra hindsight` | 我方無改動 | 🟡 **MEDIUM** — Dockerfile 中 `uv sync` 參數需更新;若有 CMD 呼叫 `hermes-agent` 需驗證 `agent.legacy_cli:main` 存在 |
| **`.github/workflows/`** | 新增 `live-providers.yml`、`e2e-desktop-core.yml`;`docker.yml` 改動支援 `-desktop` tag;既有 `ci.yaml`/`lint.yaml`/`skills-index.yaml`/`tests-os.yaml`/`tests.yaml` 微調 | 只保留我們的 `ghcr-publish.yml` | 🟢 **NONE** — 依 Workflow Purge Protection 全砍後只留自定義 |
| **`AGENTS.md`** | 新增 `hermes_platform.host` 章節;`[tool.uv] exclude-newer` 14 天規則說明;修訂 plugin dependencies policy | Mac Host Resource Constraint 區塊(末段,2025/9 加入) | 🟢 **LOW** — 客製區塊加在末尾,並存無衝突 |

### 5. 已知 breaking/結構性變更需要我們注意
1. **`hermes-agent` CLI 入口點變更**:從 `run_agent:main` → `agent.legacy_cli:main`
   - 影響:任何 Dockerfile / docker-compose / k8s manifest 直接呼叫 `hermes-agent` 的場景
   - 我們檢視:Dockerfile CMD 為 `["/init"]`(s6 啟動),`main-wrapper.sh` 透過 `drop hermes "$@"` 呼叫,應不受影響
   - **驗證點**:v2026.9.24 中 `agent/legacy_cli.py` 是否存在且 `main()` 為 entry point
2. **uv sync 參數變更**:去掉 `--extra hindsight`
   - 我們 Dockerfile 有 `uv sync --frozen --no-install-project --extra all --extra messaging --extra otlp --extra anthropic --extra bedrock --extra azure-identity --extra hindsight --extra matrix --extra google-chat`
   - **必須改為**:`--extra all --extra messaging --extra otlp --extra anthropic --extra bedrock --extra azure-identity --extra matrix --extra google-chat`
3. **`docker-compose.yml`**:官方 v2026.9.24 的版本與我們從 my-config-v2026.5.16 還原的版本差異
   - 我們 commit `488b1095af` 還原為 85 行版本;官方是否更新需確認

### 6. 待保留的 22 個 my-config 自定義 commit(cherry-pick 清單)
| Commit | Subject |
|---|---|
| `8ca9b1d4f7` | chore: add .env with HERMES_IMAGE for docker-compose |
| `476848b97b` | chore: add ghcr-publish workflow for Docker image build |
| `488b1095af` | chore: restore docker-compose.yml from my-config-v2026.5.16 |
| `6a2606009c` | **feat: integrate SSH and build toolchain into v2026.8.3 Docker architecture** |
| `53aaf2956e` | **feat(docker): add rsync, locales, and full UTF-8 support** |
| `6177971ddd` | **feat(docker): install full Playwright Chromium with proper permissions** |
| `e7a7df913f` | ci: add platform choice to workflow defaulting to amd64 |
| `da7593eaa6` | **fix(docker): propagate s6 container_environment to SSH sessions and fix faster-whisper PYTHONPATH** |
| `3434ff9cdb` | **feat(docker): build faster-whisper (voice extra) directly into image** |
| `c2c387d98e` | **fix(docker): ensure /root/.npm ownership is granted to hermes user (UID 10000)** |
| `859bbee15e` | **fix(docker): set ENV HOME=/opt/data to prevent non-root processes from accessing /root** |
| `6505927ea5` | **feat(docker): restore dropped extras (edge-tts, firecrawl, dingtalk, feishu, exa) and install playwright** |
| `b6a0809854` | **chore: add Mac host resource constraint rule to AGENTS.md** |
| `0be373bd1a` | **fix(docker): bake playwright CLI globally and isolate npm cache to /tmp** |
| `33dfe55beb` | **fix(docker): persist fixed package-lock.json and enforce post-copy npm audit fix** |
| `d58cb7c4af` | **chore(ci): upgrade to native arm64 runner (ubuntu-24.04-arm) and purge non-essential workflows** |
| `3c9d596114` | **ci: default platforms to all for dual-arch build (amd64 + arm64) using native runners** |
| `b26a1ce554` | chore: bump HERMES_IMAGE tag to v2026.9.21 |
| `c9666c2fee` | docs: restore historical upgrade logs from my-config-v2026.9.14 |
| `b3bb5aa7c0` | docs: add upgrade log and worksheet v2026.9.14 to v2026.9.21 |
| `c997dbfa03` | docs: record GitHub Actions run ID in worksheet |
| `a006177954` | docs: finalize upgrade worksheet for v2026.9.21 |

---

## 升級執行檢查清單 (Worksheet Checklist)

### Phase 1: 準備與分支建立 (Pre-Execution & Branch Setup)
- [ ] 取得使用者確認 Go-Sign(等待 user reply)
- [ ] 備份當前分支:`git branch backup/my-config-v2026.9.21`
- [ ] 從官方 release tag 建立新分支:`git checkout -b my-config-v2026.9.24 v2026.9.24`
- [ ] 重新 `git fetch origin --tags` 確認 v2026.9.24 SHA 一致

### Phase 2: 基礎配置 Cherry-Pick (Base Config Cherry-Pick)
- [ ] `8ca9b1d4f7` cherry-pick — `.env` HERMES_IMAGE for docker-compose
- [ ] `476848b97b` cherry-pick — `ghcr-publish.yml` workflow
- [ ] `488b1095af` cherry-pick — docker-compose.yml restore
- **若 cherry-pick 衝突(預期):**
  - `docker-compose.yml`:檢查官方 v2026.9.24 是否也有更新,採三方合併或人工整合(我們的 85 行版本含 `hermes-bot-desktop` service profile 設定)

### Phase 3: Dockerfile 自定義層重建 (Dockerfile Custom Layer Rebuild)🔴 HIGH RISK
**策略:不直接 cherry-pick(因官方 Dockerfile 變動大),而是將每個自定義 commit 的 hunks 人工移植到 v2026.9.24 基礎上。**

- [ ] **基底**:以 v2026.9.24 官方 Dockerfile 為起點(513 行)
- [ ] 套用 `6a2606009c` — 加入 `openssh-server`、`/var/run/sshd`、`ssh-keygen -A`、`rsync`、`locales`、`zh_TW.UTF-8`、`en_US.UTF-8` 至 `apt-get install` 區塊
- [ ] 套用 `6177971ddd` — Playwright Chromium `--with-deps` 改回完整版本(官方 v2026.9.24 已預設為 `--only-shell`,我們要 `--with-deps` 兩段式?)
- [ ] 套用 `6505927ea5` — uv sync 加上 `--extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa`(若 plugins.yaml 中仍定義)
- [ ] 套用 `3434ff9cdb` — faster-whisper (voice extra) 烤進 image
- [ ] 套用 `53aaf2956e` — locales(`/etc/locale.gen`、`locale-gen`、`/etc/default/locale`)
- [ ] 套用 `c2c387d98e` — `/root/.npm` ownership 給 UID 10000
- [ ] 套用 `859bbee15e` — `ENV HOME=/opt/data`
- [ ] 套用 `0be373bd1a` — Playwright CLI 全域 + `/tmp/.npm-cache` 隔離
- [ ] 套用 `33dfe55beb` — package-lock.json 固定 + post-copy `npm audit fix`
- [ ] 套用 `da7593eaa6` — s6 container_environment 與 faster-whisper PYTHONPATH(主要改 stage2-hook.sh,但 Dockerfile 中間層亦可能有調整)
- [ ] **🚨 關鍵更新**:`uv sync` 參數 **必須移除 `--extra hindsight`**(配合官方 v2026.9.24)
- [ ] 驗證最終 `uv sync --frozen --no-install-project --extra all --extra messaging --extra otlp --extra anthropic --extra bedrock --extra azure-identity --extra matrix --extra google-chat` 與自定義 extras
- [ ] 整合 `COPY --chmod=0755 docker/entrypoint-ssh.sh /opt/hermes/docker/entrypoint-ssh.sh`(從 entrypoint-ssh.sh 移植)

### Phase 4: stage2-hook.sh SSH 區塊重建 (stage2 SSH Block Rebuild)🔴 HIGH RISK
**策略:從 my-config-v2026.9.21:docker/stage2-hook.sh 取出我們的 SSH 區塊(約 77-160 行),合併到 v2026.9.24 官方版。**

- [ ] 取出 SSH setup block(從 my-config-v2026.9.21 取得 77-160 行):
  - `/run/sshd` mkdir
  - `$HERMES_HOME/.ssh` mkdir + authorized_keys
  - `.bashrc` auto-source `/opt/data/.env` + `set -a` / `unset SSH_PUBLIC_KEY`
  - `export PATH="/opt/hermes/.venv/bin:$PATH"`
  - `export HERMES_TUI_DIR=/opt/hermes/ui-tui`
  - `export npm_config_cache=/tmp/.npm-cache`
  - container_environment 載入 loop
  - `/usr/sbin/sshd` background start
- [ ] 選擇合併位置:在官方 `as_hermes mkdir -p ...` 區塊(約 381 行)之前插入
- [ ] 驗證 SSH 區塊與官方 XDG_RUNTIME_DIR 區塊(395-425)無變數/邏輯衝突
- [ ] 確保 SSH server 啟動仍位於 `as_hermes` 用戶 drop 之前(因為 sshd 需要 root)

### Phase 5: entrypoint-ssh.sh 還原 (Restore entrypoint-ssh.sh)
- [ ] 從 my-config-v2026.9.21 取得 `docker/entrypoint-ssh.sh` 並 commit:
  ```
  chore: restore docker/entrypoint-ssh.sh for Zeabur backward compatibility
  ```

### Phase 6: docker-compose.yml 整合 (Compose File Integration)
- [ ] 對比 v2026.9.21 + my-config + v2026.9.24 三方 docker-compose.yml
- [ ] 我們的版本(來自 my-config-v2026.5.16 restore,85 行)與 v2026.9.24 是否有結構衝突
- [ ] 確認 `hermes-bot-desktop` service profile 是否需要對應官方 `-desktop` tag build(選用)

### Phase 7: pyproject.toml 驗證 (pyproject.toml Validation)
- [ ] 確認我們的 Dockerfile `uv sync` 命令已移除 `--extra hindsight`
- [ ] 驗證 `agent/legacy_cli.py:def main()` 存在於 v2026.9.24
- [ ] 若發現 `hermes-agent` 入口點被我們的任何 script/CI 引用,確認仍能運作

### Phase 8: AGENTS.md Mac Host 規則追加 (Mac Host Rule Append)
- [ ] cherry-pick `b6a0809854` — Mac host resource constraint 規則(預期無衝突,加在末尾)

### Phase 9: Workflow Purge Protection (CI Workflow Purge)
- [ ] 執行 workflow 清理:
  ```bash
  find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete
  git add -A .github/workflows
  git commit -m "chore(ci): purge official CI workflows; retain only ghcr-publish.yml"
  ```
- [ ] 驗證 `.github/workflows/` 只剩 `ghcr-publish.yml`

### Phase 10: HERMES_IMAGE Tag 更新 (Bump Image Tag)
- [ ] 修改 `.env`:`HERMES_IMAGE=v2026.9.24`
- [ ] 修改 `docker-compose.yml` 任何 `image:` 引用
- [ ] commit:
  ```
  chore: bump HERMES_IMAGE tag to v2026.9.24
  ```

### Phase 11: 本地輕量驗證 (Local Lightweight Verification)
- [ ] `git status` 工作區乾淨
- [ ] `git log --oneline my-config-v2026.9.21..my-config-v2026.9.24` 線性歷史檢查
- [ ] Dockerfile 結構語法肉眼檢查(`RUN`/`COPY`/`ENV` 區塊對齊)
- [ ] **禁止**:`uv run pytest`、`docker build`、重型 typecheck — 一律交給 CI

### Phase 12: 推送分支 (Push Branch)
- [ ] `git push kuniakil my-config-v2026.9.24`(先推分支,不推 tag)

### Phase 13: GitHub Actions 映像檔建置 (CI/CD Build)
- [ ] 觸發 `ghcr-publish.yml` workflow:
  ```bash
  gh workflow run ghcr-publish.yml \
    --repo kuniakil/hermes-agent \
    --ref my-config-v2026.9.24 \
    -f tag_name=v2026.9.24 \
    -f platforms=all
  ```
- [ ] 記錄 GitHub Actions Run ID 到本 worksheet
- [ ] 追蹤雙架構(amd64 + arm64)native runner 建置狀態
- [ ] 驗證建置結果:`ghcr.io/kuniakil/hermes-agent:v2026.9.24` 存在

### Phase 14: Kubernetes 叢集部署與驗證 (K8s Deployment & Verification)
- [ ] 更新 Kubernetes `hermes` deployment 映像檔 tag 為 `v2026.9.24`
- [ ] 觀察 Pod rolling update 狀態
- [ ] 進入 Pod 執行 `hermes doctor` 驗證全數通過
- [ ] 驗證 SSH 登入、Playwright Chromium、API 連線及 state.db 運作
- [ ] 同步更新集中式憑證庫 `~/kubernetes/.secrets.env`(若需要)
- [ ] 標記工作表全部完成並歸檔升級記錄

### Phase 15: 文檔與歸檔 (Documentation & Archival)
- [ ] 建立 `UPGRADE_LOG_v2026.9.21_to_v2026.9.24.md`
- [ ] 還原/新增歷史升級 log 段落
- [ ] 更新本 worksheet 為全部 `- [x]`
- [ ] 最終 commit + push

---

## ⚠️ 風險與注意事項

1. **官方 v0.21.5 把 `hermes-agent` script 入口點從 `run_agent:main` 改為 `agent.legacy_cli:main`** — 雖然我們不直接呼叫 `hermes-agent`,但若 s6 service 或 entrypoint 有依賴會出問題,Phase 7 必須驗證
2. **`uv sync` 參數必須更新**:`--extra hindsight` 在 v2026.9.24 已不存在於 pyproject.toml,留著會導致 image build 失敗
3. **Playwright 安裝行為改變**:v2026.9.24 預設只裝 `chrome-headless-shell`,我們過去裝完整版是為了 SSH/agent-browser 通用,需評估是否保留 `--with-deps chromium`(而非 `--only-shell`)
4. **Dockerfile 體積影響**:`HERMES_BOT_DESKTOP=1` 是 opt-in,我們預設不開,但 Docker 映像建置 script(`docker.yml`)的 binary tag 拆 `-desktop` 變體不會影響我們(我們只跑預設 build)
5. **AGENTS.md 新章節 `hermes_platform.host`**:我們的 Mac host constraint 章節須確保仍位於檔案末尾(避免被官方章節覆蓋)
6. **大改動範圍**:1,638 commits / 4,828 files 改動 — 即使我們的 cherry-pick 策略是基於檔案級別的 `git checkout <commit> -- <files>`,仍可能遇到非預期的衝突。建議每個階段完成後立即 commit,失敗時可局部回滾

---

## 📂 預期檔案清單 (Artifacts)

### 新增
- `docs/worksheet-upgrade-hermes-v2026.9.24-20260925.md`(本檔)
- `UPGRADE_LOG_v2026.9.21_to_v2026.9.24.md`

### 修改
- `Dockerfile`(主要 — 重新整合自定義層)
- `docker/stage2-hook.sh`(主要 — SSH 區塊重建)
- `docker-compose.yml`(可能)
- `.env`(HERMES_IMAGE tag)
- `AGENTS.md`(Mac host rule 加回末尾)

### 還原
- `docker/entrypoint-ssh.sh`(從 my-config-v2026.9.21 取回)

### 保留
- `.github/workflows/ghcr-publish.yml`(我們的優化版)
- 所有 `docs/UPGRADE_LOG_*.md` 歷史檔案

---

## 🟢 Go-Sign 等待

**請確認以下事項後再下達 "Go" 指令:**

1. ✅ 同意上述風險評估與執行策略(尤其 Phase 3 / 4 的 Dockerfile + stage2-hook.sh 重建)
2. ✅ 同意備份分支命名為 `backup/my-config-v2026.9.21`
3. ✅ 同意保留 Playwright 完整版(`--with-deps chromium`)而非官方預設的 `--only-shell`
4. ✅ 同意 uv sync 移除 `--extra hindsight` 與新增 `agent/legacy_cli:main` 驗證
5. ✅ 同意不觸碰官方 Bot Screen(`HERMES_BOT_DESKTOP=1`)路徑,只建置預設 image
6. ✅ 同意先推分支不推 tag,待 GitHub Actions 建置成功後再 `git tag -f v2026.9.24 && git push -f origin v2026.9.24`

**收到 "Go" 後,我會嚴格依照 SOP 順序執行,且不會在本地跑任何 docker build 或 pytest。**