# 升級衝突解決方案:v2026.9.21 → v2026.9.24

> 對應工作表:`docs/worksheet-upgrade-hermes-v2026.9.24-20260925.md`
> 本文件詳列每個衝突點的**具體解決策略**與**hunk 級合併步驟**,供執行階段使用。

---

## 📊 衝突全景圖

| # | 檔案 | 衝突類型 | 嚴重度 | 解決策略 |
|---|---|---|---|---|
| 1 | `Dockerfile` | **內容衝突**(apt + playwright + uv sync 改動) | 🔴 HIGH | 人工移植(hunk-level),不走 cherry-pick |
| 2 | `docker/stage2-hook.sh` | **刪除衝突**(官方移除我們的 SSH/cleanup) | 🔴 HIGH | 人工移植(hunk-level),不走 cherry-pick |
| 3 | `docker/entrypoint-ssh.sh` | **檔案不存在衝突** | 🟡 MEDIUM | 直接從 my-config 取回 |
| 4 | `docker-compose.yml` | **可能內容衝突**(確認中) | 🟢 LOW | 三方比對後取較新版本 |
| 5 | `pyproject.toml` | **結構性變更**(`hermes-agent` 入口、`hindsight` extra 移除) | 🟡 MEDIUM | 採官方版本 + Dockerfile 參數更新 |
| 6 | `.github/workflows/*` | **大量新檔衝突** | 🟢 LOW | 全砍後只留 `ghcr-publish.yml` |
| 7 | `AGENTS.md` | **無實質衝突** | 🟢 LOW | 採官方版本 + 末尾追加 Mac host rule |
| 8 | `.env` | **無衝突** | 🟢 LOW | 只改 `HERMES_IMAGE` tag |

---

## 衝突 1 🔴 Dockerfile — 高風險

### 1.1 衝突盤點

| 區塊 | v2026.9.24 官方 | 我們 my-config-v2026.9.21 | 衝突形式 |
|---|---|---|---|
| `apt-get install` (line ~74) | `ca-certificates curl iputils-ping python3 ... openssh-client docker-cli xz-utils`(14 個 package) | 同上 **+ openssh-server + rsync + locales**(17 個 package),**+ mkdir sshd + ssh-keygen -A + locale-gen + /etc/default/locale + /etc/profile + /home/node/.bashrc + /root/.bashrc** | 我們要**新增 3 個 package + 8 行配置**,無重疊衝突 |
| `HERMES_BOT_DESKTOP` (line ~76-90) | **新增 opt-in 區塊**(Xfce/Xvnc/chromium,apt 約 930 MB,僅當 `ARG HERMES_BOT_DESKTOP=1`) | 無 | 官方新增,我們無變動 → **採納官方區塊** |
| Playwright install (line ~217-228) | `--with-deps chromium --only-shell` (僅 shell) | 改回 `--with-deps chromium`(完整版) | **語意衝突**:我們堅持完整版 |
| Playwright BOT_DESKTOP (line ~230-237) | **新增 gated 完整版**(僅 `HERMES_BOT_DESKTOP=1` 時安裝) | 我們裝的完整版覆蓋所有 build | 官方把完整版 gate 起來,我們的策略需調整 |
| `/tmp/.X11-unix` / `/tmp/hermes-runtime` (line ~311-315) | **新增** | 無 | 採納官方 |
| `uv sync` extras (line ~298) | `--extra all --extra messaging --extra otlp --extra anthropic --extra bedrock --extra azure-identity --extra matrix --extra google-chat`(已**移除** `--extra hindsight`) | 我們加上 `--extra edge-tts --extra firecrawl --extra dingtalk --extra feishu --extra exa --extra hindsight` | **extras 組合衝突**:hindsight 必須移除,其他保留 |
| `COPY --chmod=0755 docker/entrypoint-ssh.sh` (line ~458 my-config) | 無(官方無此 COPY) | 有(我們加的) | **採納我方** |
| 後段 env(`HERMES_DISABLE_LAZY_INSTALLS=1` 之後) | 多個 `ENV` / `CMD` 微調 | 可能保留我們的 `ENV HOME=/opt/data` 等 | 逐行比對 |

### 1.2 解決策略:**人工移植**(不走 cherry-pick)

**理由**:官方 Dockerfile 共 513 行,我們 my-config 共 508 行,差異跨多個不相鄰區塊且邏輯互相穿插。`git cherry-pick` 會失敗,必須以 v2026.9.24 為基底,逐 hunk 把我們客製 hunks 插入對應處。

### 1.3 執行步驟

```bash
# 1. 從 v2026.9.24 取出官方 Dockerfile 作為基底
git checkout v2026.9.24 -- Dockerfile

# 2. 依序套用我們的 hunks(用 edit 工具,精確匹配)
```

**Hunk A — `apt-get install` 區塊(擴大 package 清單 + 加 locales/ssh 初始化)**

原 v2026.9.24 line 74:
```dockerfile
RUN apt-get -o Acquire::Retries=3 update && \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
    ca-certificates curl iputils-ping python3 python-is-python3 ripgrep ffmpeg gcc g++ make cmake python3-dev python3-venv libffi-dev libolm-dev libatomic1 procps git openssh-client docker-cli xz-utils && \
    rm -rf /var/lib/apt/lists/*
```

改為(在 `xz-utils` 後加 `openssh-server rsync locales`,並在 layer 末尾加入 sshd/locale 初始化):
```dockerfile
RUN apt-get -o Acquire::Retries=3 update && \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
    ca-certificates curl iputils-ping python3 python-is-python3 ripgrep ffmpeg gcc g++ make cmake python3-dev python3-venv libffi-dev libolm-dev libatomic1 procps git openssh-client openssh-server docker-cli xz-utils rsync locales && \
    mkdir -p /var/run/sshd && ssh-keygen -A && \
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
    echo "export LC_ALL=C.UTF-8" >> /root/.bashrc && \
    rm -rf /var/lib/apt/lists/*
```

**Hunk B — Playwright 改回完整版**

原 v2026.9.24 line ~217-222:
```dockerfile
RUN npm install --prefer-offline --no-audit --fetch-retries=5 && \
    for i in 1 2 3; do \
        npx playwright install --with-deps chromium --only-shell && break || \
        { [ "$i" = 3 ] && exit 1; echo "playwright headless-shell install failed (attempt $i); retrying in 10s"; sleep 10; }; \
    done && \
    npm cache clean --force
```

改為(去掉 `--only-shell`,讓預設 build 也裝完整 chromium):
```dockerfile
RUN npm install --prefer-offline --no-audit --fetch-retries=5 && \
    for i in 1 2 3; do \
        npx playwright install --with-deps chromium && break || \
        { [ "$i" = 3 ] && exit 1; echo "playwright install failed (attempt $i); retrying in 10s"; sleep 10; }; \
    done && \
    npm cache clean --force
```

> **決策點**:雖然官方把完整版 gate 在 `HERMES_BOT_DESKTOP=1` 之後才裝,但我們的 SSH / agent-browser 路徑仍需 headed Chromium。把預設改回 `--with-deps chromium`(不去掉下方 BOT_DESKTOP 的二次安裝也無妨,Playwright 會偵測已安裝跳過)。

**Hunk C — `/tmp/.npm-cache` 隔離(commit `0be373bd1a`)**

在 Bot Screen `mkdir -p /tmp/.X11-unix` 之前/之後追加(具體插入哪裡需視 build cache 友善度):
```dockerfile
# Isolate npm global cache to /tmp to avoid EACCES on read-only /root
RUN mkdir -p /tmp/.npm-cache && chmod 1777 /tmp/.npm-cache
ENV npm_config_cache=/tmp/.npm-cache
```

**Hunk D — `uv sync` extras 組合(commit `6505927ea5` + 移除 hindsight)**

原 v2026.9.24 line ~298:
```dockerfile
RUN uv sync --frozen --no-install-project --extra all --extra messaging --extra otlp --extra anthropic --extra bedrock --extra azure-identity --extra matrix --extra google-chat
```

改為(加上我們要保留的 extras,**不**加 `hindsight`):
```dockerfile
RUN uv sync --frozen --no-install-project \
    --extra all --extra messaging --extra otlp --extra anthropic --extra bedrock --extra azure-identity \
    --extra matrix --extra google-chat \
    --extra edge-tts --extra firecrawl
```

> ⚠️ **驗證前先檢查**:`edge-tts`、`firecrawl`、`dingtalk`、`feishu`、`exa` 是否仍在 v2026.9.24 的 `[project.optional-dependencies]` 區塊中。若已被官方刪除,改用 `uv pip install` 直接裝 pinned 版本,或在 `requirements.txt` 補。

驗證指令(執行前必跑):
```bash
git show v2026.9.24:pyproject.toml | grep -E "^(edge-tts|firecrawl|dingtalk|feishu|exa|hindsight)\s*="
```

**Hunk E — `entrypoint-ssh.sh` COPY**

在 Dockerfile 後段(找 `COPY docker/entrypoint.sh` 這類 COPY 指令附近)加入:
```dockerfile
# Backward-compatible SSH entrypoint shim (Zeabur / custom deployments)
COPY --chmod=0755 docker/entrypoint-ssh.sh /opt/hermes/docker/entrypoint-ssh.sh
```

**Hunk F — 後段 `ENV HOME=/opt/data`(commit `859bbee15e`)**

在合適位置(找 `ENV HERMES_HOME` 附近)加入:
```dockerfile
# Prevent non-root processes from reading /root (which would expose SSH keys etc.)
ENV HOME=/opt/data
```

**Hunk G — `/root/.npm` ownership 給 hermes(commit `c2c387d98e`)**

由於 `RUN uv sync ...` 階段以 root 執行,`/root/.npm` 預設 root-owned,而後續 drop 到 hermes UID 10000 後 npm cache 會 EACCES。建議在 `RUN uv sync` 之後加:
```dockerfile
# Grant hermes user ownership of /root/.npm (created by uv/npm during build)
RUN mkdir -p /root/.npm && chown -R 10000:10000 /root/.npm
```

### 1.4 完成後 commit

```bash
git add Dockerfile
git commit -m "feat(docker): re-port custom layer (SSH, locales, faster-whisper extras) onto v2026.9.24

- openssh-server + rsync + locales (zh_TW/en_US UTF-8)
- Playwright full chromium (override --only-shell default for SSH/agent-browser)
- uv sync extras: drop hindsight, keep edge-tts/firecrawl
- /tmp/.npm-cache isolation + ENV HOME=/opt/data
- docker/entrypoint-ssh.sh shim COPY

Ref: 6a2606009c 53aaf2956e 6177971ddd 6505927ea5 c2c387d98e 859bbee15e 0be373bd1a"
```

---

## 衝突 2 🔴 docker/stage2-hook.sh — 高風險

### 2.1 衝突盤點

| 區塊 | v2026.9.24 官方 | 我們 my-config-v2026.9.21 | 衝突形式 |
|---|---|---|---|
| Line ~78 SSH setup | **無此區塊** | `# --- SSH server setup ---`(82 行) + `.bashrc` + `.profile` + sshd start | 官方**移除**了我們所有 SSH 相關 |
| Line ~84 `mkdir -p .npm .cache .config` | **無** | 我們額外加 `mkdir -p "$HERMES_HOME/.npm" "$HERMES_HOME/.cache" "$HERMES_HOME/.config"` | 官方移除(優化) |
| Line ~395 XDG_RUNTIME_DIR | **新增**(18 行安全邊界 + chown) | 無 | 採納官方 |
| Line ~478 `/tmp/.npm-cache` sticky + `.npm` cleanup | **無** | 我們的 `mkdir -p /tmp/.npm-cache && chmod 1777` + `rm -rf $HERMES_HOME/.npm` | 我們要重套 |
| Line ~771 Chromium search | `chrome-headless-shell` first, fallback to `chrome/chromium` | 單一 find | 採納官方新邏輯(更乾淨) |

### 2.2 解決策略:**基底取代 + Hunk 移植**

**理由**:官方結構性改動大(801 vs 856 行),SSH 區塊官方完全沒有了。採 `git checkout v2026.9.24 -- docker/stage2-hook.sh` 取官方版,再把我們的 hunks 插入對應位置。

### 2.3 執行步驟

```bash
# 1. 以官方版本為基底
git checkout v2026.9.24 -- docker/stage2-hook.sh
```

**Hunk A — SSH 區塊插入(在 line ~78 `exit 1` 之後,`# --- Bootstrap HERMES_HOME as root ---` 之前)**

精確插入點:
```bash
fi

# --- SSH server setup ---
# Setup SSH for remote access. This runs early because sshd needs
# the hermes user to exist first (before UID/GID remap below).
if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
    echo "[stage2] Setting up SSH server"
    mkdir -p /run/sshd
    mkdir -p "$HERMES_HOME/.ssh"

    # Write authorized_keys from SSH_PUBLIC_KEY env var
    SSH_KEY_CLEAN=$(echo "$SSH_PUBLIC_KEY" | sed 's/^"//;s/"$//')
    echo "$SSH_KEY_CLEAN" > "$HERMES_HOME/.ssh/authorized_keys"
    chmod 600 "$HERMES_HOME/.ssh/authorized_keys"
    chown -R hermes:hermes "$HERMES_HOME/.ssh"

    # Create .bashrc to auto-source .env for SSH sessions
    cat > "$HERMES_HOME/.bashrc" <<'EOF'
# Auto-source environment variables for SSH login
if [ -f /opt/data/.env ]; then
    set -a
    . /opt/data/.env
    set +a
    unset SSH_PUBLIC_KEY
fi
export PATH="/opt/hermes/.venv/bin:$PATH"
export HERMES_TUI_DIR=/opt/hermes/ui-tui
export npm_config_cache=/tmp/.npm-cache
# Load runtime env vars written by stage2-hook.sh into s6 container_environment
# (e.g. AGENT_BROWSER_EXECUTABLE_PATH, PYTHONPATH for faster-whisper).
if [ -d /run/s6/container_environment ]; then
    for _env_f in /run/s6/container_environment/*; do
        [ -f "$_env_f" ] || continue
        _env_key=$(basename "$_env_f")
        _env_val=$(cat "$_env_f")
        export "${_env_key}=${_env_val}"
    done
    unset _env_f _env_key _env_val
fi
EOF
    chown hermes:hermes "$HERMES_HOME/.bashrc"

    # Create .profile for sh login shells
    cat > "$HERMES_HOME/.profile" <<'EOF'
if [ -f /opt/data/.env ]; then
    set -a
    . /opt/data/.env
    set +a
    unset SSH_PUBLIC_KEY
fi
export PATH="/opt/hermes/.venv/bin:$PATH"
export HERMES_TUI_DIR=/opt/hermes/ui-tui
export npm_config_cache=/tmp/.npm-cache
if [ -d /run/s6/container_environment ]; then
    for _env_f in /run/s6/container_environment/*; do
        [ -f "$_env_f" ] || continue
        _env_key=$(basename "$_env_f")
        _env_val=$(cat "$_env_f")
        export "${_env_key}=${_env_val}"
    done
    unset _env_f _env_key _env_val
fi
EOF
    chown hermes:hermes "$HERMES_HOME/.profile"

    # Start sshd in background
    /usr/sbin/sshd
    echo "[stage2] SSH server started"
fi

# --- Bootstrap HERMES_HOME as root ---
```

> **互動驗證**:官方 XDG_RUNTIME_DIR 區塊(line ~395)會檢查 `actual_hermes_uid` 變數。確認 SSH 區塊插在此檢查之前**不會干擾** `actual_hermes_uid` 的值(我們的 SSH 區塊只用 `$(id -u hermes)` 或 `$hermes` 變數,不會 reset `actual_hermes_uid`)。

**Hunk B — `/tmp/.npm-cache` sticky + `.npm` cleanup(在 XDG_RUNTIME_DIR 區塊之後,`# --- Install-method stamp ---` 之前)**

精確插入點:
```bash
fi

# Ensure global /tmp/.npm-cache exists with sticky bit permissions for any user
mkdir -p /tmp/.npm-cache && chmod 1777 /tmp/.npm-cache

# Self-heal / clean legacy stale .npm from data volume
if [ -d "$HERMES_HOME/.npm" ]; then
    rm -rf "$HERMES_HOME/.npm" 2>/dev/null || true
fi

# --- Install-method stamp ---
```

### 2.4 完成後 commit

```bash
git add docker/stage2-hook.sh
git commit -m "fix(docker): re-port SSH server setup and npm cache isolation onto v2026.9.24

- SSH server setup block (sshd + authorized_keys + .bashrc/.profile auto-source)
- /tmp/.npm-cache sticky bit for global npm cache
- self-heal legacy $HERMES_HOME/.npm

Ref: 6a2606009c da7593eaa6 0be373bd1a"
```

---

## 衝突 3 🟡 docker/entrypoint-ssh.sh — 中風險

### 3.1 衝突盤點

- **v2026.9.24 官方**:**無此檔案**(diff 顯示 `deleted file` — 那是因為之前 my-config 還有,對比 v2026.9.24 沒有)
- **我們 my-config**:`docker/entrypoint-ssh.sh` 13 行 shim,呼叫 `entrypoint-dispatch.sh`

### 3.2 解決策略:**直接從 my-config 取回**

```bash
git checkout my-config-v2026.9.21 -- docker/entrypoint-ssh.sh
git add docker/entrypoint-ssh.sh
git commit -m "fix(docker): restore docker/entrypoint-ssh.sh for Zeabur backward compatibility"
```

---

## 衝突 4 🟢 docker-compose.yml — 低風險

### 4.1 衝突盤點

| 來源 | 內容 |
|---|---|
| v2026.9.21 官方 | `services.gateway` 標準定義,75 行 |
| v2026.9.24 官方 | `services.gateway` 標準定義,75 行(內容與 v2026.9.21 相同) |
| 我們 my-config-v2026.9.21 | 從 my-config-v2026.5.16 還原的 85 行版本,內容大致一致 |

### 4.2 解決策略:**採用 my-config 還原版(我們的 commit `488b1095af`)**

```bash
git checkout my-config-v2026.9.21 -- docker-compose.yml
git diff v2026.9.24 -- docker-compose.yml  # 確認差異可接受
```

若差異極小(< 5 行),可接受;
若差異大,採三方合併或留官方版(因為官方 v2026.9.24 與 my-config 一致)。

### 4.3 完成後

```bash
git add docker-compose.yml
git commit -m "chore: restore docker-compose.yml from my-config-v2026.5.16 (carry forward)"
```

---

## 衝突 5 🟡 pyproject.toml — 中風險

### 5.1 衝突盤點

| 變更 | 細節 |
|---|---|
| version | `0.21.4 → 0.21.5` |
| `[project.optional-dependencies]` | 移除 `hindsight = ["hindsight-client==0.6.1"]` 整行 |
| `[tool.uv] exclude-newer-package]` | 移除 `hindsight-client = false` 整行 |
| `[project.scripts] hermes-agent` | `run_agent:main → agent.legacy_cli:main` |
| `[tool.setuptools.packages.find] include` | 新增 `hermes_platform.*` |

### 5.2 解決策略:**完全採納官方版本**

**理由**:
- 我們的 my-config-v2026.9.21 **沒有修改** pyproject.toml(`git diff v2026.9.21..my-config-v2026.9.21 -- pyproject.toml` 為空)
- 官方變動都屬於 hermes 內部結構,我們的 Dockerfile 中只有一行 `uv sync` 引用了 `--extra hindsight`(必須手動修正)

### 5.3 衝突的解決策略

**衝突 1:`hermes-agent` script 入口點變更**(`run_agent:main` → `agent.legacy_cli:main`)

**問題**:`agent/legacy_cli.py` 是 v2026.9.24 新檔案,當我們 `git checkout v2026.9.24 -- .` 時會自動帶進來。但需要確認 `agent/legacy_cli.py` 內部是否引用了我們可能移除的東西。

**驗證指令**(執行前必跑):
```bash
git show v2026.9.24:agent/legacy_cli.py | head -30
# 確認它 import 了 run_agent.main 或 run_agent 內的元件
```

**風險**:若 `agent/legacy_cli.py` 假設某些 v2026.9.24 之後才有的相依套件存在,但因為我們沒用 `hermes-agent` 這個 CLI(只用 `hermes`),理論上無影響。

**衝突 2:`--extra hindsight` 必須從 Dockerfile `uv sync` 移除**

這個已在「衝突 1 - Hunk D」處理完畢。

**衝突 3:新套件 `hermes_platform.*`**

採納官方自動帶入的套件包。

### 5.4 完成後

**無獨立 commit**(我們沒改 pyproject.toml,採官方版即可)。

---

## 衝突 6 🟢 .github/workflows/ — 低風險

### 6.1 衝突盤點

官方 v2026.9.24 新增/修改的工作流:
- `ci.yaml`(修改)
- `docker.yml`(大幅修改,支援 `-desktop` tag)
- `e2e-desktop-core.yml`(**新增**)
- `lint.yml`(微調)
- `live-providers.yml`(**新增**)
- `skills-index.yml`(修改)
- `tests-os.yml`(微調)
- `tests.yml`(大幅修改)

### 6.2 解決策略:**Workflow Purge Protection**

完全依 SOP 執行:
```bash
# 1. 從 my-config 取出我們優化的 ghcr-publish.yml
git checkout my-config-v2026.9.21 -- .github/workflows/

# 2. 刪除所有官方 workflow
find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete

# 3. Commit
git add -A .github/workflows
git commit -m "chore(ci): purge official CI workflows; retain only ghcr-publish.yml"
```

> **注意**:在我們自定義的 `ghcr-publish.yml` 中,Dockerfile 引用了我們 `COPY --chmod=0755 docker/entrypoint-ssh.sh`(若 workflow 用 docker build 的話)。需確認 workflow 沒有硬編碼 Dockerfile 路徑或 layer 預期。

---

## 衝突 7 🟢 AGENTS.md — 低風險

### 7.1 衝突盤點

| 變更 | 細節 |
|---|---|
| v2026.9.24 新增 | `hermes_platform.host` 章節(line ~286+) |
| v2026.9.24 新增 | `[tool.uv] exclude-newer` 14 天規則說明(line ~323+) |
| 我們 my-config 加 | 「Local Resource Constraint (Mac Host Protection)」區塊(檔案末段) |

### 7.2 解決策略:**採官方版 + 末尾追加 Mac host rule**

```bash
# 1. 取官方版
git checkout v2026.9.24 -- AGENTS.md

# 2. 末尾追加我們的 Mac host rule(從 my-config 取出)
cat >> AGENTS.md <<'EOF'

## Local Resource Constraint (Mac Host Protection)

- **Strict Resource Rule**: DO NOT run heavy test suites (`pytest`, full test matrix, `uv run pytest`), heavy typechecks, or local `docker build` directly on the local machine.
- Local verification MUST only check git status, file diffs, and lightweight syntax.
- All compilation, container packaging, and full test runs MUST be offloaded to GitHub Actions CI (`docker-release.yml` / `ghcr-publish.yml`).
EOF

git add AGENTS.md
git commit -m "chore: re-append Mac host resource constraint rule to AGENTS.md (v2026.9.24)"
```

> **互動驗證**:Mac host rule 加在末尾,**不會**影響官方新增的 `hermes_platform.host` 章節(章節位於 line 286,Mac rule 在 line 800+)。

---

## 衝突 8 🟢 .env — 低風險

### 8.1 解決策略:**只改 HERMES_IMAGE tag**

```bash
sed -i '' 's/HERMES_IMAGE=v2026.9.21/HERMES_IMAGE=v2026.9.24/' .env

git add .env
git commit -m "chore: bump HERMES_IMAGE tag to v2026.9.24"
```

---

## 🎯 衝突解決順序(執行 Checklist)

依照這個順序解決衝突,可最大化自動化、最小化手動介入:

```
Phase 1: Branch + 基礎
   ├── 1a. 備份 my-config-v2026.9.21
   ├── 1b. checkout v2026.9.24
   └── 1c. checkout v2026.9.24 -- Dockerfile  stage2-hook.sh  AGENTS.md  pyproject.toml
                                (基底取代)

Phase 2: 高風險手動移植
   ├── 2a. Dockerfile  hunks (Hunk A-G)
   ├── 2b. stage2-hook.sh hunks (Hunk A-B)
   └── 2c. cherry-pick b6a0809854 (Mac host rule,先不要 commit)

Phase 3: 簡單恢復
   ├── 3a. checkout my-config-v2026.9.21 -- docker/entrypoint-ssh.sh
   ├── 3b. checkout my-config-v2026.9.21 -- docker-compose.yml (若採用)
   └── 3c. cherry-pick 基礎配置 commits (8ca9b1d4f7, 476848b97b, 488b1095af)

Phase 4: 文件 + Tag
   ├── 4a. 修改 AGENTS.md 末尾追加 Mac host rule
   ├── 4b. 修改 .env HERMES_IMAGE tag
   └── 4c. 建立 docs/worksheet-upgrade-hermes-v2026.9.24-20260925.md
       (這個檔案已建立)

Phase 5: Workflow Purge
   └── 5a. find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete
       git checkout my-config-v2026.9.21 -- .github/workflows/

Phase 6: 驗證
   ├── 6a. git status  確認所有變更已 stage
   ├── 6b. git log --oneline  確認線性歷史
   └── 6c. 肉眼檢查 Dockerfile / stage2-hook.sh 結構完整性

Phase 7: Push + CI
   ├── 7a. git push kuniakil my-config-v2026.9.24
   └── 7b. gh workflow run ghcr-publish.yml ...
```

---

## ⚠️ 跨衝突注意事項

1. **Hunk A (Dockerfile apt) 與 Hunk A (stage2 SSH) 有連動**:Dockerfile 安裝 `openssh-server` 才能讓 stage2 的 `sshd` 指令找到 `/usr/sbin/sshd`。任一漏掉會讓 SSH 功能 dead。

2. **`/tmp/.npm-cache` 在 Dockerfile 與 stage2-hook.sh 都出現**:
   - Dockerfile Hunk C:`mkdir -p /tmp/.npm-cache && chmod 1777 /tmp/.npm-cache`(build-time)
   - stage2-hook.sh Hunk B:`mkdir -p /tmp/.npm-cache && chmod 1777 /tmp/.npm-cache`(runtime 補強)
   - 兩處都做是 defensive(若 Dockerfile build cache 失效,stage2 仍會建立)。建議保留。

3. **`entrypoint-ssh.sh` 與 stage2 SSH 區塊互補**:
   - `entrypoint-ssh.sh` 是 Zeabur 部署的 entrypoint shim
   - stage2 SSH 區塊是 normal s6-overlay 流程下的 SSH 設定
   - 兩者獨立,不互相依賴

4. **官方 XDG_RUNTIME_DIR 區塊可能與 SSH 衝突**:XDG_RUNTIME_DIR 區塊檢查 `$actual_hermes_uid`,SSH 區塊不需要這個變數。但 SSH 啟動後,若 user SSH 進來,可能觸發 XDG_RUNTIME_DIR 的 mkdir(若 `XDG_RUNTIME_DIR` env 在 SSH session 中被 export)。建議驗證 `XDG_RUNTIME_DIR` env 是否在 SSH 登入時被 s6 自動帶入(若會,需在 `.bashrc` 中加 `export XDG_RUNTIME_DIR=/tmp/hermes-runtime` 或類似)。

5. **`agent/legacy_cli.py` 在 v2026.9.24 是新檔**:當我們 `git checkout v2026.9.24 -- agent/legacy_cli.py`(或 checkout whole tree)時會自動帶入。我們不需要在 Dockerfile 中額外處理。

---

## ✅ 衝突解決完成驗證清單

- [ ] Dockerfile 包含:`openssh-server`、`rsync`、`locales`、`zh_TW.UTF-8`、`en_US.UTF-8`、`/var/run/sshd`、`ssh-keygen -A`、`locale-gen`、`/etc/default/locale`、`uv sync` 不含 `--extra hindsight`、`/tmp/.npm-cache`、`ENV HOME=/opt/data`、`COPY --chmod=0755 docker/entrypoint-ssh.sh`
- [ ] stage2-hook.sh 包含:SSH server setup、`/run/sshd`、`$HERMES_HOME/.ssh`、`authorized_keys`、`.bashrc` / `.profile` 自動 source、`/usr/sbin/sshd`、`/tmp/.npm-cache`、`rm -rf $HERMES_HOME/.npm`
- [ ] docker/entrypoint-ssh.sh 存在且 13 行
- [ ] docker-compose.yml 採用我們的還原版(若採用)
- [ ] pyproject.toml 為官方版(`hermes-agent = "agent.legacy_cli:main"`,無 `hindsight` extra)
- [ ] .github/workflows/ 只剩 `ghcr-publish.yml`
- [ ] AGENTS.md 末尾有 Mac host rule
- [ ] .env 含 `HERMES_IMAGE=v2026.9.24`
- [ ] `git log --oneline my-config-v2026.9.21..my-config-v2026.9.24` 顯示線性歷史(無 merge commit)