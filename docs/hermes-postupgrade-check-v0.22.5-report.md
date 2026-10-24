# Hermes v0.22.5 升級後全面檢查報告

> 由 **Hermes Agent 自行**執行（session `local-ec6857cb6f0d475c321ac8b109eaa5217226fb0986997f43ef18e71600495aee`，
> 135 則訊息 / 133 次工具呼叫 / 15m 3s），於 2026-10-24 14:26–14:41 CST 在升級後的正式 pod 內執行。
> 提示詞：`docs/hermes-postupgrade-check-v0.22.5-prompt.md`；原始輸出：`docs/hermes-postupgrade-check-v0.22.5-report-raw.txt`。
> 檢查全程唯讀（DB 以 `mode=ro` 開啟，未執行任何 DELETE / prune / optimize-storage / config 修改）。

---

【1. 結論】

整體健康，本次升級成功且未引入阻斷級問題。DB integrity_check 為 ok、schema_version 仍
為 32（未被 migration 推到 33）、sessions 128 / messages 17,791 均不低於升級前基線
（127 / 17,702），config _config_version 仍為 51 且 config.yaml 檔案 mtime 停留在
10-15（升級完全沒有改寫設定檔）。Pod 1/1 Running、RESTARTS=0、啟動於 14:10:26 CST，
無 restart loop。升級後 14:05 之後的日誌中，ERROR/CRITICAL 精確 level 比對為 0 筆，
唯一的 1 筆 Traceback 是本次檢查自己造成的（import yaml 失敗，WARNING 級）。
left-core / catalog 自動安裝完全未觸發。

最大亮點是 npm 漏洞：同一支 npm audit --package-lock-only 從 v0.22.4 的 24 個
（2 critical / 5 high）降到 4 個（0 critical / 2 high / 2 moderate），且容器內的
package-lock.json 與官方 v0.22.5 逐位元組相同（sha256 d439feaa…）——不是我方改的。
同時 hermes doctor 這次報的 npm 數字與手動 audit 完全吻合，v0.22.1 時代那個
「no known vulnerabilities」假陰性已修好。

唯一需要留意的既有設計（非本次升級造成）：upstream 自己的 package.json overrides 把
undici 釘死在 6.29.0 / 7.30.0，恰好就是 advisory 認定的漏洞版本上限，所以
npm audit fix --force 永遠會報「outside the stated dependency range」——這條要等
upstream 自己改 override，不是本地能解的。

【2. 檢查項目表】

檢查項                                    期望值                    實測值                                              判定
────────────────────────────────────────────────────────────────────────────────────────────────────────────────
1. hermes --version                      v0.22.5 / 505335bf         vv0.22.5 (2026.9.24) · upstream 505335bf            ✅
1. upstream 非官方 SHA                   ≠ bf0203a794a              505335bfebd6bdf76ee564ca0a8eb4945109edf0              ✅
1. install-stamp.json                    commit=505335bf…           505335bf… / branch my-config-v0.22.5 / dirty=false      ✅
1. image-provenance.json                 revision=505335bf…         revision 505335bf… / version 0.0.0                     ✅
1. image digest                          sha256:8fb00e46…1660       ghcr.io/kuniakil/hermes-agent@sha256:8fb00e46…1660   ✅
1. deploy spec image                     v0.22.5                    ghcr.io/kuniakil/hermes-agent:v0.22.5                  ✅
2. Pod READY / STATUS                    1/1 Running                1/1 Running                                           ✅
2. RESTARTS                              0                          0                                                     ✅
2. 啟動時間                              ~14:10 CST                 pod start 14:10:26 / container 14:10:27 CST             ✅
2. restart loop 跡象                     無                         無（14:03:51、14:10:26 兩次 SIGTERM 分別為部署與刪pod） ✅
3. PRAGMA integrity_check                ok                          ok                                                     ✅
3. schema_version                        = 32（不得 33）             32（PRAGMA user_version=0，實際值在 schema_version 表）✅
3. sessions                              ≥ 127                      128                                                    ✅
3. messages                              ≥ 17,702                   17,791（檢查期間持續增長）                              ✅
4. session_admissions                    物件存在                    4 列                                                   ✅
4. worker_executions                     物件存在                    0 列                                                   ✅
4. worker_receipts                       物件存在                    0 列                                                   ✅
4. runtime_epoch                         物件存在                    1 列 (epoch=5)                                         ✅
4. sessions.transcript_revision          存在                        存在（column #67）                                     ✅
4. session_turn_leases                   存在                        存在（1 列，本 session 持有）                           ✅
4. session_model_usage                   存在                        存在（141 列）                                         ✅
4. async_delegations                     存在                        存在（1 列）                                           ✅
5. state_meta.fts_storage_version        必須不存在（opt-in）        ABSENT                                                 ✅
5. state_meta.fts_optimize_available     存在                        '1'                                                    ✅
5. messages_fts DDL                      仍為 fts5(content)          CREATE VIRTUAL TABLE messages_fts USING fts5(content) ✅
5. FTS 觸發器完整（附加）                13 triggers                 13（6 個 FTS + 7 個 display/ledger），0 orphan row      ✅
6. _config_version                       = 51（不得 migration）       51；config.yaml mtime 2026-10-15 14:27:35 未被改寫     ✅
6. sessions.auto_prune                   false                      false                                                   ✅
6. terminal.backend                      local                      local                                                   ✅
6. security.allow_lazy_installs          true                       true                                                    ✅
6. toolsets                              ['hermes-cli']             ['hermes-cli']                                          ✅
6. platform_toolsets.cli                 19 項未變動                19 項，與升級前快照逐項相同                              ✅
6. 有無多出/缺少的設定鍵                 無                          config.yaml 67 鍵 == effective 67 鍵，集合完全相同        ✅
7. 升級後 ERROR/CRITICAL（精確 level）    0                          gateway.log 0 / agent.log 0 / errors.log 0              ✅
7. 升級後 Traceback                      0                          1（本次檢查自造的 import yaml 失敗，WARNING 級）         ✅
7. Telegram connected                    connected                   ✓ telegram connected @14:10:54                        ✅
7. getUpdates progressing                 是                          generation 1 confirmed healthy @14:10:53                ✅
7. left-core / catalog 自動安裝           不應觸發                   0 筆（所有日誌 grep left-core / Installing plugin）     ✅
8. openssh-server                        存在                        ii 1:10.0p1-7+deb13u4                                   ✅
8. rsync                                 存在                        ii 3.5.0+ds1-0+deb13u1                                   ✅
8. tini                                  存在                        /usr/bin/tini 存在（s6-overlay shim，非 tini 套件）        ✅
8. locale C.utf8/en_US.utf8/zh_TW.utf8   三者皆存在                 三者皆存在（/etc/locale.gen 已生成）                      ✅
8. hermes 使用者 shell                   /bin/bash                  /bin/bash                                               ✅
8. /usr/local/bin/agent-browser          指向 agent-browser-*       → agent-browser-0.26.0-linux-x64/bin/…（0.26.0 可執行）  ✅
8. extras edge_tts/firecrawl/dingtalk_   全部可 import              7.3.1 / 4.17.0 / OK / OK / OK                          ✅
   stream/lark_oapi/exa_py
8. ffmpeg                                存在                        n9.0.1-11-ge47273f4d9-20260831                            ✅
8. /tmp/.npm-cache 權限                  1777                       1777 (root:root)                                        ✅
8. /root/.npm、/root/.cache owner        hermes:hermes              無法直接驗證（uid 10000 無法進入 0700 的 /root；        ⚠️
                                                                          kubectl exec 對 readonly SA 禁止）                  │
8. HOME 環境變數                         /opt/data                  /opt/data                                                ✅
8. /opt/hermes/docker/entrypoint-ssh.sh  存在                        存在 (755)                                              ✅
9. Debian base                           13 trixie                  Debian GNU/Linux 13 (trixie), DEBIAN_VERSION 13.7        ✅
9. libc                                  2.41                       2.41-12+deb13u4                                         ✅
9. Node.js                               v26.12.1                   v26.12.1                                                 ✅
9. Python                                3.14.x                     3.14.9（venv + pm build 一致）                           ✅
9. sqlite3 版本                          記錄實測                    Hermes runtime 3.53.1；/usr/local/lib 有 3.53.4 供 Debian  ✅
                                                                          python3.13 使用（與 v0.22.1/v0.22.4 基線同為 3.53.1）  │
9. ruamel.yaml C 加速                    可用                        from _ruamel_yaml import CParser → OK                    ✅
10. hermes doctor                        執行並分類                  4 issues（1 setup + 3 npm），已分類於第 3 節             ✅
10. delegation default backend           enabled                     plugin "default" status=enabled (bundled 1.0.0)        ✅
11. npm audit（根 lockfile 真實狀態）    讀實況                     4 vulnerabilities (2 moderate, 2 high)                   ⚠️
11. 根 package-lock.json overrides 欄位  檢查存在與否                 不存在（top-level 與 packages[''] 都無）；             ✅
                                                                          overrides 實際在 package.json（20 條），與官方一致     │

【3. 本次升級引入的問題 vs 既有問題】

【本次升級引入的問題】
無阻斷級問題。唯一「與升級相關但方向是變好」的一項：

  · npm 漏洞由 24 個 → 4 個（2 critical → 0 critical）。容器內 package-lock.json
    sha256 = d439feaa570d5098f5479f2af154c001f48d5c2d95a938977cc235384978e37c，
    與官方 v0.22.5 逐位元組相同（cmp 驗證 IDENTICAL）；package.json 的 20 條
    overrides 也與官方 v0.22.5 完全相同。→ 是 upstream 在 81 PR 內修好的，不是我方
    改的，也不需任何本地 patch。
  · 附帶效益：hermes doctor 這次報的 npm 數字（root 1 high / web 1 high+1 mod /
    ui-tui 1 high+1 mod）與手動 audit 逐項吻合。v0.22.1 時代 doctor 的假陰性
    （容器無 node_modules 卻報 0 漏洞）已消失，doctor 從此可作為可信訊號。

【既有問題（升級前就存在，與 v0.22.5 無關）】
  1. SSH password authentication 開啟（hermes.security_audit 每次開機都報 1 issue）。
  2. skill 'plan' 的 /plan 與核心指令撞名，auto-registration 被略過。
  3. 4 個 auth provider 未登入（Nous Portal / OpenAI Codex / MiniMax OAuth / xAI OAuth），
     加上 7 個 optional tool 缺 key 或缺 system dependency（a2a、browser-cdp、
     computer_use、discord、discord_admin、hermes-yuanbao、image_gen、x_search）。
  4. delegate_task 的 output_schema 驗證失敗（14:07 一次，人為構造）。
  5. npm 的 4 個殘留 advisory 全部由 upstream 自己的 overrides 造成（見第 5 節）。
  6. Hermes runtime 實際載入的 SQLite 是 pm python 內建的 3.53.1，而非 Dockerfile
     為修 WAL-reset bug 而釘的 /usr/local/lib/libsqlite3.so.3.53.4（後者只被 Debian
     python3.13 載入）。3.53.1 ≥ Dockerfile 自我檢查門檻 3.51.3，且與 v0.22.1 /
     v0.22.4 基線相同，屬 upstream 打包結構，非本次造成。

【4. 需要人為決策的事項】

1. 【低優先】undici 的殘留 2 個 high 是否要等 upstream。upstream v0.22.5 的
   package.json overrides 寫死 "undici@^6": "6.29.0"、"undici@^7": "7.30.0"，
   而 advisory 判定漏洞區間正是 6.5.0–6.29.0 與 7.0.0–7.30.0。npm audit fix --force
   想裝 undici@6.29.1，但 override 把它擋在 "outside the stated dependency range"
   之外 → 只要 upstream 不改 override，這條永遠不會自癒。建議沿用既有決策：等
   upstream bump，不要本地 patch lockfile（本地 patch 也撐不過下次 hermes update）。
   實質曝險面：Hermes 的 Node 側僅 dashboard / ui-tui / agent-browser，DoS 型 advisory
   需要能送入畸形 response 才有機會觸發。

2. 【低優先】config.yaml 內同一個 camofox MCP 指向兩個不同 namespace：
   mcp.servers.camofox.url = camofox-mcp.default.svc.cluster.local
   mcp_servers.camofox.url = camofox-mcp.camofox.svc.cluster.local
   兩者皆存在於 effective config。功能上 MCP 目前可用，但同一服務兩份 URL 是
   pre-existing 的不一致，建議統一成一份以免日後其中一份失效時難以判斷。

3. 【可選】/root/.npm 與 /root/.cache 的 owner 驗證需要一個能在容器內取得 root
   檢視權的方式（目前 readonly SA 禁止 pods/exec、容器內 uid 10000 無法進 /root）。
   但實務上 npm_config_cache=/tmp/.npm-cache（1777）才是實際生效的 cache 路徑，
   /root/.npm 在本部署中並未被使用，優先級低。

【5. 本次檢查的侷限】

1. /root/.npm、/root/.cache 的 owner 未能直接驗證。/root 權限 0700 root，而本 pod
   內為 uid 10000；kubectl exec 對 system:serviceaccount:hermes:agent-readonly-sa
   回 Forbidden（無 pods/exec 權限），kubectl --as 亦被 API server 拒絕。改以
   Dockerfile hunk 存在性（RUN mkdir -p /root/.npm /root/.cache && chown -R
   10000:10000）+ stage2-hook 的防禦性重建邏輯作為間接證據，未取得 stat 實測值。

2. 「image digest」欄位取自 kubectl pod containerStatuses.imageID，該值即 index
   digest，與題目提供的 sha256:8fb00e46…1660 完全一致。容器內無 docker socket /
   containerd socket（crictl、ctr、skopeo、crane 均不存在），故無法用 registry 端
   API 做二次交叉驗證。

3. 設定鍵「多出/缺少」的判定，只能與 v0.22.5 的 DEFAULT_CONFIG 及本次 session 的
   effective config 比對（config.yaml 67 鍵 == effective 67 鍵，集合相同）。升級前
   的 config 完整快照不存在於 state_meta（僅存 v0.22.1 時代的 doctor 輸出片段），
   故「升級前有沒有別的鍵」改以 config.yaml 的 mtime（2026-10-15 14:27:35，
   升級完全未改寫）作為主要證據。effective config 與檔案的 4 處差異皆為 runtime
   層現象：secret redaction（headers/record_key → None）、oneshot request 覆寫
   （max_turns 90→60、run_budget_seconds）。

4. 日誌切分基準採 2026-10-24 14:05（題目指定）；14:03–14:05 為部署窗口、14:10:30
   後為重啟後穩態，三段皆已分別統計 ERROR/WARNING/INFO。errors.log 內 15,145 筆中
   有 9,910 筆無時間戳（多為 traceback 內文與續行），已用「回溯至最近時間戳行」
   的方式歸屬，未遺漏。gateway.log 頭兩行同樣無時間戳，落在 2026-04 舊區間。

5. MCP server 的實際連線端點（default 與 camofox 兩個 namespace 哪個被採用）
   未做連線層驗證，僅讀取設定與 effective config。

6. 未執行任何寫入驗證（依邊界要求）：因此「FTS trigger 在寫入後仍正確」只做了
   靜態一致性比對（messages 17,791 == messages_fts 17,791 == messages_fts_trigram
   17,791，orphan 0），未實際新增 message 觸發比對。
————————————————————————————————————————
