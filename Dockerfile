# Buzz agent for the code-server environment: buzz-acp + buzz CLI (from source)
# + Claude Code. Runs headless on cm3588, works in its OWN checkout under
# /workspace, routes Claude through code-server's pii-proxy. Never touches your Mac.
ARG BUZZ_REF=v0.4.22

# Rust 1.95 to match Buzz's rust-toolchain.toml (channel = "1.95.0").
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
# Runtime toolset: parity with the code-server env so agents can do real work —
# shell tooling, python, build tools, ssh git remotes, plus the Chromium/
# Playwright runtime libs + fonts and bubblewrap (Claude Code sandbox) that the
# code-server image adds. Keep the two lists in sync (apps/cm3588/code-server/Dockerfile).
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates libssl3 git tini gosu \
      curl wget jq ripgrep less procps zip unzip rsync openssh-client \
      build-essential python3 python3-pip python3-venv \
      tmux bubblewrap \
      libglib2.0-0 libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 libdbus-1-3 \
      libcups2 libxkbcommon0 libatspi2.0-0 libxcomposite1 libxdamage1 libxfixes3 \
      libxrandr2 libgbm1 libcairo2 libpango-1.0-0 libasound2 \
      fonts-liberation fonts-noto-color-emoji \
      && rm -rf /var/lib/apt/lists/*
# Claude Code + its ACP adapter (what buzz-acp drives over stdio)
RUN npm install -g @agentclientprotocol/claude-agent-acp @anthropic-ai/claude-code
COPY --from=builder /build/target/release/buzz-acp /usr/local/bin/buzz-acp
COPY --from=builder /build/target/release/buzz /usr/local/bin/buzz
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENV BUZZ_ACP_AGENT_COMMAND=claude-agent-acp
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
