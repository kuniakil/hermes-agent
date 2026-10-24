#!/usr/bin/env python3
"""Experiment: does an explicit non-default userId avoid the orphan-profile rollout restart?"""
import json
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


import subprocess


def profiles():
    out = subprocess.check_output([
        "kubectl", "exec", "-n", "camofox",
        "camofox-mcp-546b9d6d65-8ftr8", "--", "ls", "-1",
        "/home/camofox/.camofox-mcp/profiles/",
    ]).decode()
    return sorted(x.strip() for x in out.splitlines() if x.strip())


def pod_created():
    return subprocess.check_output([
        "kubectl", "get", "pod", "-n", "camofox",
        "-l", "app=camofox-mcp", "-o", "jsonpath={.items[0].metadata.creationTimestamp}",
    ]).decode().strip()


def syncer_tail(n=6):
    out = subprocess.check_output([
        "kubectl", "logs", "-n", "camofox", "camofox-cookie-syncer-76749db66f-6h9zw",
        "--tail", str(n * 20),
    ]).decode().splitlines()
    return [l for l in out if "orphan" in l or "rollout" in l][-n:]


print("=" * 72)
print("EXPERIMENT: explicit userId that is NOT 'default'")
print("=" * 72)
print("pod created before :", pod_created())
print("profiles before    :", profiles())

r = call("create_tab", {"url": "https://example.com", "userId": "cli-default", "sessionKey": "default"})
print("\ncreate_tab ->", r)
tabid = json.loads(r).get("tabId")

print("\n... waiting 12s for the cookie-syncer sweep ...")
time.sleep(12)

print("profiles after     :", profiles())
print("pod created after  :", pod_created())
print("syncer events     :", syncer_tail(4))

# cleanup regardless
print("\ncleanup ->", call("close_tab", {"tabId": tabid}))
time.sleep(10)
print("profiles final    :", profiles())
print("pod created final :", pod_created())
print("syncer final      :", syncer_tail(4))
