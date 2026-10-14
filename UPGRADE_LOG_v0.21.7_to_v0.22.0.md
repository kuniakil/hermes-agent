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