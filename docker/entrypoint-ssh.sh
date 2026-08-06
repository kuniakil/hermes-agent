#!/bin/sh
set -e
# Backward-compatible SSH entrypoint for Zeabur and custom deployments.
#
# SSH server setup is handled by stage2-hook.sh (triggered when the
# SSH_PUBLIC_KEY env var is set). Non-PID 1 environments (Zeabur,
# Fly Machines, docker run --init) are handled natively by the official
# entrypoint-dispatch.sh since v2026.8.3.
#
# This script exists solely for backward compatibility with deployments
# that hard-code the entrypoint path (e.g. Zeabur startup commands like
# `sh -c '/opt/hermes/docker/entrypoint-ssh.sh gateway run'`).
exec /opt/hermes/docker/entrypoint-dispatch.sh "$@"
