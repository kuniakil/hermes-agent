#!/usr/bin/env python3
"""Agent-independent third-party verification of camofox MCP (raw JSON-RPC, no agent involved)."""
import json
import urllib.request

URL = "http://camofox-mcp.camofox.svc.cluster.local:8080/mcp"
HDRS = {
    "Authorization": "Bearer abcdef1234567890abcdef1234567890abcdef12",
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
}
_id = 0


def call(name, args):
    global _id
    _id += 1
    body = json.dumps({
        "jsonrpc": "2.0", "id": _id, "method": "tools/call",
        "params": {"name": name, "arguments": args},
    }).encode()
    req = urllib.request.Request(URL, data=body, headers=HDRS)
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read().decode()
    for line in raw.splitlines():
        if line.startswith("data: "):
            d = json.loads(line[6:])
            res = d.get("result", d)
            if "content" in res:
                for c in res["content"]:
                    if c.get("type") == "text":
                        return c["text"]
                    if c.get("type") == "image":
                        return f"[IMAGE {c.get('mimeType')} {len(c.get('data',''))} b64chars]"
            return json.dumps(res, ensure_ascii=False)
    return raw


def show(label, out, limit=400):
    print(f"\n--- {label} ---")
    print(str(out)[:limit])


print("=" * 70)
print("A. server_status")
show("server_status", call("server_status", {}), 400)

print("=" * 70)
print("B. create_tab (NO userId/sessionKey -> does it default to 'default'?)")
r = call("create_tab", {"url": "https://example.com"})
show("create_tab", r, 400)
tabid = json.loads(r).get("tabId")
print("tabId =", tabid)

print("=" * 70)
print("C. navigate -> is title empty?")
show("navigate", call("navigate", {"tabId": tabid, "url": "https://example.com"}), 300)

print("=" * 70)
print("D. snapshot -> DOES IT CONTAIN 'Example Domain'?  (Hermes said YES, OpenClaw said NO)")
snap = call("snapshot", {"tabId": tabid})
show("snapshot (first 500)", snap, 500)
print(">>> contains 'Example Domain' :", "Example Domain" in snap)
print(">>> contains 'Learn more'     :", "Learn more" in snap)

print("=" * 70)
print("E. get_links -> href empty?")
show("get_links", call("get_links", {"tabId": tabid}), 300)

print("=" * 70)
print("F. query_selector attribute=href -> correct URL?")
show("query_selector a[href]", call("camofox_query_selector", {"tabId": tabid, "selector": "a", "attribute": "href"}), 300)

print("=" * 70)
print("G. extract_structured kind=list + top-level selector + item  (OpenClaw's discovery)")
show("extract_structured list", call("extract_structured", {
    "tabId": tabid,
    "schema": {"kind": "list", "selector": "body", "item": {"kind": "url", "selector": "a", "attr": "href"}},
}), 300)

print("=" * 70)
print("H. screenshot -> does the MCP return an image block?")
shot = call("screenshot", {"tabId": tabid})
show("screenshot", shot, 200)

print("=" * 70)
print("I. list_tabs -> has a 'title' field?")
show("list_tabs", call("list_tabs", {}), 300)

print("=" * 70)
print("J. close_tab + list_tabs cleanup")
show("close_tab", call("close_tab", {"tabId": tabid}), 200)
show("list_tabs after", call("list_tabs", {}), 200)
show("server_status after", call("server_status", {}), 300)
