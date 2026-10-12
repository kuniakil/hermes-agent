# Hermes Agent 升級工作表:v0.21.6 → v0.21.7

- **目標版本**:`v0.21.7`(commit `00f69310e2`,2026-10-11 發佈)
- **當前版本**:`my-config-v0.21.6`(基於官方 `v0.21.6` = `f27cdbce5a`,HEAD `59577ff5e2`)
- **新分支**:`my-config-v0.21.7`
- **Remote**:`origin` = 官方、`kuniakil` = 個人 fork
- **狀態**:⏸ 規劃階段,**等待使用者 Go-Sign,尚未修改任何程式碼**

---

## 1. 官方 Release Notes 稽核(v0.21.7)

- 性質:Patch release,~204 PRs / 740 commits / 4,156 files(+86.8K −27.0K)。完整 curated notes 延至 v0.22.0。
- **Breaking Changes / Deprecations / Migration:官方未列**(須以 diff 自行判斷,見 §2)。
- **更新通道行為變更(影響 `hermes update`)**:
  - 官方 repo 的 source install 改為追隨 **tagged release**,不再追 `main`;`hermes update --set-channel main` 可切回。
  - **Fork / mirror 仍追 `main`**(我們是容器映像,不使用 `hermes update`,無影響)。
- 其他:resume 後 signed thinking 重放、Bedrock Converse reasoning 修正;更新不再因區域防火牆 403;plugin SDK 新增 `ctx.runAction` / `ctx.pet.say`;Codex 請求改由 core 發出;skills 中途安裝免重建 prompt。
- **Dependency / Runtime Bumps**:
  - `nemo-relay` `>=0.9,<0.10` → `>=0.10,<0.11`(Python ≥3.14 才啟用;我們為 3.14.x ✅)
  - 根 `package.json` 新增 devDeps:`eslint 10.12.0`、`typescript 6.0.3`、`lefthook 2.1.14`;新增 `prepare` script(僅 `.git` 存在時執行 lefthook)
- **Upgrade Caveats**:`pm/` 小幅更新(`--record-selection`、recovery、packages),Dockerfile 的 `python_deps` 新增 `--record-selection`,否則首次 opt-in extra 會讓之後開機丟失已烘焙 extras(與我們的 extras 預裝直接相關,有益)。

## 2. Diff 稽核(`v0.21.6..v0.21.7`)

| # | 變更 | 影響 |
|---|---|---|
| 1 | `Dockerfile` +9/−… 僅一處:`pm.build_env` 加 `--record-selection` 與註解 | 🟡 與我們修改同一個 RUN(我們在尾端追加 `--extra edge-tts ...`);dry-run 顯示 **auto-merge 成功**,需人工確認旗標順序與 `\` 續行 |
| 2 | `docker/`、`docker-compose.yml`、`AGENTS.md`、`.env` 上游無 diff | 🟢 沿用我們版本 |
| 3 | `pyproject.toml` / `uv.lock`:nemo-relay 0.10 | 🟢 無衝突 |
| 4 | `package.json` / `package-lock.json`:上游加 devDeps、我們有 npm audit overrides(`js-yaml 4.3.2`、`undici 7.30.0`、`vitest` 等) | 🟡 dry-run auto-merge,但 lockfile 須人工驗證:上游 `js-yaml 4.3.1` vs 我們 `4.3.2`、overrides 是否仍生效 |
| 5 | `pm/*`(含 `pm/lock.json`、`packages.py`) | 🟢 官方檔,隨版帶入;`agent-browser` 套件版本確認未變動(我們 Dockerfile 有 `ensure("agent-browser")` + symlink) |
| 6 | Workflows:大量新增/修改(tests、stable-release、plugin-catalog-ci…) | 🟢 依 Purge 規則全刪,只保留 `ghcr-publish.yml`;merge dry-run 12+ 個 modify/delete 衝突皆屬此類 |

**衝突風險結論**:僅 workflow modify/delete(以 Purge 解決)+ Dockerfile 一處相鄰修改(auto-merge)+ lockfile 需驗證。**預期低風險。**

## 3. 需攜帶的自定義 commit(`v0.21.6..my-config-v0.21.6`,共 16 個)

策略:**從 `v0.21.7` 建立新分支後,按序 cherry-pick**(保留線性歷史);workflow purge commit 重做。

| Commit | 內容 | 處置 |
|---|---|---|
| `97e144194e` | purge workflows 只留 `ghcr-publish.yml` | 🔁 重做(新 tag 又新增 workflow) |
| `906a8d4101` | restore `docker/entrypoint-ssh.sh` | ✅ cherry-pick |
| `26086778e3` | docker-compose.yml(`HERMES_IMAGE`、TZ) | ✅ cherry-pick |
| `227c6cbe2d` | AGENTS.md Mac 資源限制規則 | ✅ cherry-pick(衝突則附加於檔尾) |
| `a7e8db1d69` `f3d3911ed4` | SSH、locales、extras、permissions 自定義層 | ✅ cherry-pick,重點審視 Dockerfile 合併結果 |
| `4a5d31131a` | bump `HERMES_IMAGE` tag | 🔁 重做 → `v0.21.7` |
| `d1ee4540ac` | bake agent-browser + install-stamp | ✅ cherry-pick,確認與 `--record-selection` 不衝突 |
| `74d07f34e8` | npm audit overrides + lockfile bump | ⚠️ 預期 lockfile 衝突 → 於 `v0.21.7` lockfile 上重新套用 overrides(僅編輯 JSON,不在本機跑 npm 重建),交由 CI 驗證 |
| `59577ff5e2` | hermes user 預設 shell = bash | ✅ cherry-pick |
| 其餘 docs commits | 升級 log / worksheet | ✅ cherry-pick,新增 v0.21.6→v0.21.7 log |

> 註:實際保留的 workflow 為 `ghcr-publish.yml`(Skill 文件寫 `docker-release.yml`,以 repo 實況為準)。

## 4. 執行檢查清單

### Phase 0:前置(唯讀,已完成)
- [x] 讀取官方 release notes 與 breaking change 稽核
- [x] `git fetch origin --tags` 取得 `v0.21.7`(`v2026.9.24` 本機 tag 拒絕覆蓋屬舊問題,可忽略)
- [x] 分析 Dockerfile / pyproject / package.json / pm / workflows 差異
- [x] `git merge-tree` 衝突模擬
- [x] **取得使用者 Go-Sign**

### Phase 1:分支建立
- [x] `git status` 確認工作樹乾淨
- [x] 備份:`git branch backup/my-config-v0.21.6`
- [x] `git checkout -b my-config-v0.21.7 v0.21.7`
- [x] 確認 HEAD tag commit = `00f69310e2` / tree = `71d34bad10`

### Phase 2:Workflow Purge
- [x] `find .github/workflows -type f ! -name 'ghcr-publish.yml' -delete`
- [x] `git checkout my-config-v0.21.6 -- .github/workflows/ghcr-publish.yml`
- [x] 檢查 `ghcr-publish.yml` 是否引用已變動的 Dockerfile build-arg/stage
- [x] commit:`chore(ci): purge official CI workflows; retain only ghcr-publish.yml`

### Phase 3:自定義層移植
- [x] cherry-pick:entrypoint-ssh.sh、docker-compose.yml、AGENTS.md
- [x] cherry-pick:Dockerfile 自定義層(SSH/locales/extras/npm cache/HOME/agent-browser)
- [x] 人工審視 `pm.build_env` RUN:`--sealed --record-selection` + `--extra ... edge-tts firecrawl dingtalk feishu exa` 皆在
- [x] cherry-pick stage2-hook.sh 自定義(SSH 區塊等)與 bash shell fix
- [x] 輕量檢查:`sh -n docker/stage2-hook.sh docker/entrypoint-ssh.sh`、`git diff v0.21.7 -- Dockerfile docker/`

### Phase 4:Lockfile / npm audit
- [x] 於 `v0.21.7` package.json 重新套用 audit overrides(js-yaml 4.3.2、undici 7.30.0、vitest 4.1.11 等)
- [x] 保持 `package-lock.json` 為乾淨上游 v0.21.7 (不在本機執行高負載 npm rebuild，交 CI/Linux runner)
- [x] 確認 `web/`、`ui-tui/`、`agent-browser` lockfile 無衝突

### Phase 5:版本與文件
- [x] bump `HERMES_IMAGE` → `ghcr.io/kuniakil/hermes-agent:v0.21.7`(`.env` / docker-compose)
- [x] 新增 `UPGRADE_LOG_v0.21.6_to_v0.21.7.md`
- [x] 更新本 worksheet 勾選並 commit

### Phase 6:推送與 CI(需再次確認)
- [x] `git push kuniakil my-config-v0.21.7`
- [x] 觸發 `ghcr-publish.yml`(amd64 + arm64, tag_name=`v0.21.7`, platforms=`all`)
- [x] 記錄 GH Actions Run ID: [38260942404](https://github.com/kuniakil/hermes-agent/actions/runs/38260942404)

### Phase 7:部署驗證(K3s)
- [ ] 更新 K8s manifest 映像 tag 為 `v0.21.7`(`~/kubernetes`)
- [ ] 備份 `/opt/data` PVC 快照
- [ ] 啟動後檢查:s6 服務、版本字串(`v0.21.7`)、Config 版本、`agent-browser`、faster-whisper / edge-tts import、SSH 登入、state.db 完整、cron writable、Relay 0.10 plugins
- [ ] 確認 `stage2` dependency refresh 後 extras(aiohttp、matrix 等)仍存在

### Phase 8:收尾
- [ ] 全部勾選、post-mortem(`session-wrapup`)

## 5. 風險摘要

| 風險 | 等級 | 緩解 |
|---|---|---|
| lockfile 與我們 overrides 衝突 | 🟡 | 以 v0.21.7 為底重套 overrides,CI 驗證 |
| Dockerfile `pm.build_env` 相鄰修改 | 🟡 | auto-merge 後人工審視 |
| `nemo-relay` 0.10 行為變化 | 🟢/🟡 | 僅 Py≥3.14,部署後檢查 Relay plugins |
| 官方無 breaking-change 文件 | 🟡 | diff 稽核;v0.22.0 notes 出後補核 |
| 回滾 | 🟢 | 保留 `backup/my-config-v0.21.6` 與 v0.21.6 映像 tag |
