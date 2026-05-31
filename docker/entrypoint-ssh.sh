#!/bin/bash
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"

# --- SSH server setup ---
# Setup SSH for remote access. This runs early because sshd needs
# the hermes user to exist first (before UID/GID remap below).
if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
    echo "[entrypoint-ssh] Setting up SSH server"
    mkdir -p /run/sshd
    mkdir -p "$HERMES_HOME/.ssh"

    # Write authorized_keys from SSH_PUBLIC_KEY env var
    SSH_KEY_CLEAN=$(echo "$SSH_PUBLIC_KEY" | sed 's/^"//;s/"$//')
    echo "$SSH_KEY_CLEAN" > "$HERMES_HOME/.ssh/authorized_keys"
    chmod 600 "$HERMES_HOME/.ssh/authorized_keys"
    chown -R hermes:hermes "$HERMES_HOME/.ssh"

    # Create .bashrc to auto-source .env for SSH sessions
    cat > "$HERMES_HOME/.bashrc" <<'EOF'
# Auto-source environment variables for SSH login
if [ -f /opt/data/.env ]; then
    set -a  # auto-export all variables
    . /opt/data/.env
    set +a
    unset SSH_PUBLIC_KEY
fi
export PATH="/opt/hermes/.venv/bin:$PATH"
EOF
    chown hermes:hermes "$HERMES_HOME/.bashrc"

    # Create .profile for sh login shells
    cat > "$HERMES_HOME/.profile" <<'EOF'
if [ -f /opt/data/.env ]; then
    set -a
    . /opt/data/.env
    set +a
    unset SSH_PUBLIC_KEY
fi
export PATH="/opt/hermes/.venv/bin:$PATH"
EOF
    chown hermes:hermes "$HERMES_HOME/.profile"

    # Start sshd in background
    /usr/sbin/sshd
    echo "[entrypoint-ssh] SSH server started"
fi

# Clean up stale files and fix ownership from previous deployments that
# may have bypassed the entrypoint (e.g. Zeabur with direct command).
# Without this, root-owned files in /opt/data cause PermissionError when
# hermes user tries to write logs, sessions, skills, etc.
rm -f /opt/data/gateway.lock /opt/data/*.lock 2>/dev/null || true
chown -R hermes:hermes "$HERMES_HOME" 2>/dev/null || true

# Make faster-whisper venv site-packages available to Hermes Python
# This avoids rebuilding the Docker image when faster-whisper is installed
# via the lazy_deps installer at /opt/data/venvs/faster-whisper.
if [ -d "/opt/data/venvs/faster-whisper/lib/python3.13/site-packages" ]; then
    export PYTHONPATH="/opt/data/venvs/faster-whisper/lib/python3.13/site-packages:$PYTHONPATH"
fi

# --- Execute official s6-overlay entrypoint ---
# Use /init (s6-overlay) as PID 1, which handles:
# - UID/GID remap
# - Volume chown
# - Config seeding
# - Skills sync
# - Service supervision (main-hermes, dashboard, per-profile gateways)
# - Then exec's main-wrapper.sh to handle the user's CMD
echo "[entrypoint-ssh] Delegating to /init main-wrapper.sh with args: $@"
exec /init /opt/hermes/docker/main-wrapper.sh "$@"