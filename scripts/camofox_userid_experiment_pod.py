#!/usr/bin/env python3
"""MCP-only part of the userId experiment (kubectl checks are done from the Mac)."""
import json
import sys
import time
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
    body = json.dumps({"jsonrpc": "2.0", "id": _id, "method": "tools/call",
                       "params": {"name": name, "arguments": args}}).encode()
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
            return json.dumps(res, ensure_ascii=False)
    return raw


USER_ID = sys.argv[1] if len(sys.argv) > 1 else "cli-default"
args = {"url": "https://example.com", "sessionKey": "default"}
if USER_ID != "__default__":
    args["userId"] = USER_ID

print(f"[pod] create_tab with userId={USER_ID!r}", flush=True)
r = call("create_tab", args)
print("[pod] create_tab ->", r, flush=True)
tabid = json.loads(r).get("tabId")

print("[pod] sleeping 15s for cookie-syncer sweep ...", flush=True)
time.sleep(15)

print("[pod] list_tabs ->", call("list_tabs", {}), flush=True)
print("[pod] close_tab ->", call("close_tab", {"tabId": tabid}), flush=True)
print("[pod] sleeping 12s ...", flush=True)
time.sleep(12)
print("[pod] final list_tabs ->", call("list_tabs", {}), flush=True)
print("[pod] DONE", flush=True)
