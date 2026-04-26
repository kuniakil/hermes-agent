#!/bin/bash
set -e

# Setup SSH public key if provided
if [ -n "\$SSH_PUBLIC_KEY" ]; then
    # Home directory for hermes is /opt/data by default
    HERMES_HOME_DIR=\$(getent passwd hermes | cut -d: -f6)
    SSH_DIR="\$HERMES_HOME_DIR/.ssh"
    
    mkdir -p "\$SSH_DIR"
    echo "\$SSH_PUBLIC_KEY" > "\$SSH_DIR/authorized_keys"
    chmod 700 "\$SSH_DIR"
    chmod 600 "\$SSH_DIR/authorized_keys"
    chown -R hermes:hermes "\$SSH_DIR"
    echo "SSH public key configured for hermes user."
fi

# SSHD runtime directory
mkdir -p /var/run/sshd

# Generate host keys if they don't exist
ssh-keygen -A

# Start sshd in the background
echo "Starting sshd..."
/usr/sbin/sshd

# Hand off to the original entrypoint
exec /opt/hermes/docker/entrypoint.sh "\$@"
