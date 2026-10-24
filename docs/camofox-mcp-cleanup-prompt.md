請用 camofox MCP 工具做收尾清理，動作要精確，不要做其他事。

1. 呼叫 `mcp__camofox__list_tabs`，列出目前所有 tab（列出 tabId 與 url）。
2. 對**每一個** tab 呼叫 `mcp__camofox__close_tab` 把它關掉。
3. 再呼叫一次 `mcp__camofox__list_tabs` 確認結果是空的 `[]`。
4. 呼叫 `mcp__camofox__server_status` 回報 `activeTabCount`。

【邊界】
- 絕對不要呼叫 `delete_profile` / `save_profile` / `load_profile` / `import_cookies` / `delete_download` / `batch_download` / `camofox_close_session` / `web_search` / `navigate` / `snapshot`
- 不要開任何新 tab、不要 navigate 到任何網址
- 不要修改任何 config 或檔案
- 不要用 terminal 做任何 curl / ping

輸出格式（簡短即可）：
1. 關閉前 list_tabs 的完整內容
2. 每個 tab 的 close_tab 結果
3. 關閉後 list_tabs 的完整內容
4. server_status 的 activeTabCount
5. 一句話總結：是否已清乾淨
