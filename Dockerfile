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
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates libssl3 git tini gosu && rm -rf /var/lib/apt/lists/*
# Claude Code + its ACP adapter (what buzz-acp drives over stdio)
RUN npm install -g @agentclientprotocol/claude-agent-acp @anthropic-ai/claude-code
COPY --from=builder /build/target/release/buzz-acp /usr/local/bin/buzz-acp
COPY --from=builder /build/target/release/buzz /usr/local/bin/buzz
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENV BUZZ_ACP_AGENT_COMMAND=claude-agent-acp \
    BUZZ_ACP_RESPOND_TO=owner-only
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
