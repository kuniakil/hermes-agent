請實際使用 camofox MCP 工具做一次**功能實測**，並產出一份結構化報告：camofox 到底能不能用？有哪些問題？

【背景 — 請先讀，這些是已確認的事實，不要重複查證】
- 你是跑在 Hermes Agent 裡（v0.22.5，K3s n100，namespace=hermes）。
- camofox MCP server 已成功註冊 **49 個工具**，前綴為 `mcp__camofox__`（例：`mcp__camofox__navigate`、`mcp__camofox__snapshot`、`mcp__camofox__screenshot`）。
- MCP 端點：`http://camofox-mcp.camofox.svc.cluster.local:8080/mcp`（camofox namespace，ClusterIP 10.43.250.235）。
- `camofox-mcp` pod：Running，**0 次重啟**。
- `camofox-browser` pod：顯示 **366 次重啟**，但這**不是崩潰** —— 它的 `lastState.terminated.exitCode = 0`、`reason = Completed`、日誌顯示 `idle exit started` / `shutting down signal=IDLE_TIMEOUT`，是「一小時無成功瀏覽就自我回收」的設計行為，K8s 再把它拉起來。**不需要把它當成問題報告。**
- `browserConnected: false` / `sessions: 0` 在閒置時是正常狀態；有工作時才會連上瀏覽器。
- 這些工具**從來沒有被實際呼叫過**（agent 歷史裡只有註冊 log）→ 這是第一次真實端到端實測，請如實記錄第一手的觀察。

【測試矩陣 — 請逐項實際執行，不要只看 schema 就下結論】

階段一：後端狀態
1. `mcp__camofox__server_status` — 後端是否健康、有無 session/tab
2. `mcp__camofox__get_stats` — 統計

階段二：基本瀏覽管線（用 https://example.com 作基準）
3. `mcp__camofox__create_tab` → 記下回傳的 tab 識別資訊
4. `mcp__camofox__navigate` 到 https://example.com
5. `mcp__camofox__snapshot` — **AI 可讀的頁面內容**，請貼出實際內容（確認有 "Example Domain" 字樣）
6. `mcp__camofox__camofox_get_page_html` — 原始 HTML，請回報長度與前 200 字元
7. `mcp__camofox__get_links` — 連結清單
8. `mcp__camofox__camofox_query_selector` — 例如取 `h1` 的文字
9. `mcp__camofox__camofox_evaluate_js` — 例如回傳 `document.title`
10. `mcp__camofox__screenshot` — **是否能取得圖片**？回報成功與否、圖片大小或錯誤

階段三：真實內容站（用同一個 tab 或另開 tab）
11. `mcp__camofox__navigate` 到 https://en.wikipedia.org/wiki/Hermes
12. `mcp__camofox__snapshot` — 內容是否完整（條目首段）
13. `mcp__camofox__extract_structured` — 結構化抽取是否可用
14. `mcp__camofox__web_search` — 搜尋能力是否可用
15. `mcp__camofox__navigate` 到 https://news.ycombinator.com
16. `mcp__camofox__snapshot` — 真實新聞站內容

階段四：session 生命週期
17. `mcp__camofox__list_tabs`
18. `mcp__camofox__close_tab` 關閉你開的 tab
19. `mcp__camofox__list_tabs` — 確認已收乾淨

【邊界 — 嚴格遵守】
- 絕對不要呼叫：`delete_profile`、`save_profile`、`load_profile`、`import_cookies`、`delete_download`、`batch_download`、`camofox_close_session`（會動到既有狀態）、`youtube_transcript`、`extract_resources`、`resolve_blobs`
- 絕對不要修改任何 config、任何檔案、任何 k8s 資源
- 不要用 terminal 去 curl/ping camofox 來「代替」工具測試 —— 測的是 **MCP 工具本身**能不能用
- 每個失敗都要記下**原始錯誤字串**（不要改寫、不要只寫「失敗了」）
- 每個步驟記下**花費時間**（若工具回報則記，沒有就記你的觀察順序）
- 若某個工具呼叫卡住，不要無限重試；換下一項並記錄

【輸出格式】
1. **結論**（3-5 句）：camofox 能不能用？整體可用度？
2. **測試表格**：# | 工具 | 目標/參數 | 結果 | 耗時 | 判定（✅/⚠️/❌）
3. **失敗清單**：每個失敗 → 原始錯誤字串 → 你判斷的失敗類別：
   - `TOOL_CONTRACT`（工具呼叫格式/schema 不符）
   - `BACKEND_NOT_READY`（瀏覽器後端沒起來或沒連上）
   - `NETWORK`（DNS / connection refused / TLS）
   - `SITE_BLOCKED`（403 / CAPTCHA / bot 偵測 — 目標站擋，不是工具壞）
   - `EMPTY_CONTENT`（HTTP 200 但抽不到內容）
   - `TIMEOUT`
   - `OTHER`
4. **已知設計行為 vs 真問題**：分開列（例如 idle timeout 重啟屬於前者）
5. **需要人為決策的事項**（沒有就寫「無」）
6. **本次測試的侷限**
