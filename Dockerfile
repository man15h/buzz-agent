# Headless Buzz agent: buzz-acp + buzz CLI (built from source) + Claude Code,
# plus Grok Build for agents that run on xAI. Works in its own checkout under
# /workspace.
ARG BUZZ_REF=desktop-v0.5.22

# Rust 1.95 to match Buzz's rust-toolchain.toml (channel = "1.95.0" at
# desktop-v0.5.22; upstream renamed its tags from v0.5.x to desktop-v0.5.x
# after v0.5.2).
FROM rust:1.95-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential git pkg-config libssl-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
ARG BUZZ_REF
WORKDIR /build
RUN git clone --depth 1 --branch "${BUZZ_REF}" https://github.com/block/buzz .
# buzz-acp = the agent harness; buzz (buzz-cli) = client CLI used at startup to
# self-join open channels / open a DM to the owner (bootstrap in entrypoint.sh).
RUN cargo build --release --locked -p buzz-acp -p buzz-cli --bin buzz-acp --bin buzz \
    && strip target/release/buzz-acp target/release/buzz

FROM node:24-bookworm-slim
# Runtime toolset so agents can do real work: shell tooling, python, build
# tools, ssh git remotes, plus the Chromium/Playwright runtime libs + fonts and
# bubblewrap (Claude Code sandbox). Everything here has a caller in
# entrypoint.sh, buzz-acp, the Claude
# Code binary or Grok Build, or is agent-shell tooling kept on purpose; wget,
# zip and rsync had neither and were dropped.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates libssl3 git tini gosu \
      curl jq ripgrep less procps unzip openssh-client \
      build-essential python3 python3-pip python3-venv \
      tmux bubblewrap \
      libglib2.0-0 libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 libdbus-1-3 \
      libcups2 libxkbcommon0 libatspi2.0-0 libxcomposite1 libxdamage1 libxfixes3 \
      libxrandr2 libgbm1 libcairo2 libpango-1.0-0 libasound2 \
      fonts-liberation fonts-noto-color-emoji \
      && rm -rf /var/lib/apt/lists/*
# Claude Code + its ACP adapter (what buzz-acp drives over stdio).
#
# The adapter is PINNED and Claude Code is not, deliberately. The adapter
# decides which BUZZ_ACP_MODEL strings are accepted — an unrecognised one
# doesn't fail, it silently falls back to a smaller context — so letting it
# float means agent model behaviour can change on a rebuild with nothing in
# the diff to explain it. Bump ACP_VERSION on purpose, and check
# `claude-agent-acp` still accepts your default model afterwards.
# Claude Code floats because we want current.
ARG ACP_VERSION=0.81.0
RUN npm install -g "@agentclientprotocol/claude-agent-acp@${ACP_VERSION}" @anthropic-ai/claude-code
# Two Claude Code binaries ship, so the build log records both: the floating
# global CLI, and the adapter's bundled SDK binary — the one buzz-acp actually
# executes (pinned transitively by ACP_VERSION). The second line is the version
# agents really run; the path is amd64-only, like the build.
RUN claude --version \
    && "$(npm root -g)/@agentclientprotocol/claude-agent-acp/node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude" --version
# Grok Build: xAI's coding agent, which speaks ACP natively over stdio
# (`grok agent stdio`), so buzz-acp drives it the same way it drives the
# Claude adapter — an agent picks it with BUZZ_ACP_AGENT_COMMAND=grok, and
# nothing changes for agents that don't. Fetched as the static binary the
# official installer (x.ai/cli/install.sh) would fetch, without the installer:
# it verifies no checksum and defaults to "latest", and this image pins both.
# The version is one xAI publishes on https://x.ai/cli/stable; the checksum
# was taken from that download. Bump the two together.
#
# Auto-update is the agent's job to refuse, not the image's to hide: the
# binary self-updates into $HOME/.grok/bin unless told not to, so a Grok
# agent's BUZZ_ACP_AGENT_ARGS must carry --no-auto-update (README).
ARG GROK_VERSION=1.0.13
ARG GROK_SHA256=edf79521581bb5e6b95abef848491a6a742e860da3e237ebe86a280d30dce4c1
RUN curl -fsSL --connect-timeout 10 -o /usr/local/bin/grok \
      "https://x.ai/cli/grok-${GROK_VERSION}-linux-x86_64" \
    && echo "${GROK_SHA256}  /usr/local/bin/grok" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/grok \
    && grok --version
COPY --from=builder /build/target/release/buzz-acp /usr/local/bin/buzz-acp
COPY --from=builder /build/target/release/buzz /usr/local/bin/buzz
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENV BUZZ_ACP_AGENT_COMMAND=claude-agent-acp
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
