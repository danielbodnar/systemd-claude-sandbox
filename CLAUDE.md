# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

The `justfile` is the workflow surface; `just` with no arguments lists every recipe.

```sh
just build            # docker compose build (worker + mcp-tunnel images)
just up / down / logs / ps
just up-cloudflared   # adds the profile-gated cloudflared publisher

just install          # cd mcp-tunnel && bun install
just typecheck        # tsc --noEmit in mcp-tunnel
just test             # bun test in mcp-tunnel
just tunnel-dev       # run the tunnel against examples/tunnel.jsonc

just cf-install / cf-typecheck          # backends/cloudflare
just cf-dev / cf-deploy                 # need an authenticated wrangler

just devcontainer-config / -up / -shell # bunx @devcontainers/cli
just deploy / remote-up / remote-status / remote-logs   # SSH to the `bb1` alias
```

Tests: the whole suite is one file, `mcp-tunnel/src/index.test.ts`. Run a single
case with `cd mcp-tunnel && bun test -t "forwards to the upstream endpoint"`.
`backends/cloudflare` has no tests — `cf-typecheck` is its only gate.

Two shell notes. Recipe bodies in the `justfile` are executed by `sh`, so the
`cd mcp-tunnel && bun install` form there is correct and must not be rewritten
into Nushell syntax; the no-`&&` rule applies to commands you run directly.
And per the global supply-chain rule, `socket package shallow npm <pkg>` before
adding a dependency — this repo adds npm packages in three places, the
non-obvious one being the `npm install -g` line in the `dev` stage of
`sandbox/Dockerfile`.

## Architecture

**The contract is a pull-based work queue, not a server.** Anthropic's control
plane holds the queue; nothing here accepts inbound connections from Anthropic.
`ant beta:worker poll` claims sessions using `ANTHROPIC_ENVIRONMENT_KEY`. That
key is the *only* credential that belongs on the worker host — an
`ANTHROPIC_API_KEY` is organization-scoped and agent tool calls can read the
worker's environment. Do not add one to `.env`, `compose.yaml`, or the
Cloudflare worker's vars.

**Two isolation modes share one image.** `sandbox/Dockerfile` builds a
`sandbox` stage (the worker: `/bin/bash` at that exact path, `/workspace` as
WORKDIR and VOLUME, default entrypoint `ant beta:worker run` — all contract
requirements) and a thin `dev` stage on top of it for the devcontainer. The
compose `worker` service overrides the entrypoint to the always-on poller,
sharing one `/workspace` volume across sessions. `sandbox/spawn.sh` is the
alternative: run the poller with `--on-work sandbox/spawn.sh` and every claimed
work item gets a fresh `docker run --rm` container plus its own host output
directory. Untrusted or mutually-isolated sessions want the second mode.

**mcp-tunnel is deliberately thin.** It forwards MCP Streamable HTTP
transparently — any method, streamed bodies both directions, no session or
protocol-revision tracking — so both the 2026-07-28 and 2025-11-25 revisions
pass through unmodified. Publishing is separated from listening: a transport is
an async function returning a stop handle (`src/transport/types.ts`), so making
the listener reachable never touches the proxy. It is Bun with no build step;
config is JSONC validated by Zod at load and typed everywhere after.

**`backends/cloudflare/` is a parallel implementation of the same contract**, not
a deployment target for this stack: sessions become `Sandbox` Durable Object
instances, and in-sandbox MCP servers use the SDK's own cloudflared tunnels
instead of mcp-tunnel. It typechecks; everything needing an authenticated
wrangler is a documented run-later step.

**systemd's role is one unit.** `host/systemd/claude-sandbox.service` brings the
compose stack up at boot and supervises it — restart policy and ordering only.
Resource limits live in `compose.yaml` (`deploy.resources`) and in `spawn.sh`'s
`docker run` flags, because containers run under the container engine's cgroup
tree rather than under the unit that launched the compose client. Don't move
them into the unit.

## Constraints a future change could easily violate

- **ADR 0001 is Proposed, not accepted.** `mcp-tunnel/src/transport/ssh.ts` and
  `wireguard.ts` throw on purpose. Implementing either, removing the
  `--enable-cloudflared` flag, or dropping the `cloudflared` compose profile
  gate all require the decision in `docs/decisions/0001-tunnel-transport.md` to
  be accepted first. These are not bugs to fix.
- **The `dev` compose service is privileged** (docker-in-docker) with NET_ADMIN
  and NET_RAW. It is confined to the `dev` profile so it never starts with the
  sandbox stack. Never copy that service shape to anything executing untrusted
  code.
- **Version pins live in `sandbox/Dockerfile` ARGs** — `ANT_VERSION`,
  `BUN_VERSION`, `NODE_MAJOR`, `GIT_DELTA_VERSION`, `JCODE_VERSION`,
  `OPENCODE_VERSION`, `COPILOT_CLI_VERSION`, `OPENCHAMBER_VERSION`. Bumps are
  deliberate edits; the jcode binary is verified against the release's published
  `SHA256SUMS`.
- **The repository name predates the runtime.** An earlier iteration built an
  mkosi/vmspawn VM image; compose replaced it and the naming survived. The
  stronger-isolation seam is the container runtime (gVisor, Kata, a VM-isolated
  OCI runtime), not a second image pipeline. See `docs/architecture.md`.
- **`.attic/` is gitignored quarantine, not source.** Its `README.md` is a stale
  `bun init` artifact and will mislead a grep.
