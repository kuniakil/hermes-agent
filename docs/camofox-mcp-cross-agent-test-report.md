# camofox MCP 跨 Agent 功能實測與問題清單（2026-10-24）

> 三方交叉驗證：**Hermes Agent**（v0.22.5）、**OpenClaw Agent**（2026.10.6）、**第三方 raw JSON-RPC**（不經任何 agent）。
> 觸發原因：v0.22.5 升級後的全面檢查回報「config.yaml 有兩個 camofox MCP 定義」，追查後延伸出這份實測。

---

## 1. 結論

| 問題 | 答案 |
|---|---|
| **camofox 能不能用？** | ✅ **能用，核心能力完整**。瀏覽、a11y 快照、原始 HTML、DOM selector、JavaScript 執行、截圖、結構化抽取、Google SERP 搜尋 —— 全部在 3 個 agent 視角獨立驗證通過 |
| **有沒有問題？** | ⚠️ **有 6 個**，其中 3 個是上游 camofox 的真 bug、2 個是 OpenClaw 側的整合缺陷、1 個是**跨 agent 共用架構的結構性問題**（最嚴重） |
| **兩個 agent 能同時操作嗎？** | ❌ **不建議也不安全** —— 除了使用者要求的「不要同時操作」紀律外，還有一個**技術層的強制中斷機制**（見 §5）會在任一 agent 建立 tab 時無預警地把另一個的 session 整個砍掉 |

---

## 2. 正常可用的能力（19 項測試矩陣實測）

| 工具 | Hermes | OpenClaw | 第三方 raw | 備註 |
|---|---|---|---|---|
| `server_status` | ✅ | ✅ | ✅ | `ok/running/reachable/version 2.4.8` |
| `get_stats` | ✅ | ⚠️ | — | **JSON Schema 把 `tabId` 列為 required**，開 tab 前無法取得全域 stats（與「session statistics」描述不符） |
| `create_tab` | ✅ | ✅ | ✅ | 回 `tabId` + `userId` + `sessionKey`；`autoLoaded:false` → 需顯式 navigate |
| `navigate` | ⚠️ | ⚠️ | ⚠️ | URL 正確，**`title` 恆空字串**（見 §4.2） |
| `snapshot` | ✅ | ✅ | ✅ | Wikipedia 79,912 字元；HN 30 則 + 226 refs |
| `camofox_get_page_html` | ✅ | ✅ | ✅ | example.com 1,974 字元 |
| `camofox_query_selector` | ✅ | ✅ | ✅ | `p` → text/html/tag/attributes；`a`+attribute=href → 正確 URL |
| `camofox_evaluate_js` | ✅ | ✅ | ✅ | `document.title` → "Example Domain"；HN `tr.athing` = 30 |
| `screenshot` | ✅ | ❌ | ✅ | **MCP 端兩邊都回 image/png**；OpenClaw 側圖片遺失（見 §4.4） |
| `extract_structured` | ⚠️ | ✅ | ✅ | 契約未公開（見 §4.3） |
| `web_search` | ✅ | ✅ | — | 真實 Google SERP，未遇 CAPTCHA，geo=台灣/新北市土城區 |
| `list_tabs` | ✅ | ✅ | ✅ | **無 `title` 欄位**（描述宣稱有） |
| `close_tab` | ✅ | ❌ | ✅ | OpenClaw 側那次拿到 `TAB_NOT_FOUND`（tab 已被 idle teardown 收掉） |

**排除的失敗類別**：`NETWORK`（無 DNS/connection refused/TLS 錯誤）、`SITE_BLOCKED`（無 403/CAPTCHA）、`BACKEND_NOT_READY`、`TIMEOUT` 全數排除。

---

## 3. ⚠️ 對 Hermes 報告的一處更正

| 項目 | Hermes 報告 | 第三方 raw 驗證 | 結論 |
|---|---|---|---|
| a11y `snapshot` 是否含 "Example Domain" | 「含 'Example Domain'（位於 `<title>`，非 h1）」 | **❌ 不含** —— snapshot 只有 6 個多語段落 + `link "Learn more" [e1]` / `/url: https://iana.org/help/example-domains`；"Example Domain" 只出現在 **原始 HTML 的 `<title>`** 與 **`document.title`** | **OpenClaw 側的觀察正確，Hermes 報告此點錯誤**。a11y snapshot 取的是可及性樹，不含 `<title>` 文字 |

---

## 4. 真問題清單

### 4.1 🔴 `get_links` 恆回空 href（上游 camofox bug，影響兩個 agent）

| 項目 | 內容 |
|---|---|
| 現象 | 工具回「成功」，但每一筆 `href` 都是空字串 `""`；`text` 欄位正常 |
| 證據 | Hermes 3 站 / OpenClaw 3 站（**92/92 筆**）/ 第三方 raw 1 站 —— 三方一致。例：`[{"text":"Learn more","href":""}]`；Wikipedia 50 筆、HN 41 筆全部空 |
| 根因（已從上游原始碼驗證） | camofox-browser `src/services/tab.ts` 的 `getLinks()` 回傳型別是 `Array<{url: string; text: string}>`，但 camofox-mcp `src/client.ts:702-705` 讀的是 `item.href ?? ""` → **欄位名不匹配，恆為空字串** |
| **危險性** | **靜默錯誤** —— 工具回成功但欄位無效，下游 AI 會誤以為「該頁沒有連結」，比明確報錯更糟 |
| 替代路徑 | ① `camofox_query_selector(selector:"a", attribute:"href")` ✅ 已驗證回 `https://iana.org/help/example-domains`<br>② `camofox_evaluate_js` ✅<br>③ `extract_structured({kind:"url", selector:"a", attr:"href"})` ✅ |
| 修法 | 上游 `camofox-mcp/src/client.ts:702-705` 改讀 `item.url`（一行）。我們的 image 是 `ghcr.io/redf0x1/camofox-mcp` → 需上游發版或自行 fork |

### 4.2 🔴 `navigate` / `list_tabs` 的 `title` 恆空（上游 camofox bug）

| 項目 | 內容 |
|---|---|
| 現象 | `navigate` 回 `{"url":"https://example.com/","title":""}`；`list_tabs` 回的物件**沒有 `title` 欄位**（工具描述宣稱 "with URLs and titles"） |
| 證據 | 三方一致；且 `evaluate_js("document.title")` 在 example.com 回 "Example Domain"、HN 回 "Hacker News" → **頁面本身 title 正常，斷點在 camofox 的回傳欄位** |
| 根因 | camofox-browser `src/routes/core.ts` 的 navigate 路由只回 `{ok: true, url: tabState.page.url()}`，**沒有 `title` 欄位**；camofox-mcp `src/client.ts:350` 讀 `response.title` → `undefined` → `""` |
| 修法 | 需改 camofox-browser 的 navigate 路由，非 MCP 端可單獨修 |

### 4.3 🟡 `extract_structured` 的 schema 契約完全未公開（上游 camofox）

工具描述只有一句 *"Structured extraction schema understood by camofox-browser"*，JSON Schema 只有 `type:object` 無結構定義 → agent 必須靠錯誤訊息試錯。

**踩坑路徑（Hermes 側 5 輪）**：
```
schema.kind must be "object" or "list" at the root
schema.properties is not supported
schema.fields.intro_paragraph.type is not supported
schema.fields.intro_paragraph must be an object
schema.fields.intro_paragraph.kind must be one of text, html, attr, url, or number
schema.fields.first_story.required must be a boolean   ← 傳 boolean 卻被回報不是 boolean（疑似上游型別判斷缺陷）
```

**最終正確契約（OpenClaw 側獨立推導 + 第三方驗證）**：
```jsonc
// 單值
{"kind":"object","fields":{"名稱":{"kind":"text|html|attr|url|number","selector":"相對 root 的選擇器","attr":"屬性名"}},"selector":"root 選擇器（選填）"}

// 陣列 —— kind:"list" 必須用 item（單數物件），不能用 fields
{"kind":"list","selector":"root 選擇器","item":{"kind":"url|text|html|attr|number","selector":"相對 root 的選擇器","attr":"屬性名"}}
```

| 寫法 | 結果 |
|---|---|
| `kind:"object"` + `fields` | ✅ 可用，但 `matchedRoots:1`（只抽第一個 root） |
| `kind:"list"` + `fields` | ❌ `schema.fields is not supported` |
| `kind:"list"` + `item`（物件）+ 頂層 `selector` | ✅ **正確寫法** —— 30 筆全抽出，`matchedRoots:30` |
| `kind:"list"` + `item`（陣列） | ❌ `schema.item must be an object` |

**副作用**：連續失敗會觸發 **Hermes MCP circuit breaker** →
`MCP server 'camofox' rejected the last 3 calls (it is reachable; see the error text those calls returned).` → 暫停 49 秒。等待 55 秒後恢復正常，**後端本身無故障**。

### 4.4 🟡 OpenClaw 側：`screenshot` 圖片在 tool-call 路徑遺失（**不是 camofox 的問題**）

| 證據鏈 | 內容 |
|---|---|
| MCP 端 | ✅ **確定有回圖** —— 第三方 raw JSON-RPC 實測 `[IMAGE image/png 108036 b64chars]`；OpenClaw 側用 raw JSON-RPC + 官方 MCP SDK client 雙路驗證 `type:"image"`、`mimeType:"image/png"`、base64 **230,368** 字元 |
| Hermes 側 | ✅ **正常收到** —— 83,043 bytes PNG 落到 `/opt/data/cache/images/img_dd3abe8aac77.png`，視覺確認正常渲染 |
| OpenClaw 側 | ❌ `{"content":[], "details":{"mcpServer":"camofox","mcpTool":"screenshot"}}` —— **無 `isError`，content 空陣列** |
| 根因（最強假說，未插樁定案） | `@openclaw/ai` `src/transports/anthropic-messages.ts` `convertContentBlocks()` 只在 `profile === "provider" \|\| model.input.includes("image")` 時保留 image block。本次 session 模型 **MiniMax-M2.5 是 text-only**（`input: ["text"]`）→ image block 被整段丟掉 |
| 佐證 | Hermes 用 MiniMax-M3（支援 vision）→ 圖片正常收到 |
| 未定案 | 「M3 + screenshot 是否正常」在 OpenClaw 側**尚未實測**（該 agent 把 session 切到 M3 時顯示 live switch pending，下一 turn 才生效，測試已收尾） |

### 4.5 🟡 OpenClaw 側：`fullPage: true` 被字串化 → MCP `-32602`

```
MCP error -32602: Input validation error: Invalid arguments for tool screenshot:
Invalid input: expected boolean, received string at fullPage
```

`-32602` 是 **Invalid params** → **參數在傳到 server 前就被 OpenClaw 轉成了字串 `"true"`**，不是 camofox 拒收合法 boolean。
→ 這是 OpenClaw tool-call 橋接層的型別處理問題，**會影響所有需要 boolean/數字型別的 MCP 工具**，不只 screenshot。workaround：一律省略 optional boolean。

### 4.6 🟡 `get_stats` 強制要求 `tabId`（上游契約與描述不符）

描述：*"Get session statistics: request counts, active tabs, uptime, performance metrics"*；
JSON Schema 把 `tabId` 列為 **required** → **開 tab 之前無法取得全域 stats**。
實測只能拿到 per-tab 視角：`{"visitedUrls":["https://example.com/"],"toolCalls":8,"refsCount":1,"sessionKey":"default","remote":{...,"toolCalls":6}}`。

---

## 5. 🔴🔴 最嚴重：跨 agent 共用的結構性中斷機制

### 5.1 現象

**任一 agent 建立 camofox tab → camofox-mcp pod 被殺重創 → 另一個 agent 進行中的所有 MCP session 全斷。**

### 5.2 完整因果鏈（實測確認，非推測）

```
① agent 呼叫 create_tab（不帶 userId → MCP 預設 userId = "default"）
        ↓
② camofox-mcp 在 profile store 寫入 _auto_default.json
        ↓
③ camofox-cookie-syncer 的 cleanup_orphaned_profiles() 掃描 /data/profiles
   規則：expected_profiles = 由 /data/cookies/*.json 推導出的 {name}.json + _auto_{name}.json
        protected = {"x-user.json", "xkuni.json"}
        → 任何不在清單內的 profile → os.remove()
        ↓
④ "Deleted orphaned profile: /data/profiles/_auto_default.json"
        ↓
⑤ "Successfully triggered rollout restart of camofox-mcp: HTTP 200"
        ↓
⑥ camofox-mcp pod 被殺 → pod 重建 → 所有進行中的 MCP 連線斷線
```

### 5.3 實測證據（2026-10-24 全部事件）

| 時間 (UTC) | 觸發者 | 孤兒 profile | 結果 |
|---|---|---|---|
| 10:15:10 | **Hermes 實測**（測試矩陣期間） | `_auto_default.json` | rollout restart |
| 10:20:55 | **Hermes 清理回合** | `_auto_default.json` | rollout restart |
| 11:32:39 | **第三方 raw 驗證** | `_auto_default.json` | rollout restart |
| 12:36:43 | **userId=cli-default 實驗** | `_auto_cli-default.json` | rollout restart |

> 第三次是**決定性實驗**：raw 驗證在 11:32:34 建立 tab，**5 秒後**（11:32:39）syncer 就刪掉了 `_auto_default.json` 並觸發 rollout。
> 第四次證明**換 userId 也沒用** —— `cli-default` 一樣被判為孤兒。

### 5.4 目前 cookie dropzone（= expected profiles 的來源）

`/data/services/camofox-data/cookies/`：`2home.json`、`google.json`、`shopee.json`、`x.com.json`、`youtube.json`
→ 對應 expected profiles：`2home.json`/`_auto_2home.json`、`google.json`/`_auto_google.json`、`shopee.json`/`_auto_shopee.json`、`x-user.json`/`_auto_x-user.json`、`youtube.json`/`_auto_youtube.json`，另加 protected 的 `x-user.json`、`xkuni.json`。

**→ 只有這 5 組 userId 是不會觸發 rollout 的**（但每組都帶特定網域的登入 cookies）。

### 5.5 為什麼 OpenClaw 測試期間沒踩到

OpenClaw 的 agent 明確傳了 `userId: "cli-default"` → 理論上應產生 `_auto_cli-default.json` → 應被刪。
但 10:25–11:20Z 期間 syncer **無任何刪除事件**。推測是 camofox-mcp 在 10:20:56 重啟後的 auto-profile 寫入時序/條件差異。
**未來仍可能踩到** → 不能當作安全保證。

### 5.6 影響

- 兩個 agent 的 MCP session 會互相踩，**無預警**、**無錯誤提示**（只會看到工具呼叫失敗 / circuit breaker）
- Hermes 側已觀察到 `MCP server 'camofox' rejected the last 3 calls` 的保護機制，但那**只是症狀不是原因**
- 登入態 session（用 `2home` / `x-user` 等 profile）也會被波及

### 5.7 選項（需決策，本次未動）

| 選項 | 做法 | 影響 |
|---|---|---|
| **A. 加一個對應 cookie 檔** | 在 `/data/services/camofox-data/cookies/` 放一個 `default.json`（可為空 cookies 陣列）→ syncer 會轉成 `default.json` + `_auto_default.json` → 成為 expected → 不再被刪 | 最簡單、不動 camofox 程式；但多一份空 cookie 檔 |
| **B. 改 syncer 的 protected 清單** | 在 `syncer.py` 的 `protected = {"x-user.json", "xkuni.json"}` 加 `_auto_default.json` / `_auto_cli-default.json` | 直接，但 `/app/syncer.py` 來自 ConfigMap → 要改 deployment 的 ConfigMap 並重啟 syncer |
| **C. 改 syncer 不再因刪 profile 而 rollout** | 刪除孤兒 profile 時**不**觸發 rollout restart | 最根本（刪一個孤兒檔本來就不需要重啟 MCP），但改動最大 |
| **D. agent 端使用 expected 清單內的 userId** | 例：`userId:"x-user"` | 零改動，但會帶 X.com 的登入 cookies 進一般網站測試 |
| **E. 維持現狀 + 紀律** | 兩個 agent 嚴格排程、不同時操作；每次操作後確認 `list_tabs` 為空 | 零改動，但「任一 agent 開 tab 就重啟」的事實仍在，跨 agent 協作時仍會中斷 |

> 📌 **我的建議：C**（孤兒清理不該重啟 MCP —— 這是明顯的過度反應），次選 **A**。
> 但這屬於 camofox 部署層（`ghcr.io/redf0x1/*` + `~/kubernetes` 另一組 overlay），**本次未動**。

---

## 6. 流程發現

| 發現 | 內容 |
|---|---|
| **`openclaw agent` 預設 600 秒 timeout** | 本次測試矩陣需 ~55 分鐘 → 第一次執行在 600s 被砍（`status: error`、`error.kind=incomplete_turn`、`durationMs:601846`、`modelFallbackStopReason=agent_run_terminal_timeout`），已用 212 次 tool call 但沒產出報告。必須加 **`--timeout 2400`**。`--help` 有此選項，**不需改 config** |
| Hermes 端同類問題 | `hermes chat --oneshot` 預設 `--max-turns` 會被 50 回合上限截斷（本次 50/50 用盡 → `Iteration budget exhausted`）。需 `--max-turns 50 --run-budget 900` |
| **OpenClaw 的 `close_tab` 沒有正例** | OpenClaw 那次拿到 `TAB_NOT_FOUND`（tab 已被 idle teardown 收掉）。第三方 raw 驗證補上了正例：`close_tab` → `{"success":true,"tabId":"...","autoSaved":true}` → `list_tabs` → `[]` |
| **tab 消失的真正原因** | OpenClaw agent 歸因為「browser pod 每小時 idle 自收」，但**該窗口內 browser pod 根本沒重啟**（366 次重啟，最後一次在 97 分鐘前，log 顯示 `uptimeSeconds: 5701` 連續）→ 實際是 **browser/MCP 層的 session-idle teardown** 收掉了 tab。browser log 的 `health probe: no successful navigation in 2+ minutes`（`timeSinceSuccessMs` 爬過 64 min，最後一次成功導航 ~18:26 = Google SERP 之後）佐證了這點 |
| Hermes agent 的越界 | 用了 terminal `curl` 去 reverse-engineer 上游原始碼（`redf0x1/camofox-mcp` / `camofox-browser` 的 `src/client.ts` 等，約 20 個指令）。只讀未改動任何上游 repo，但報告中對此**揭露不足**（§6 只提「未用 terminal curl/ping camofox 端點」） |
| OpenClaw agent 的越界 | 同樣用 `exec` 讀 `openclaw.json`（取 Bearer）、跑 raw JSON-RPC + 官方 MCP SDK client、比對 `@openclaw/ai` 原始碼；且用 `session_status` 把**該 session 的**模型 override 改成 `minimax/MiniMax-M3`（pending）。已清理：刪除測試 session `agent:main:explicit:camofox-verify-20261024` |

---

## 7. 已知設計行為（**不是**問題）

| 現象 | 判定 |
|---|---|
| `camofox-browser` pod 366+ 次重啟 | **設計行為** —— `lastState.terminated.exitCode = 0`、`reason = Completed`、日誌 `idle exit started` / `shutting down signal=IDLE_TIMEOUT`。「一小時無成功瀏覽就自我回收」，K8s 再拉起 ≈ 24 次/天 |
| 閒置時 `browserConnected:false` / `sessions:0` / `activeTabCount:0` | 正常。本次實測也實證「閒置 → 工作 → 閒置」的循環正常 |
| `create_tab` 回 `autoLoaded:false` | 符合工具描述（需顯式 navigate） |
| Hermes MCP circuit breaker 暫停 49 秒 | **Hermes 端保護機制**，後端未失效；等待 55 秒後恢復正常 |
| MCP 層以 `isError` + `code: INTERNAL_ERROR` 回報錯誤、不暴露 HTTP status code | 上游設計 |

---

## 8. 需要人為決策的事項

| # | 優先 | 事項 | 建議 |
|---|---|---|---|
| 1 | 🔴 高 | **孤兒 profile → rollout restart 的跨 agent 中斷機制**（§5） | 選項 C（syncer 刪孤兒時不 rollout restart）；次選 A（加 `default.json`） |
| 2 | 🔴 高 | **`get_links` 恆空 href**（§4.1） | 上游一行修正；在此之前**在 skill / MEMORY 裡明文標註 `get_links` 不可用**，改走 `query_selector` / `extract_structured` |
| 3 | 🟡 中 | **`extract_structured` schema 未公開**（§4.3） | 短期：把 §4.3 的正確寫法寫進兩邊的 skill / MEMORY；長期：向 camofox 上游回報要求補 JSON Schema |
| 4 | 🟡 中 | **`navigate` / `list_tabs` title 恆空**（§4.2） | 向上游回報（需改 camofox-browser 路由） |
| 5 | 🟡 中 | **OpenClaw screenshot 圖片遺失**（§4.4） | 先用 MiniMax-M3 實測確認是否純 vision 閘門；不要去改 provider 的 `input` 能力宣告（會送出 MiniMax 不接受的 payload）。不解決就轉 upstream issue |
| 6 | 🟡 中 | **OpenClaw boolean 參數被字串化**（§4.5） | 影響所有 boolean/數字型 MCP 工具 → 開 upstream issue；workaround 是省略 optional boolean |
| 7 | 🟢 低 | **`get_stats` 強制 `tabId`**（§4.6） | 向上游回報釐清 |
| 8 | 🟢 低 | `list_tabs` 描述宣稱有 title 實際沒有 | 與第 4 點併報 |

---

## 9. 產出物

| 檔案 | 內容 |
|---|---|
| `docs/camofox-mcp-live-test-report.md` | Hermes 側完整實測報告（原始產出，含一處需更正，見 §3） |
| `docs/camofox-mcp-live-test-report-raw.txt` | Hermes 側原始輸出（28,063 bytes） |
| `docs/camofox-mcp-openclaw-test-report-raw.txt` | OpenClaw 側完整實測報告（原始產出） |
| `docs/camofox-mcp-openclaw-test-report-raw-attempt1-timeout.json` | OpenClaw attempt 1 的 600s timeout JSON |
| `docs/camofox-mcp-live-test-prompt.md` | Hermes 側測試提示詞 |
| `docs/camofox-mcp-openclaw-test-prompt.md` | OpenClaw 側測試提示詞（已預先給出 `extract_structured` 正確 schema，避免重蹈 5 輪試錯） |
| `docs/camofox-mcp-cleanup-prompt.md` | Hermes 側殘留 tab 清理提示詞 |
| `scripts/camofox_mcp_raw_verify.py` | 第三方 raw JSON-RPC 驗證腳本（不經 agent） |
| `scripts/camofox_userid_experiment_pod.py` | userId 對照實驗腳本 |

**測試環境最終狀態**：camofox `list_tabs` = `[]`、`activeTabCount` = 0、profile store 無孤兒殘留、camofox-mcp 0 restarts、OpenClaw 測試 session 已刪除。
