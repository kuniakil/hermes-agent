# Hermes Agent 升級工作表:v0.21.7 → v0.22.0

- **目標版本**:`v0.22.0`(commit `e06df9c2ea`,2026-10-13 發佈,"The Threshold Release")
- **當前版本**:`my-config-v0.21.7`(HEAD `ba394bbcf2`,基於官方 `v0.21.7` = `71d34bad10`)
- **新分支**:`my-config-v0.22.0`
- **Remote**:`origin` = 官方、`kuniakil` = 個人 fork
- **發布模型**:`my-config-v0.22.0` 分支為 source of truth,由 `ghcr-publish.yml`(dispatch input `tag_name`)建置 `ghcr.io/kuniakil/hermes-agent:v0.22.0`
- **狀態**:⏸ 規劃階段,**等待使用者 Go-Sign,尚未修改任何程式碼**

---

## 1. 官方 Release Notes 稽核(v0.22.0 — The Threshold Release)

大型 feature/major release(~24,200 commits 自 v0.21.0、~6,080 PR;程式碼瘦身 34%)。官方重點:首次啟動引導、Connectors、本機模型(llama.cpp)、穩定版頻道、簽章桌面套件、統一 `hermes pm`、600-plugin 目錄。

### ⚠️ 官方 Upgrade notes 逐條影響評估(對我們的 Linux/Docker 部署)

| # | 官方公告 | 對我們的影響 | 判定 |
|---|---|---|---|
| 1 | **Python 3.14 為 managed install 的 runtime**(KittenTTS 在 3.14 不可用) | 我們 pm lock 已釘 `python 3.14.7`(`pm/lock.json`),Dockerfile 以 pm 管理 Python;我們不依賴 KittenTTS | 🟢 相容 |
| 2 | **Windows 桌面改 MSIX-only**、需 Win11 22H2+;macOS 預設僅 Apple Silicon | 我們部署於 Linux/N100 K3s 容器,無 Windows/macOS 桌面 | 🟢 無影響 |
| 3 | **每台機器單一 gateway 成為預設**,`hermes update` 會把 per-profile gateway 摺疊成 multiplex | 我們 host 無 `profiles/`(單 profile)、compose `command: gateway run`、容器內不使用 `hermes update`;無 per-profile gateway 可摺疊 | 🟢 無影響 |
| 4 | **閒置/每日計時器不再重置對話**,`session_reset` 的 idle/daily 模式退役(仍設定者僅 warning) | 我們 `data/config.yaml` **未設定** `session_reset` → 無 warning、無功能影響 | 🟢 無影響 |
| 5 | **舊 session 自動清理**,`sessions.auto_prune` 預設改為 on(閒置 90 天開機刪除) | 我們 `data/config.yaml` 已**明確設定 `sessions.auto_prune: false`** → 明確值優先,維持保留全部 | 🟢 已防護(升級後需複驗此鍵仍在) |
| 6 | **記憶供應商搬到 catalog plugin**(Honcho/Supermemory/Hindsight/Mem0/OpenViking/Holographic + Home Assistant/Spotify/Langfuse);ByteRover、RetainDB 仍內建 | 部署 host `data/.hermes/plugins/` **不存在**,未安裝任何 plugin → 遷移為 no-op;repo 內隨官方 v0.22.0 帶入 | 🟢 無影響 |
| 7 | **Plugin 作者**:compat import 層移除、`hermes sync` 移除、tirith scanner 移除;工具改名 `todo`→`todo_list`、`cronjob`→`cronjob_manage`、`process`→`process_manage`(**舊名仍可用**) | 我們無自訂 plugin;舊名相容 | 🟢 無影響 |

### Dependency / Runtime 稽核(機器可讀真相)

- `pm/lock.json`(v0.22.0):`python 3.14.7`、`uv 0.12.3`、`node 26.7.0`、`ffmpeg 9.0.1`、`chromium 1208`、`ripgrep 15.2.0`、`agent-browser 0.26.0`。
- **關鍵**:`Dockerfile` 在 `v0.21.7 → v0.22.0` **完全未變動**(我們以 Dockerfile 內的 pm ensure/symlink + `--record-selection` 動態解析,`agent-browser` 版本兩版皆 0.26.0 → 相容)。
- `--record-selection` 於 v0.22.0 `Dockerfile:284` 仍存在 → 我們自訂 extras 仍會被記錄、重啟後保留(對應官方「baked-in extras return after a restart」)。
- **無** `package.json`/`package-lock.json` 變動(根與 `web`/`ui-tui`/`apps-desktop`/`agent-browser` workspace 皆 unchanged)→ v0.21.7 時的 npm audit overrides 不受影響。
- 無 `requires-python` / schema migration 變更 → **無 DB schema 版本變動**,回滾不需要強制 DB 遷移。

### 結論:官方未列阻擋性 breaking change 影響我們的部署;7 條 upgrade notes 全部 🟢 或已由既有設定防護。

---

## 2. Diff 稽核(`upstream-v0.21.7..upstream-v0.22.0`,756 commits / 1059 files)

| # | 變更 | 影響 |
|---|---|---|
| 1 | `Dockerfile` **上游無 diff** | 🟢 我們現有 custom layer 直接沿用,無需 re-port |
| 2 | `docker-compose.yml`、`docker/`、`AGENTS.md`、`.env` 上游無 diff | 🟢 沿用我們版本 |
| 3 | `pyproject.toml`、`uv.lock` 上游有更新(opposite-shaped pins、移除數個 optional dep flag) | 🟢 無衝突,非我們修改範圍 |
| 4 | 官方 Workflows 大量變更(`stable-release*`、`skills-index-freshness*` 等) | 🟢 依 Purge 規則全刪,只保留 `ghcr-publish.yml` |
| 5 | 其餘 ~1050 檔(agent/、tools/、gateway/、apps/、web/、ui-tui/、plugins/、locales/ 等官方程式碼) | 🟢 官方檔,隨版帶入 |

### 衝突風險結論

- 我們自定義 commit 觸及 65 檔;上游 v0.21.7→v0.22.0 變更 1059 檔;**重疊僅 3 檔**且皆為 `.github/workflows/`(已被 purge 刪除):
  - `skills-index-freshness.yml`、`stable-release-publication.yml`、`stable-release.yml`(三者在我們分支皆為 DELETED)。
- **實質程式碼衝突 = 0**。Dockerfile / docker/ / compose / AGENTS.md 皆零 diff。
- **預期:極低風險,可乾淨 cherry-pick 全部自定義 commit。**

---

## 3. 需攜帶的自定義 commit(`upstream-v0.21.7..my-config-v0.21.7`,共 9 個)

自 `v0.22.0` 建立新分支後,按序 **cherry-pick**(保留線性歷史);workflow purge commit 重做。

| # | commit | 說明 | 預期 |
|---|---|---|---|
| 1 | `028c5aac93` | `chore(ci)`:purge 官方 CI,只留 `ghcr-publish.yml` | 重做(直接在新分支 purge) |
| 2 | `608f50e2d1` | `fix(docker)`:還原 `docker/entrypoint-ssh.sh`(Zeabur 相容) | 乾淨 |
| 3 | `caedf23c36` | `chore`:帶入 `docker-compose.yml`(HERMES_IMAGE + TZ) | 乾淨 |
| 4 | `91ce53104b` | `chore`:重貼 Mac host 資源限制規則到 AGENTS.md | 乾淨 |
| 5 | `dc3ee53fda` | `fix(docker)`:還原 stage2 SSH 設定 + npm cache | 乾淨 |
| 6 | `ca2ff22645` | `feat(docker)`:re-port custom layer(SSH/locale/extras/perms) | **上游 Dockerfile 無變動 → 乾淨** |
| 7 | `032e5eb836` | `chore`:bump HERMES_IMAGE tag 到 v0.21.7 | 改為 v0.22.0(§5) |
| 8 | `721bab60e3` | `docs`:v0.21.7 升級紀錄 + 工作表 | 保留 |
| 9 | `0f361e49f2`、`ba394bbcf2` | `docs`:工作表更新/驗證結果 | 保留 |

> **註**:`ca2ff22645` 因上游 Dockerfile 零 diff,patch 應乾淨套用;若 cherry-pick 報冲突,改用 `git checkout my-config-v0.21.7 -- Dockerfile` 直接沿用我們的 Dockerfile(已驗證僅含 5 處自訂補丁)。

---

## 4. 執行步驟 checklist

### Phase A — 建分支 + Purge + 攜帶自定義
- [ ] A1. `git fetch origin refs/tags/v0.22.0:refs/tags/upstream-v0.22.0 --no-tags`(已完成)
- [ ] A2. `git checkout -b my-config-v0.22.0 upstream-v0.22.0`
- [ ] A3. Purge 官方 workflows,只保留我們的 `ghcr-publish.yml`:
  ```bash
  find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete
  git checkout my-config-v0.21.7 -- .github/workflows/ghcr-publish.yml
  git add .github/workflows && git commit -m "chore(ci): purge official CI workflows; retain only ghcr-publish.yml"
  ```
- [ ] A4. 依序 cherry-pick 自定義 commits #2–#6、#8、#9(跳過 #1 purge、#7 改 tag)
- [ ] A5. 處理 HERMES_IMAGE tag → v0.22.0(§5)
- [ ] A6. 複驗 `git diff upstream-v0.22.0 HEAD` 只含 5 處 Dockerfile 自訂補丁 + workflows/文檔

### Phase B — 本地輕量驗證(不做重測/不本機 build)
- [ ] B1. `git status` 乾淨
- [ ] B2. `Dockerfile` diff 僅自訂層:`git diff upstream-v0.22.0 HEAD -- Dockerfile | head -60`
- [ ] B3. `.github/workflows/` 僅 `ghcr-publish.yml`
- [ ] B4. `git grep 'Custom\|edge-tts\|openssh-server' HEAD -- Dockerfile`(自訂層存在)

### Phase C — 推送 + 建置
- [ ] C1. `git push -u kuniakil my-config-v0.22.0`
- [ ] C2. dispatch 建置(**input 為 `tag_name`**,Hermes 專屬):
  ```bash
  gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent \
    --ref my-config-v0.22.0 -f tag_name=v0.22.0 -f platforms=all
  ```
- [ ] C3. 驗證 run:`gh run list --workflow=ghcr-publish.yml --limit 1 --json databaseId,event,headBranch,headSha`;`event=workflow_dispatch`、`headBranch=my-config-v0.22.0`、`headSha=我方 commit`
- [ ] C4. `gh run watch <run_id>`
- [ ] C5. 確認 image tags 存在:`v0.22.0`、`latest`

### Phase D — 部署 + 驗證
- [ ] D1. 更新 k8s overlay:`~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag` → `v0.22.0`
- [ ] D2. 套用並 rollout
- [ ] D3. **複驗 `sessions.auto_prune: false` 仍生效**(§1 #5)
- [ ] D4. 冒煙測試:gateway 啟動、SSH (port 2222)、locale (`zh_TW.UTF-8`)、edge-tts/ffmpeg、Telegram 訊息

### Phase E — 收尾
- [ ] E1. 全部勾選完成
- [ ] E2. 產出 post-mortem / 升級紀錄
- [ ] E3. 必要時記錄 frozen known-good tag

---

## 5. 專案特定備註(Hermes)

- **Fork remote**:`kuniakil`;**Upstream remote**:`origin`
- **Workflow**:`ghcr-publish.yml`(檔名 `Docker Build, Test, and Publish`,ID 319971247)
- **dispatch input**:**`tag_name`**(Hermes 專屬;**非** `tag`)
- **預設 push 模型**:分支建置,**不需** force-push 版本 tag;重建 = 重 dispatch 覆寫 `<version>` image(設計如此)
- **HERMES_IMAGE**(compose):`v0.21.7` → **`v0.22.0`**
- **k8s overlay**:`~/kubernetes/hermes/overlays/n100/kustomization.yaml` 目前 `newTag: "v0.21.7"` → 需更新
- **Host 保護**:本機**不**跑 pytest / docker build / 全面 typecheck;僅 git diff/status + 單檔語法檢查;編譯與完整測試交由 GitHub Actions

## 6. Go-Sign

- [ ] 使用者確認升級計畫,授權執行 Phase A–E