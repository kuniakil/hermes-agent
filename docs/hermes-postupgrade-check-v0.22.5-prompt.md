請對目前這個 Hermes Agent 部署做「v0.22.5 升級後全面檢查」，並產出一份結構化報告。

【背景】
- 部署環境：K3s n100，namespace=hermes，pod 為當前唯一運行的 hermes-agent pod
- 剛完成官方 v0.22.4 → v0.22.5 升級（81 PR 的正常 patch window）
- Image: ghcr.io/kuniakil/hermes-agent:v0.22.5（index digest sha256:8fb00e4665e888ed3ce199269355cc0d596e1399f52f148c21403b06b0fb1660）
- Image source SHA: 505335bfebd6bdf76ee564ca0a8eb4945109edf0（我方 commit，絕不是官方 bf0203a794a）
- 升級前基線（2026-10-24 13:48 備份時）：sessions=127、messages=17,702、schema_version=32
- 部署時間：2026-10-24 14:07 CST；刪 pod 強制重啟驗證：2026-10-24 14:10 CST
- 備份在 Mac 本機 ~/backups/hermes-20261024/state.db（不在本 pod 內，請勿嘗試讀取）
- 你正在跑在升級後的同一個 pod 裡（這是事實，請自行用工具驗證）

【檢查項目】逐項獨立驗證，每項都給「期望值 / 實測值 / 判定」，務必以實測輸出為準，不要用推理代替實測。

1. 版本與 stamp
   - `hermes --version` 是否顯示 v0.22.5，且 upstream 是 505335bf（不得是官方 bf0203a794a）
   - image digest 是否與上面列的一致（可用 `hermes --version` 與容器內路徑推斷；若無直接查詢方式就說明限制）

2. Pod 健康
   - READY 狀態、RESTARTS 次數、啟動時間（`date -u -d @<epoch>` 或 uptime 推算）
   - 是否有 restart loop 跡象

3. DB 完整性
   - `PRAGMA integrity_check`
   - `schema_version`（必須仍是 32，**不得變 33**）
   - sessions / messages 計數（不得低於 127 / 17,702）

4. Ledger 與 schema 狀態
   - session_admissions / worker_executions / worker_receipts / runtime_epoch 的列數
   - sessions.transcript_revision、session_turn_leases、session_model_usage、async_delegations 這四個物件是否存在

5. FTS
   - state_meta.fts_storage_version 是否仍**不存在**（應維持 opt-in）
   - state_meta.fts_optimize_available 的值
   - messages_fts 的 DDL（是否仍是 fts5(content)，即未被自動重建）

6. Config
   - `_config_version` 是否仍是 51（不得有任何 migration 執行）
   - sessions.auto_prune 是否仍是 false
   - terminal.backend、security.allow_lazy_installs、toolsets、platform_toolsets 是否被升級改動
   - 有無多出或缺少的設定鍵

7. 日誌
   - 升級後（2026-10-24 14:05 之後）的 ERROR / CRITICAL / Traceback 筆數與內容
   - Telegram 是否 connected、`getUpdates` 是否 progressing
   - **left-core 是否被觸發**：不應有任何 catalog 自動安裝（grep left-core / Installing plugin）
   - 日誌錯誤數請依部署時間切分，並用 level 精確比對，不要用 case-insensitive 的 "error" 子字串

8. 自訂層（Dockerfile 8 個 hunk + 我們的補丁）
   - openssh-server / rsync / tini 是否存在
   - locale：C.utf8 / en_US.utf8 / zh_TW.utf8
   - hermes 使用者的 shell 是否為 /bin/bash
   - /usr/local/bin/agent-browser 是否可用（指向 agent-browser-* 目錄）
   - extras：edge_tts / firecrawl / dingtalk_stream / lark_oapi / exa_py 是否都能 import
   - ffmpeg、/tmp/.npm-cache 權限（應為 1777）、/root/.npm 與 /root/.cache 的 owner（應為 hermes:hermes）
   - HOME 環境變數（應為 /opt/data）
   - /opt/hermes/docker/entrypoint-ssh.sh 是否存在

9. 執行環境
   - Debian base 版本（預期 Debian GNU/Linux 13 trixie）與 libc 版本
   - Node.js 版本（預期 v26.12.1）、Python 版本（預期 3.14.x）、sqlite3 版本
   - ruamel.yaml.clib 的 C 加速是否可用（`from _ruamel_yaml import CParser`）

10. 功能健全性
    - `hermes doctor` 的結果，並把問題分成「既有問題」與「本次升級可能引入的問題」兩類
    - `hermes plugins list` 中 delegation 的 default backend 是否 enabled

11. npm 漏洞決策複查
    - 只用 `npm audit --package-lock-only` 讀根 package-lock.json 的實際狀態（**不要**用 hermes doctor 的結論）
    - 檢查根 package-lock.json 的 overrides 欄位是否存在

【邊界 — 嚴格遵守】
- 只做唯讀查詢與報告產出
- 絕對不要：DELETE 任何 session_admissions / worker_* 列、不要 DROP 任何 trigger、不要執行 `hermes sessions optimize-storage`、不要執行任何 prune、不要刪除任何 session、不要修改任何 config、不要跑 docker build、不要跑 pytest、不要改動任何檔案
- DB 一律用唯讀開啟：`sqlite3.connect('file:/opt/data/state.db?mode=ro', uri=True)`
- 若某項無法驗證，明確寫「無法驗證」並說明原因，不要猜測

【輸出格式】
1. 「結論」段：整體健康與否、有無阻斷級問題（3-5 句）
2. 一個表格：檢查項 | 期望值 | 實測值 | 判定（✅ / ⚠️ / ❌）
3. 「本次升級引入的問題」與「既有問題」分開列
4. 「需要人為決策的事項」（若有；沒有就寫「無」）
5. 「本次檢查的侷限」（哪些沒能驗到、為什麼）
