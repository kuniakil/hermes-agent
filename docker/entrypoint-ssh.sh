#!/bin/bash
set -e

# hermes user home is /opt/data (not /home/hermes)
mkdir -p /opt/data/.ssh

# Strip surrounding quotes from SSH_PUBLIC_KEY if present
# (SSH_PUBLIC_KEY="ssh-ed25519 ... mlee-macbook" → ssh-ed25519 ... mlee-macbook)
SSH_KEY_CLEAN=$(echo "$SSH_PUBLIC_KEY" | sed 's/^"//;s/"$//')
echo "$SSH_KEY_CLEAN" > /opt/data/.ssh/authorized_keys
chmod 600 /opt/data/.ssh/authorized_keys
chown -R hermes:hermes /opt/data/.ssh

# Sync config.yaml so TUI finds it at /opt/data/.hermes/config.yaml
# (hermes config path returns /opt/data/.hermes/config.yaml)
cp /opt/data/config.yaml /opt/data/.hermes/config.yaml 2>/dev/null || true

# Change hermes shell from /bin/sh to /bin/bash
usermod -s /bin/bash hermes

# Create .bashrc to auto-source .env for SSH bash sessions
cat > /opt/data/.bashrc <<'EOF'
# Auto-source environment variables for SSH login
if [ -f /opt/data/.env ]; then
    set -a  # auto-export all variables
    . /opt/data/.env
    set +a
    # Unset SSH_PUBLIC_KEY to avoid "bad variable name" errors (has spaces)
    unset SSH_PUBLIC_KEY
fi
# Add hermes to PATH so "hermes --tui" works without full path
export PATH="/opt/hermes/.venv/bin:$PATH"
EOF

# Create .profile for sh login shells
cat > /opt/data/.profile <<'EOF'
# Auto-source environment variables for sh login
if [ -f /opt/data/.env ]; then
    set -a
    . /opt/data/.env
    set +a
    unset SSH_PUBLIC_KEY
fi
# Add hermes to PATH so "hermes --tui" works without full path
export PATH="/opt/hermes/.venv/bin:$PATH"
EOF

# Start SSH daemon
mkdir -p /run/sshd
/usr/sbin/sshd

# Clean up stale files and fix ownership from previous deployments that
# may have bypassed the entrypoint (e.g. Zeabur with direct command).
# Without this, root-owned files in /opt/data cause PermissionError when
# hermes user tries to write logs, sessions, skills, etc.
rm -f /opt/data/gateway.lock /opt/data/*.lock 2>/dev/null || true
chown -R hermes:hermes /opt/data

exec /opt/hermes/docker/entrypoint.sh "$@"
