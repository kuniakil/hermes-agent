# Hermes Agent 升級工作表:v0.21.7 → v0.22.0

- **目標版本**:`v0.22.0`(commit `e06df9c2ea`,2026-10-13 發佈,"The Threshold Release")
- **當前版本**:`my-config-v0.21.7`(HEAD `ba394bbcf2`,基於官方 `v0.21.7` = `71d34bad10`)
- **新分支**:`my-config-v0.22.0`
- **Remote**:`origin` = 官方、`kuniakil` = 個人 fork
- **發布模型**:`my-config-v0.22.0` 分支為 source of truth,由 `ghcr-publish.yml`(dispatch input `tag_name`)建置 `ghcr.io/kuniakil/hermes-agent:v0.22.0`
- **狀態**:✅ **已完成升級並部署**(2026-10-14)。GH Actions Run **38537807179** 全部成功;k8s n100 已 rollout 至 `v0.22.0`,冒煙測試全數通過
- **GHCR image digest**:`sha256:d03b3cad0b249783c4d005e3ae948e1a501d8d587eee2ee0c09ebc59d2e378bb`(linux/amd64 + linux/arm64)

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
- [x] A1. `git fetch origin refs/tags/v0.22.0:refs/tags/upstream-v0.22.0 --no-tags`(已完成)
- [x] A2. `git checkout -b my-config-v0.22.0 upstream-v0.22.0`
- [x] A3. Purge 官方 workflows,只保留我們的 `ghcr-publish.yml`:
  ```bash
  find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete
  git checkout my-config-v0.21.7 -- .github/workflows/ghcr-publish.yml
  git add .github/workflows && git commit -m "chore(ci): purge official CI workflows; retain only ghcr-publish.yml"
  ```
- [x] A4. 依序 cherry-pick 自定義 commits #2–#6、#8、#9(跳過 #1 purge、#7 改 tag)
- [x] A5. 處理 HERMES_IMAGE tag → v0.22.0(§5)
- [x] A6. 複驗 `git diff upstream-v0.22.0 HEAD` 只含 5 處 Dockerfile 自訂補丁 + workflows/文檔

### Phase B — 本地輕量驗證(不做重測/不本機 build)
- [x] B1. `git status` 乾淨
- [x] B2. `Dockerfile` diff 僅自訂層:`git diff upstream-v0.22.0 HEAD -- Dockerfile | head -60`
- [x] B3. `.github/workflows/` 僅 `ghcr-publish.yml`
- [x] B4. `git grep 'Custom\|edge-tts\|openssh-server' HEAD -- Dockerfile`(自訂層存在)

### Phase C — 推送 + 建置
- [x] C1. `git push -u kuniakil my-config-v0.22.0`
- [x] C2. dispatch 建置(**input 為 `tag_name`**,Hermes 專屬):
  ```bash
  gh workflow run ghcr-publish.yml --repo kuniakil/hermes-agent \
    --ref my-config-v0.22.0 -f tag_name=v0.22.0 -f platforms=all
  ```
- [x] C3. 驗證 run:`gh run list --workflow=ghcr-publish.yml --limit 1 --json databaseId,event,headBranch,headSha`;`event=workflow_dispatch`、`headBranch=my-config-v0.22.0`、`headSha=我方 commit`
- [x] C4. `gh run watch <run_id>`
- [x] C5. 確認 image tags 存在:`v0.22.0`、`latest`

### Phase D — 部署 + 驗證
- [x] D1. 更新 k8s overlay:`~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag` → `v0.22.0`
- [x] D2. 套用並 rollout
- [x] D3. **複驗 `sessions.auto_prune: false` 仍生效**(§1 #5)
- [x] D4. 冒煙測試:gateway 啟動、SSH (port 2222)、locale (`zh_TW.UTF-8`)、edge-tts/ffmpeg、Telegram 訊息

### Phase E — 收尾
- [x] E1. 全部勾選完成
- [x] E2. 產出 post-mortem / 升級紀錄
- [x] E3. 必要時記錄 frozen known-good tag

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

- [x] 使用者確認升級計畫,授權執行 Phase A–E → 收到「Go」

---

## 7. 實際執行結果(2026-10-14)

### Branch 與建置

| 項目 | 結果 |
|---|---|
| 新分支 | `my-config-v0.22.0`(基於 `upstream-v0.22.0` = `e06df9c2ea`) |
| 自定義 commit | 11 個(purge 重做 1 + cherry-pick 9 + worksheet 1),**9 個 cherry-pick 全部零衝突** |
| diff 面積 | 65 檔 / +654 −12295(53 個官方 workflow 刪除 + 11 個自訂檔) |
| 攜帶檔案校驗 | `Dockerfile`、`docker-compose.yml`、`docker/entrypoint-ssh.sh`、`docker/stage2-hook.sh`、`AGENTS.md`、`ghcr-publish.yml` 與 `my-config-v0.21.7` **blob 雜湊完全相同** |
| 推送 | `git push -u kuniakil my-config-v0.22.0` ✅ |
| GH Actions Run | **38537807179** — `event=workflow_dispatch`、`headBranch=my-config-v0.22.0`、`headSha=c0888ada33`(**與本分支 HEAD 一致,官方碼不可能混入**) |
| Job 結果 | prepare / amd64 / arm64 / merge 全部 **success** |
| Image | `ghcr.io/kuniakil/hermes-agent:v0.22.0` + `latest`(digest `d03b3cad…`) |

### 部署

| 項目 | 結果 |
|---|---|
| k8s overlay | `~/kubernetes/hermes/overlays/n100/kustomization.yaml` `newTag: v0.21.7 → v0.22.0` |
| 驗證 | `kubectl kustomize .` render 出 `ghcr.io/kuniakil/hermes-agent:v0.22.0` ✅ |
| rollout | `kubectl -n hermes rollout status deployment/hermes-agent` → successfully rolled out |
| Pod | `hermes-agent-bd86c9844-vn9fj` 1/1 Running,0 restart |

### 冒煙測試(D3 / D4)

| 檢查 | 結果 |
|---|---|
| Python runtime | `Python 3.14.7` ✅(對應 v0.22.0 `pm/lock.json`) |
| locale | `zh_TW.utf8`、`en_US.utf8`、`C.utf8` ✅ |
| openssh-server / rsync / tini | `/usr/sbin/sshd`、`/usr/bin/rsync`、`/usr/bin/tini` ✅ |
| ffmpeg / ffprobe / rg / agent-browser | `9.0.1` / `9.0.1` / `15.2.0` / `0.26.0` ✅ |
| baked-in extras | `edge_tts` ✅、`dingtalk_stream` ✅、`lark_oapi`(feishu extra)✅ → v0.22.0「extras 重啟後保留」成立 |
| **`sessions.auto_prune: false`** | **仍在** ✅ — 官方 v0.22.0 預設改為 on,但我們的明確值優先,舊 session 不會被刪 |
| `session_reset` | 未設定(計數 0),啟動日誌**無** idle/daily 退役 warning ✅ |
| gateway | `gateway run --replace` 進程存活;日誌顯示 `s6-supervise gateway-default`(v0.22.0 單一 gateway 預設生效)✅ |
| Telegram | `Connected to Telegram (polling mode)` ✅ |
| SSH | `sshd [listener]` 進程存活、port 22 **OPEN**、host keys 3 組、`entrypoint-ssh.sh` 權限 `-rwxr-xr-x` ✅ |
| Service 映射 | `2222 → 22`;Traefik `IngressRouteTCP hermes-ssh-ingress` ✅ |
| 啟動日誌 | 無 `ERROR` / `Traceback`;僅 3 條良性 warning(dingtalk_stream 第三方 SyntaxWarning、Telegram DNS-over-HTTPS 探索、`/plan` skill 命名衝突) |

> 註:容器內無 `ss` / `netstat`,檢查 listening port 需改用 `/opt/hermes/.venv/bin/python` 的 socket connect 或 `ps`。

## 8. 遺留事項

### 8.1 已由使用者處理

- [x] `.env` 的 `HERMES_IMAGE` → `ghcr.io/kuniakil/hermes-agent:v0.22.0`(2026-10-14 使用者手動修改;該檔受 secrets 讀取防護 `**/*.env` 阻擋,agent 無法代改。僅影響本機 `docker compose` 路徑;k8s 走 overlay `newTag`,已完成)

### 8.2 待處理

- [ ] `overlays/mac/kustomization.yaml` 仍停在 `v2026.8.3`(歷史遺留,本次未觸及)。

### 8.3 npm 漏洞:維持不修,但有觸發條件

`hermes doctor` 回報 3 個 workspace 的 npm 漏洞,**v0.22.0 官方未修**(root `overrides` 在 v0.21.7→v0.22.0 位元組完全相同;#133435 / #132924 / #79021 發佈時仍 OPEN)。完整官方出處與實測分析見 `UPGRADE_LOG_v0.21.7_to_v0.22.0.md` **附錄 A**。

**決策:不修。** 理由不是「修了不 persist」(對我們不成立),而是實測**真實暴露面為 0** —— 容器內僅 photon sidecar 一棵真實 runtime npm 樹(2 high / 0 critical),而 photon 未啟用;root / `web` / `ui-tui` 的 node_modules 皆不存在(只帶編譯產物)。

**⚠️ 以下任一成立時必須重新評估:**

- [ ] 啟用 **photon / iMessage** sidecar → 那 2 個 high 變成真實暴露面
- [ ] 啟用 **web dashboard** / **ui-tui**(node 執行而非純靜態產物)
- [ ] 官方關閉 #133435 / #132924 / #79021 → 改用官方修好的 lockfile
- [ ] 上游改 `npm ci --omit=dev` 或把 electron 移出 lockfile → 重新量測暴露面

**下次升級的檢查動作:** ①比對 `overrides` 前後兩版是否變動;②容器內 `find /opt/hermes -name node_modules -type d` 確認實際安裝的樹;③只對**實際存在**的那棵樹跑 `npm audit`(不要只看 doctor 的 lockfile 數字)。