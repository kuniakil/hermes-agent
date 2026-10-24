#!/usr/bin/env bash
# Hermes v0.22.5 部署後冒煙測試（在 pod 內執行）
# 用法: kubectl exec -n hermes $POD -- bash -s < scripts/smoke-v0.22.5.sh
set -u
FAIL=0
ok()   { echo "  [OK]   $*"; }
bad()  { echo "  [FAIL] $*"; FAIL=1; }

echo "=== 1. 版本 ==="
hermes --version 2>&1 | head -2

echo "=== 2. OS / libc (R3: trixie) ==="
grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
echo -n "  libc: "; ldd --version 2>&1 | head -1

echo "=== 3. Python (R2 相關) ==="
python3 -V
python3 - <<'PY'
try:
    from _ruamel_yaml import CParser
    print("  [OK]   ruamel.yaml.clib CParser 可用")
except Exception as e:
    print("  [FAIL] ruamel CParser:", e)
import sqlite3, sys
print("  sqlite3:", sqlite3.sqlite_version)
PY

echo "=== 4. Node.js (R2: v26.12.1) ==="
node -v 2>&1
npm -v 2>&1

echo "=== 5. locale (自訂補丁 1) ==="
locale -a 2>/dev/null | grep -iE '^(C\.utf8|en_US\.utf8|zh_TW\.utf8)$' | sort
for l in C.utf8 en_US.utf8 zh_TW.utf8; do
  locale -a 2>/dev/null | grep -qix "$l" && ok "locale $l" || bad "locale $l 缺失"
done

echo "=== 6. SSH / rsync / tini (自訂補丁 1,2) ==="
command -v sshd   >/dev/null && ok "sshd present"   || bad "sshd 缺失"
command -v rsync  >/dev/null && ok "rsync present"  || bad "rsync 缺失"
command -v tini   >/dev/null && ok "tini present"   || bad "tini 缺失"
ls /var/run/sshd >/dev/null 2>&1 && ok "/var/run/sshd 存在" || bad "/var/run/sshd 缺失"
ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 && ok "host keys 存在" || bad "host keys 缺失"

echo "=== 7. hermes user shell ==="
getent passwd hermes | grep -q '/bin/bash' && ok "hermes shell = /bin/bash" || bad "hermes shell 不是 /bin/bash"

echo "=== 8. agent-browser symlink (自訂補丁 3) ==="
ls -la /opt/hermes/bin/agent-browser >/dev/null 2>&1 && ok "agent-browser symlink" || \
  { find /opt/hermes -name 'agent-browser*' -maxdepth 3 2>/dev/null | head -3; bad "agent-browser 未找到"; }

echo "=== 9. extras (自訂補丁 4) ==="
python3 - <<'PY'
mods = ["edge_tts", "firecrawl", "dingtalk_stream", "lark_oapi", "exa_py"]
for m in mods:
    try:
        __import__(m); print(f"  [OK]   {m}")
    except Exception as e:
        print(f"  [FAIL] {m}: {e}")
PY

echo "=== 10. ffmpeg / npm cache perms (自訂補丁 5,6) ==="
command -v ffmpeg >/dev/null && ok "ffmpeg present" || bad "ffmpeg 缺失"
stat -c '%a %U:%G %n' /tmp/.npm-cache 2>/dev/null
stat -c '%a %U:%G %n' /root/.npm /root/.cache 2>/dev/null

echo "=== 11. ENV HOME (自訂補丁 7) ==="
echo "  HOME=$HOME"

echo "=== 12. entrypoint-ssh.sh (自訂補丁 8) ==="
ls -la /opt/hermes/docker/entrypoint-ssh.sh 2>/dev/null || find / -maxdepth 4 -name 'entrypoint-ssh.sh' 2>/dev/null | head -2

echo "=== 13. delegation default plugin (D9) ==="
ls -la /opt/hermes/plugins/delegation/default/ 2>/dev/null | head -5

echo "=== 14. gateway state ==="
cat /opt/data/gateway.pid 2>/dev/null | head -1
echo "  HOME=$HOME  runtime=$HERMES_RUNTIME_DIR"

echo
if [ "$FAIL" = "0" ]; then echo "SMOKE RESULT: ALL PASS"; else echo "SMOKE RESULT: HAS FAILURES"; fi
exit $FAIL
