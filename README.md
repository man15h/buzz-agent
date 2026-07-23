# buzz-agent

Container image for running a [Buzz](https://github.com/block/buzz) agent
(`buzz-acp` + Claude Code) headless. The `Dockerfile` clones `block/buzz` at
build time (pinned via `BUZZ_REF`) — this repo does **not** fork Buzz.

## Build

GitHub Actions → **Build buzz-agent image** → Run workflow → set `buzz_ref`
(e.g. `v0.4.22`). Native arm64 runner pushes to
`ghcr.io/man15h/buzz-agent:<buzz_ref>` and prints the digest.

Make the resulting GHCR package **public** so hosts can pull it without a secret.
