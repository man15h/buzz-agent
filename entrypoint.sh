#!/bin/sh
# Drop to PUID/PGID (default 1000, matching code-server) so files the agent
# writes under /workspace are owned by you, then start buzz-acp.
set -eu

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# Agent HOME (Claude config/cache) kept OUT of /workspace so it never pollutes
# the mounted git checkout. /workspace = the agent's work dir (its checkout).
AGENT_HOME=/home/agent

mkdir -p /workspace "$AGENT_HOME"
chown -R "${PUID}:${PGID}" /workspace 2>/dev/null || true
chown "${PUID}:${PGID}" "$AGENT_HOME" 2>/dev/null || true

# create a matching user if needed
if ! getent passwd agent >/dev/null 2>&1; then
  groupadd -g "${PGID}" agent 2>/dev/null || true
  useradd -u "${PUID}" -g "${PGID}" -M -d "$AGENT_HOME" -s /bin/sh agent 2>/dev/null || true
fi

export HOME="$AGENT_HOME"
cd /workspace
exec gosu "${PUID}:${PGID}" buzz-acp
