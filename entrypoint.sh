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

# --- one-time bootstrap ---------------------------------------------------
# The relay only makes an agent discover a channel via kind:39002 membership;
# BUZZ_ACP_CHANNELS can't add membership and the desktop can't attach a headless
# agent. So on FIRST boot only (marker persists in /workspace) we, as this agent:
#   - best-effort self-join each configured channel (works for OPEN channels)
#   - open exactly one DM to the owner (always works) so there's a thread to talk
#     in. `dms open` mints a fresh UUID each call, hence the once-only guard.
# buzz reads BUZZ_PRIVATE_KEY / BUZZ_RELAY_URL from the env (already set).
BOOT_MARKER=/workspace/.buzz-bootstrap-done
if [ ! -f "$BOOT_MARKER" ] && [ -n "${BUZZ_ACP_AGENT_OWNER:-}" ] && command -v buzz >/dev/null 2>&1; then
  echo "[bootstrap] first boot: joining channels + opening owner DM"
  if gosu "${PUID}:${PGID}" env HOME="$AGENT_HOME" sh -c '
        set -u
        for ch in $(echo "${BUZZ_ACP_CHANNELS:-}" | tr "," " "); do
          [ -n "$ch" ] && { buzz channels join --channel "$ch" || true; }
        done
        buzz dms open "$BUZZ_ACP_AGENT_OWNER"
      '; then
    gosu "${PUID}:${PGID}" touch "$BOOT_MARKER" 2>/dev/null || true
    echo "[bootstrap] done"
  else
    echo "[bootstrap] owner DM failed (relay not ready?) — will retry next boot"
  fi
fi
# -------------------------------------------------------------------------

cd /workspace
exec gosu "${PUID}:${PGID}" buzz-acp
