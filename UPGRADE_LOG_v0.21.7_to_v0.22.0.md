# Hermes 升級紀錄:v0.21.7 → v0.22.0(The Threshold Release)

- **日期**:2026-10-14
- **官方基準**:`v0.22.0` = `e06df9c2eae6901f4c88f464e0ae6e753c0428b8`(2026-10-13 發佈)
- **新分支**:`my-config-v0.22.0`(fork `kuniakil`)
- **GH Actions Run**:38537807179(全部 success)
- **Image**:`ghcr.io/kuniakil/hermes-agent:v0.22.0` + `latest`
  - digest `sha256:d03b3cad0b249783c4d005e3ae948e1a501d8d587eee2ee0c09ebc59d2e378bb`(amd64 + arm64)
- **工作表**:`docs/worksheet-upgrade-hermes-v0.22.0-20261014.md`
- **結果**:✅ 升級 + 部署完成,k8s n100 正常運作

---

## 1. 為什麼這次升級特別乾淨

`upstream-v0.21.7 → upstream-v0.22.0` 官方改了 **1059 個檔案**,但與我們自定義補丁的**重疊只有 3 個檔案,且全部是被 purge 刪掉的 workflow**:

| 檔案 | 性質 |
|---|---|
| `skills-index-freshness.yml` | 我們分支為 DELETED |
| `stable-release-publication.yml` | 我們分支為 DELETED |
| `stable-release.yml` | 我們分支為 DELETED |

決定性的一點:**官方 `Dockerfile` 在 v0.21.7 → v0.22.0 之間完全沒有變動**。所以我們的 custom layer(SSH / locale / rsync / `agent-browser` symlink / `edge-tts`+`firecrawl`+`dingtalk`+`feishu`+`exa` extras / 權限目錄)**不需要重新移植**,cherry-pick 直接乾淨套用。

結果:**9 個自定義 commit 零衝突**,最終 `Dockerfile`、`docker-compose.yml`、`docker/entrypoint-ssh.sh`、`docker/stage2-hook.sh`、`AGENTS.md`、`ghcr-publish.yml` 的 blob 雜湊與 `my-config-v0.21.7` **完全相同** —— 也就是說「只有官方底盤往前移動,我們的客製層原封不動」。

## 2. 官方 7 條 Upgrade notes 的實測結論

| # | 官方公告 | 實測結果 |
|---|---|---|
| 1 | Python 3.14 為 managed runtime | 容器實測 `Python 3.14.7`,與 v0.22.0 `pm/lock.json` 一致 ✅ |
| 2 | Windows MSIX-only / macOS Apple Silicon | 部署於 Linux 容器,無影響 ✅ |
| 3 | 單一 gateway 成為預設、per-profile 摺疊 | 單 profile 部署,無可摺疊;日誌顯示 `gateway-default` 單一服務 ✅ |
| 4 | `session_reset` idle/daily 退役 | config 未設定,啟動日誌**無**退役 warning ✅ |
| 5 | `sessions.auto_prune` 預設改 on(90 天清理) | **我們已明確 `auto_prune: false`,升級後複驗仍在 → 舊 session 安全** ✅ |
| 6 | 記憶供應商搬至 catalog plugin | 未安裝任何 plugin,遷移為 no-op ✅ |
| 7 | 工具改名(`todo`→`todo_list` 等) | 舊名相容,無自訂 plugin ✅ |

**無阻擋性 breaking change。** `pyproject.toml` / `uv.lock` 雖有更新,但**無 `requires-python` 或 schema migration 變更** → 不需要 DB 遷移,回滾安全。

## 3. 這次學到的事(下次直接套用)

1. **`--record-selection` 是 baked-in extras 的關鍵開關**。v0.22.0 的 `Dockerfile:284` 仍有它,所以我們追加在 `pm.build_env` 尾端的 `--extra edge-tts …` 會被寫進 `facts.json`,重啟 / `pm gc` 後仍回來。實測 `edge_tts`、`dingtalk_stream`、`lark_oapi` 全部 import 成功。**未來若上游哪個版本拿掉這行,我們的 extras 會在重建後消失 —— 升級時務必檢查這行是否還在。**

2. **上游會改 workflow 檔名**。v0.22.0 官方已不再提供 `ghcr-publish.yml`(它改用 `docker.yml` + `stable-release.yml`)。我們的 workflow 是純自訂的,靠「從 `my-config-v0.21.7` 取回」維持,**不依賴上游該檔存在**,所以這次完全無影響。

3. **容器內沒有 `ss` / `netstat`**。檢查 listening port 會靜默回傳空結果,極易誤判成「服務沒起來」。改用 `/opt/hermes/.venv/bin/python` 的 socket `connect_ex`,或直接看 `ps` 是否有 `[listener]` 進程 —— 這次就因此差點誤判 SSH 掛掉。

4. **`sessions.auto_prune: false` 這種「明確值優先」是護欄,不是巧合**。官方把預設翻成 on(會刪掉 90 天未活動的 session),我們因為在 `data/config.yaml` 明寫了 `false` 而免疫。這個設定要當成**不可遺漏的部署契約**,未來任何涉及 session 的升級都要複驗它。

5. **`.env` 受 secrets 讀取防護阻擋**,agent 無法自行修改 `HERMES_IMAGE`。本次 k8s 部署走 overlay `newTag`(已完成),但**本機 `docker compose` 路徑的 `.env` 仍停在 `v0.21.7`,需人工更新**(見工作表 §8)。

## 4. 部署紀錄

```
kustomize: ~/kubernetes/hermes/overlays/n100/kustomization.yaml  newTag: v0.21.7 → v0.22.0
apply:     kubectl apply -k .  → deployment.apps/hermes-agent configured
rollout:   successfully rolled out
pod:       hermes-agent-bd86c9844-vn9fj  1/1 Running  0 restart
image:     ghcr.io/kuniakil/hermes-agent:v0.22.0
```

冒煙測試全數通過:Python 3.14.7 / zh_TW locale / sshd+rsync+tini / ffmpeg 9.0.1 / rg 15.2.0 / agent-browser 0.26.0 / extras 齊全 / gateway `gateway-default` / **Telegram 已連線 (polling mode)** / port 22 OPEN + Traefik TCP ingress 2222→22。啟動日誌無 ERROR、無 Traceback。

## 5. 回滾方式

```bash
cd ~/kubernetes/hermes/overlays/n100
# newTag 改回 v0.21.7
kubectl apply -k . && kubectl -n hermes rollout status deployment/hermes-agent
```
舊 image `ghcr.io/kuniakil/hermes-agent:v0.21.7` 仍在 registry,可直接回滾。無 schema 遷移,回滾無 DB 風險。

---

## 附錄 A:npm 漏洞在 v0.22.0 仍未修 — 官方說明與我們的實測風險評估

### A.1 結論先講

**維持不修。** 但理由不是「修了也不會 persist」——那句對我們**不成立**(見 A.4)。正確理由是:**這些漏洞基本上不在我們 runtime,實際可利用風險為 0。**

### A.2 官方怎麼說(三個權威來源)

**① 程式碼內建說明** — `hermes_cli/doctor_tools.py:417` `_audit_one` docstring:

> Every row here audits a tree whose versions come from a **COMMITTED lockfile** (`npm ci` … reifies exactly that state on every `hermes update`), so a local `npm audit fix` **never persists** … **The durable remedy in every case is a lockfile bump on `main`**; **the doctor therefore never prescribes a local mutating fix command.**

它用 `check_warn` 而非 `check_fail`,並直接印出 `fix is an upstream lockfile bump — a local manual fix does not persist`。

**② 官方掃描政策** — `.github/workflows/osv-scanner.yml`(本次 purge 掉的那批之一)檔頭:

> This is **detection-only** — OSV-Scanner does NOT open PRs or modify pins. … Runs on a **weekly schedule against main**; deliberately **NOT part of per-PR CI** … `fail-on-vuln` is **disabled** so the job does not block merges on pre-existing vulnerabilities in pinned deps that we may need to patch deliberately.

**③ 仍 OPEN 的官方 issue**(v0.22.0 發佈 2026-10-13 時狀態)

| Issue | 內容 | 狀態 |
|---|---|---|
| [#133435](https://github.com/NousResearch/hermes-agent/issues/133435) | committed package-lock.json pins 18 high npm vulnerabilities — needs upstream lockfile refresh | OPEN(2026-10-05 開) |
| [#132924](https://github.com/NousResearch/hermes-agent/issues/132924) | 7 remaining after npm audit fix | OPEN(2026-10-04 開) |
| [#79021](https://github.com/NousResearch/hermes-agent/issues/79021) | Fix npm dependency vulnerabilities reported by hermes doctor | OPEN(2026-08-05 開) |

#133435 已列出完整修復版本(`undici@6.29.0`、`electron@40.10.6`、`js-yaml@4.3.2`、`vitest@4.1.11`、`yaml@2.9.1`、`dompurify@3.4.16`、`brace-expansion@5.0.12`…),並明說 **No semver-major changes appear to be required** —— 只差一次 main 上的 lockfile refresh。

**根因**(官方 PR #132601 自述):「Every one traces to a version pinned in the **root `overrides` block**, so a local `npm audit fix` cannot resolve them」。

### A.3 為何 v0.22.0 沒修(已實測比對)

- **root `package.json` 的 `overrides` block 在 v0.21.7 → v0.22.0 之間位元組完全相同**,官方這版一個 pin 都沒調。
- 三個 issue 在發佈當日都還開著。
- 官方 osv-scanner 是 weekly 掃 main、findings 不 block merge → 沒有修復截止日。

所以「v0.22.0 才會全面刷新 lockfile」的預期**沒有發生**。這不是我們漏做,是上游主動沒做。

### A.4 我們的實測:暴露面接近於零

doctor 報 3 個 workspace,但那是 **lockfile 宣告**的,不是實際安裝的。全盤掃描容器:

| 樹 | lockfile 宣告 | runtime 實際 |
|---|---|---|
| root `/opt/hermes/node_modules` | electron、vitest、undici、axios…(37) | **只有 `typescript`** |
| `web` | 7 | **不存在**(只帶編譯產物) |
| `ui-tui` | 5 | **不存在**(只帶編譯產物) |
| `agent-browser` | 3 | 獨立 binary,**零 npm 依賴** |
| photon sidecar | — | **70 packages(`spectrum-ts`)** ← 唯一真實 runtime npm 樹 |

全盤 `find` 確認容器內僅 3 個 `node_modules`:`node`/`npm` 自身、photon sidecar、`/opt/hermes/node_modules`。`bot_desktop` 為純 Python + Xvnc,無 electron。原因是 Dockerfile 只 COPY **編譯後產物**(`/opt/products/tui`、`/opt/products/web`),electron / vitest / electron-builder 這類 desktop 與測試工具**未進成品映像**。

**真實暴露面**:

```
photon sidecar(唯一 runtime npm 樹):  0 critical,  2 high
  ├─ @grpc/grpc-js   1.14.0–1.14.4
  └─ undici          7.0.0–7.29.0
```

而 **photon 我們未啟用**(config 提及 0 次、相關進程 0 個)→ **實際可利用風險 = 0**。

### A.5 為什麼「官方說不能 persist」對我們不成立

官方描述的是 `hermes update` 路徑會 `npm ci` 從 committed lockfile 重新還原。**我們的部署不使用 `hermes update`** —— 我們是從 git branch 用 `npm ci` build,lockfile bump 在我們的分支上**會 persist**,且下次升級可 cherry-pick 延續(SOP 亦如此要求)。

所以正確表述是:**不是「修不了」,而是「修不到有價值的地方」**。為了讓 `hermes doctor` 警告消失而改 lockfile,是為了過掃描而過掃描,反而增加每次升級的衝突面。

### A.6 ⚠️ 決策觸發條件(下次升級務必帶著)

維持「不修」的前提是 **runtime 暴露面為 0**。以下任一情況成立時,**必須重新評估並改用 root `overrides` 蓋掉**(官方 PR #132601 的做法):

- [ ] 啟用 **photon / iMessage** sidecar → 那 2 個 high(`@grpc/grpc-js`、`undici`)變成真實暴露面
- [ ] 啟用 **web dashboard**(`web_dist` 開始以 node 執行伺服器端而非純靜態產物)
- [ ] 啟用 **ui-tui** 的 runtime JS bundle 依賴
- [ ] 官方關閉 #133435 / #132924 / #79021 → 改用官方修好的 lockfile,而非自行覆寫
- [ ] 上游改用 `npm ci --omit=dev` 或把 electron 移出 lockfile → doctor 數字驟降,可重新量測真實暴露面

**每次升級的檢查動作**:
1. 比對 root `package.json` `overrides` 在前後兩版是否變動(本次:**完全相同**,官方未修)
2. 在容器內跑一次 `find /opt/hermes -name node_modules -type d`,確認實際安裝的樹(不要只看 `npm audit` 的 lockfile 數字)
3. 對**實際存在**的那棵樹跑 `npm audit` 才是有意義的暴露面