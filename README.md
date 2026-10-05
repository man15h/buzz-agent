# buzz-agent

Container image for running a [Buzz](https://github.com/block/buzz) agent
(`buzz-acp` + Claude Code, or `buzz-acp` + Grok Build) headless. The
`Dockerfile` clones `block/buzz` at build time (pinned via `BUZZ_REF`) — this
repo does **not** fork Buzz.

## Build and publish

Images are built only when a change lands on `main`. Pull requests don't
build, and there is no manual trigger. A merge that touches the
`Dockerfile` or `entrypoint.sh` makes `.github/workflows/build.yml` do
three things:

1. Bump the patch version from the highest `vX.Y.Z` tag. The first
   release is `v0.1.0`.
2. Build `linux/amd64` and push `ghcr.io/<owner>/<repo>` as `<version>`,
   `latest`, `sha-<commit>` and the `BUZZ_REF` it was built from.
3. Push the `v<version>` git tag.

The built-in `GITHUB_TOKEN` does the push, so no secret is needed. To build
a different Buzz release, change `ARG BUZZ_REF` in the `Dockerfile`.

**amd64 only.** Grok Build is fetched as an amd64 binary, and an arm64 build
would compile the Buzz Rust workspace under QEMU, which is far too slow. Add
a native arm64 job rather than emulating.

## What each version knob controls

| Knob | Pins |
| --- | --- |
| `ARG BUZZ_REF` | the Rust side — `buzz-acp` and `buzz`, compiled from `block/buzz` |
| `ARG ACP_VERSION` | `@agentclientprotocol/claude-agent-acp`, which decides the accepted `BUZZ_ACP_MODEL` values |
| `ARG GROK_VERSION` + `ARG GROK_SHA256` | Grok Build, the static binary from `https://x.ai/cli/grok-<version>-linux-x86_64`; the installer script is not used because it pins neither |
| nothing | `@anthropic-ai/claude-code` — floats to latest on every build, on purpose |

Bumping `ACP_VERSION` can change agent model behaviour: an unrecognised
`BUZZ_ACP_MODEL` doesn't error, it quietly falls back to a smaller context.
Check the adapter still accepts your default model after a bump.

## Running an agent on xAI instead of Claude

Grok Build speaks [ACP](https://agentclientprotocol.com) natively
(`grok agent stdio`), so `buzz-acp` drives it exactly as it drives the Claude
adapter — nothing in the harness changes, only which binary it starts. Per
agent, in its environment:

| Variable | Value | Why |
| --- | --- | --- |
| `BUZZ_ACP_AGENT_COMMAND` | `grok` | the binary this image installs at `/usr/local/bin/grok` |
| `BUZZ_ACP_AGENT_ARGS` | `--no-auto-update,agent,stdio` | Comma-separated: buzz-acp splits on commas, not spaces, and the space form makes grok exit 2. ACP over stdio; the flag stops the binary replacing itself under `$HOME/.grok/bin` behind the pinned checksum |
| `XAI_API_KEY` | the key | headless auth; without it the agent answers `initialize` and then asks for a browser login it cannot do |
| `BUZZ_ACP_MODEL` | e.g. `grok-4.6` | `buzz-acp models` lists what the agent offers; the Claude default is not a Grok model |

Two things live outside this image. `$HOME/.grok/config.toml` is where the
agent can be pointed at a proxy (`base_url`); whatever manages the agent's
`$HOME` writes it. `--always-approve` is deliberately not in the args
above: whether an agent auto-approves tool calls is the operator's policy,
set per agent, not baked into the image.

Grok Build writes `$HOME/.grok/` on first start (a default `config.toml`,
`agent_id`, session state), so the agent's `$HOME` must be writable.

## Running

The entrypoint drops to `PUID`/`PGID` (default 1000), works in `/workspace`
and keeps the agent's `$HOME` at `/home/agent`, outside the checkout. On first
boot, when `BUZZ_ACP_AGENT_OWNER` is set, it joins each open channel in
`BUZZ_ACP_CHANNELS` and opens one DM to the owner, then leaves a marker in
`/workspace` so that happens once.

After the first build, make the GHCR package **public** so hosts can pull it
without a registry credential. Pin consumers by digest; the workflow run's
job summary prints `ghcr.io/<owner>/<repo>:<version>@sha256:<digest>`.
