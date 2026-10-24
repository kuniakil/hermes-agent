請實際使用 camofox MCP 工具做一次**功能實測**，並產出結構化報告：從 OpenClaw 這邊，camofox 能不能用？有哪些問題？

【背景 — 已確認的事實，不要重複查證】
- 你是 OpenClaw（2026.10.6）的 agent，透過 Gateway 執行。
- camofox MCP server 已在此環境註冊，端點 `http://camofox-mcp.camofox.svc.cluster.local:8080/mcp`，transport = streamable-http。
- **camofox 是 Hermes 與 OpenClaw 共用的服務**，Hermes 端剛做完一次完整實測（已結束並清乾淨所有 tab，目前 `activeTabCount: 0`、閒置狀態）。你現在是唯一的使用者，可以放心操作。
- `camofox-browser` pod 會約每小時自我回收一次（idle timeout，`exitCode 0`，非崩潰），這是設計行為，**不要當成問題報告**。
- 閒置時 `browserConnected: false` / `activeTabCount: 0` 是正常狀態。

【已知的上游行為（請獨立驗證，不要直接照抄結論）】
Hermes 端實測發現三件事，你這邊請**親自驗證**是否一致：
1. `get_links` 似乎**恆回傳空 href**（上游欄位名對接問題）
2. `navigate` 回傳的 `title` 似乎**永遠是空字串**
3. `extract_structured` 的 schema 契約**未寫在工具描述裡**，需要試錯才能推導出來

【extract_structured 的正確 schema 格式 — 直接用這個，不要再試錯】
```json
{"kind":"object","fields":{"link":{"kind":"url","selector":"a","attr":"href"}}}
```
- 根層 `kind` 只能是 `"object"` 或 `"list"`
- `fields` 下每欄位必須是物件，且 `kind` 只能是 `text` / `html` / `attr` / `url` / `number` 之一
- **不要**用 `schema.properties`、不要用 `type:` 欄位

【測試矩陣 — 逐項實際執行】
階段一：後端
1. camofox MCP 的 server status 工具（看 running / reachable / version / activeTabCount / browserConnected）
2. stats 工具

階段二：基本管線（https://example.com）
3. 建立 tab（create tab）
4. navigate 到 https://example.com
5. snapshot — 貼出實際內容，確認有 "Example Domain"
6. 取原始 HTML — 回報長度與前 200 字元
7. **get_links** — 特別確認 href 是否有值（這是重點驗證項）
8. query selector 取 `p` 的文字（example.com 沒有 h1，勿誤判）
9. evaluate JS 取 `document.title`
10. screenshot — 能否取得圖片？回報成功/失敗與大小

階段三：真實內容站
11. navigate 到 https://en.wikipedia.org/wiki/Hermes → snapshot（應有完整條目）
12. navigate 到 https://news.ycombinator.com → snapshot（應有 30 則新聞）
13. extract_structured（用上面的 schema 格式）— 抽 HN 的連結
14. web search（google）— 能否回傳真實 SERP

階段四：生命週期
15. list tabs
16. close tab（關閉你開的每一個）
17. list tabs — 確認 `[]`

【邊界 — 嚴格遵守】
- 絕對不要呼叫：`delete_profile` / `save_profile` / `load_profile` / `import_cookies` / `delete_download` / `batch_download` / `camofox_close_session`
- 絕對不要修改任何 config、任何檔案、任何 k8s 資源
- 不要用 terminal 的 curl / ping 去「代替」MCP 工具測試 —— 測的是 **MCP 工具本身**
- 每個失敗都記下**原始錯誤字串**，不要改寫
- 若某個工具卡住，不要無限重試；跳過並記錄

【輸出格式】
1. **結論**（3-5 句）：從 OpenClaw 這邊，camofox 能不能用？
2. **測試表格**：# | 工具 | 參數 | 結果 | 耗時 | 判定（✅/⚠️/❌）
3. **三個已知上游行為的獨立驗證結果**：get_links / navigate title / extract_structured schema —— 每項寫「OpenClaw 側觀察到的」與「與 Hermes 側是否一致」
4. **失敗清單**：原始錯誤字串 + 失敗類別（`TOOL_CONTRACT` / `BACKEND_NOT_READY` / `NETWORK` / `SITE_BLOCKED` / `EMPTY_CONTENT` / `TIMEOUT` / `OTHER`）
5. **需要人為決策的事項**
6. **本次測試的侷限**
