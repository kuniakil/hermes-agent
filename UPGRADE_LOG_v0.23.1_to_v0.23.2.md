# Hermes Agent 升級紀錄：v0.23.1 → v0.23.2

- **升級日期**：2026-11-17
- **目標版本**：`v0.23.2`（官方 commit `ae2a81ccc00e9b7c06301523e5bb09608397149c`，2026-11-16 發布）
- **升級前版本**：`v0.23.1`（基於官方 `v0.23.1` = `3b4215785882`）
- **新分支**：`my-config-v0.23.2`（基底 = `upstream-v0.23.2`）
- **Image source SHA**：`df6988b7438456eef6286a57914a6d02f7bbf2f8`（= GHCR run `44042061302` 的 `headSha`，`hermes --version` 顯示 `upstream df6988b7`）
- **GH Actions Runs**：
  - 初版建置：[`44038651029`](https://github.com/kuniakil/hermes-agent/actions/runs/44038651029)（success，10m32s）
  - 補入 `--extra stt-whisper` 重建：[`44042061302`](https://github.com/kuniakil/hermes-agent/actions/runs/44042061302)（success，8m41s）
- **發布映像**：`ghcr.io/kuniakil/hermes-agent:v0.23.2`（multi-arch index）
  - index digest：`sha256:f343ea218b8ea3515f70cd37df4773c5f0bc310f53f5c66e4bb17f103ca782e8`
  - `linux/amd64` → `sha256:833402d6b6db9390311834aa3c93b137a2ef924d3b3f7aacdf4ba9226c8156f6`
  - `linux/arm64` → `sha256:9c135754d254fdd5c55801256f6d45d7f7af86a49223fa4136558a6bd8c0ab55`
- **部署環境**：K3s n100，pod `hermes-agent-c6b4487bf-7mvg4`（`1/1 Running`、`RESTARTS 0`）
- **schema_version**：33 → **33**（無不可逆遷移；僅新增冪等 `_heal_reset_rows_carrying_a_delegate_marker`）
- **config_version**：53 → **53**（不變）
- **FTS_STORAGE_VERSION**：3 → **3**（不變）
- **備份**：`~/backups/hermes-20261117/`（已驗證 `integrity_check = ok`、`sessions = 134`、`messages = 18,239`）；前次備份 `~/backups/hermes-20261110/` 已依指示刪除
- **工作表**：`docs/worksheet-upgrade-hermes-v0.23.2-20261117.md`

---

## 1. 一句話總結

> `v0.23.2` 名義上是 patch，實際涵蓋 **7,918 non-merge commits / 5,211 檔 / 1,989 PRs**（完整 curated notes 延至 `v0.24.0`）。本次 DB `SCHEMA_VERSION`（33）與 `config_version`（53）皆未變更、自訂層移植零衝突；升級後抓出一個 **上游 `v0.23.2` 的 `stt-whisper` Lazy-Install 死鎖迴歸**，已於 `Dockerfile` 補入 `--extra stt-whisper` 重建上線並將 `stt.local.language` 設為 `'zh'`，語音轉錄與 Telegram 往返皆恢復正常。

---

## 2. 關鍵技術調整與問題排除

### 2.1 自訂層移植（零衝突）
- `Dockerfile` 與 `docker/stage2-hook.sh` 的上游異動皆不與我方自訂 hunk 重疊，直接 cherry-pick 成功。
- `AGENTS.md`（Mac 資源限制）與 `.env.example`（`HERMES_IMAGE=ghcr.io/kuniakil/hermes-agent:v0.23.2`）取上游最新版後重做。
- `.github/workflows/` 全部 purge，僅保留 `ghcr-publish.yml`。

### 2.2 `v0.23.2` 上游迴歸：`stt-whisper` Lazy-Install 死鎖與根治
- **症狀**：升級後 Telegram 語音訊息無法轉錄，log 出現：
  ```
  WARNING tools.transcription_tools: STT provider 'local' configured but unavailable (install faster-whisper or set HERMES_LOCAL_STT_COMMAND)
  ```
- **根因**：上游 commit `398867326d`（`fix(voice): requirement checks answer from state, never install`）將 `_try_lazy_install_stt()` 從 `_detect_local_backend()` 移入 `_transcribe_local()`。但 `_transcribe_prepared_audio()` 會先呼叫 `_get_provider()` → `_resolve_explicit_local()` → `_detect_local_backend()`；因映像檔未預裝 `faster-whisper`，`_detect_local_backend()` 回傳 `None`，流程提前以「無可用 STT provider」中止，**永遠進不到 `_transcribe_local()` 觸發 Lazy-Install**。
- **解決方案**：
  1. **線上立即恢復（方案 A）**：於執行中 Pod 以 `hermes` 使用者執行 `_try_lazy_install_stt()` 將 `stt-whisper` 裝入 `/opt/data/installs/` 並重啟 Pod。
  2. **Image 永久內建（方案 B）**：於 `Dockerfile` 的 `pm.build_env` `--extra` 清單補上 `--extra stt-whisper`（commit `df6988b743`），觸發 GHCR 重建 `v0.23.2`（Run `44042061302`）並滾動更新上線。
  3. **中文轉錄設定**：`/opt/data/config.yaml` 中 `stt.local.language` 已設定為 `'zh'`，修正原本語音被辨識/翻譯成英文的問題。

### 2.3 Phase 0 備份技巧（Cloudflare Tunnel 大檔傳輸）
- 直接透過 `kubectl --context n100-cf exec ... tar -cf -` 串流 ~190 MB 未壓縮備份時，容易觸發 Cloudflare websocket `close 1006 unexpected EOF`。改用 `tar -czf -`（gzip 壓縮）即可穩定快速完成備份與還原驗證。

---

## 3. 線上驗證結果

- **Pod / Digest**：`hermes-agent-c6b4487bf-7mvg4`（`1/1 Running`、`RESTARTS 0`），`imageID` 與 GHCR multi-arch index digest `sha256:f343ea218b8ea3515f70cd37df4773c5f0bc310f53f5c66e4bb17f103ca782e8` 一致。
- **版本**：`Hermes Agent vv0.23.2 (2026.9.24) · upstream df6988b7`（Python `3.14.9` / OpenAI SDK `2.54.0`）。
- **資料庫**：`PRAGMA integrity_check = ok`、`schema_version = 33`、`sessions = 134`、`messages = 18,265+`、FTS trigram 正常。
- **內建 STT 實測**：`faster_whisper: 1.2.1`、`av: 18.1.0`、`_detect_local_backend() == 'local'`；Telegram 文字往返與語音轉錄（中文）皆已實測通過。
- **既有上游噪音（維持不修）**：`pnpm: not installed or outdated` 啟動警告、`/v1/skills` HTTP 500。
