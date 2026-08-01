# systemd-claude-sandbox

A repeatable, self-hosted code-execution sandbox for Claude, built as a docker compose stack and supervised by systemd on the bb1 server. The stack implements Anthropic's self-hosted sandbox contract for Claude Managed Agents, in which Anthropic enqueues sessions and a worker on your host polls the queue, claims work, and executes tool calls locally. A companion component, `mcp-tunnel`, exposes MCP servers running inside the sandbox network to remote clients such as Claude Desktop and claude.ai.

## The contract this implements

The authoritative reference is the Managed Agents self-hosted sandboxes guide (platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes). The essentials the stack is built around:

The `self_hosted` environment is a work queue, not a push API. The `ant` CLI worker (`ant beta:worker poll`) claims sessions using an environment key (`ANTHROPIC_ENVIRONMENT_KEY`), which is the only credential that belongs on the worker host. The organization API key must stay off this host, because agent tool calls can read the worker's environment.

The sandbox itself must be a Linux root filesystem with `/bin/bash` at that exact path and `/workspace` as the working directory for tool execution and skill downloads. The upstream guide's recommended isolation pattern is a container image with `ant` installed and `ant beta:worker run` as the entrypoint, spawned once per claimed session. `sandbox/Dockerfile` follows that pattern verbatim and adds Bun, Python, and Git as session runtimes.

MCP servers that should stay private are not exposed to Anthropic's MCP connector at all. Either the worker wraps them as custom tools (no inbound connectivity required), or, for interactive clients like Claude Desktop, `mcp-tunnel` publishes their Streamable HTTP endpoints outbound through a pluggable transport.

## Architecture

```
Anthropic control plane                Claude Desktop / claude.ai
        |  (worker polls out)                  |  (transport: pluggable)
        v                                      v
+---------------------- bb1: claude-sandbox.service ---------------------+
|  docker compose stack                                                  |
|                                                                        |
|   worker (ant beta:worker poll)      mcp-tunnel (Bun, :8787)           |
|     /workspace volume        <-----    routes /mcp/<name> to           |
|     bash, bun, python, git            MCP servers on the sandbox net   |
|                                                                        |
|   [cloudflared]  profile-gated publisher, decision pending             |
+------------------------------------------------------------------------+
```

`compose.yaml` is the repeatable unit. The `worker` service runs the always-on poller. For stronger isolation, `sandbox/spawn.sh` implements the upstream spawn-per-session pattern: the poller runs on the host with `--on-work`, and every claimed session gets a fresh `docker run --rm` container and its own output directory.

systemd's role is deliberately small. `host/systemd/claude-sandbox.service` brings the compose stack up at boot and supervises it. Container resource bounds live in `compose.yaml`, because containers run under the container engine's cgroup tree rather than under the unit that launched the compose client.

`mcp-tunnel` is a single Bun process with no build step. It validates its JSONC config with Zod, multiplexes any number of upstream MCP servers under `/mcp/<name>` on one listener, and passes Streamable HTTP through unmodified for both the 2026-07-28 and 2025-11-25 protocol revisions. Publish transports are plain async functions behind a common type; only the cloudflared adapter is implemented, and it is double-gated (config setting plus `--enable-cloudflared` flag) until the transport decision is accepted.

## Repository layout

| Path | Purpose |
|------|---------|
| `compose.yaml` | The stack: worker, mcp-tunnel, profile-gated cloudflared |
| `sandbox/` | Worker image (Dockerfile) and spawn-per-session script |
| `mcp-tunnel/` | Bun and strict TypeScript MCP reverse proxy with pluggable publish transports |
| `host/systemd/` | The one unit that supervises the stack on bb1 |
| `scripts/deploy-bb1.sh` | Host-side installer, invoked by `just deploy` |
| `examples/tunnel.jsonc` | Tunnel route configuration |
| `backends/cloudflare/` | Alternative execution backend on Cloudflare Sandboxes (same contract, different runtime) |
| `docs/` | Architecture notes and decision records |
| `justfile` | The repeatable workflow: build, run, test, deploy, publish |

## Quick start

Local bring-up:

```sh
cp .env.example .env      # fill in ANTHROPIC_ENVIRONMENT_KEY and _ID
just build
just up
just logs
```

Tunnel development:

```sh
just install
just typecheck
just test
just tunnel-dev
```

## Devcontainer

The repository ships a Claude Code devcontainer adapted from the reference one in anthropics/claude-code, wired into the existing compose stack instead of a standalone build. `.devcontainer/devcontainer.json` points `dockerComposeFile` at `compose.yaml` and uses the `dev` service, which builds the `dev` stage of `sandbox/Dockerfile`. That keeps a single image lineage: the dev stage layers Claude Code (native installer), zsh, git-delta, gh, and the upstream network firewall onto the same base the worker uses.

Docker-in-docker comes from the `ghcr.io/devcontainers/features/docker-in-docker:3` feature, so the full compose stack can be built and run from inside the devcontainer. Be aware of what that costs: the feature requires privileged operation, and with a compose-based devcontainer that flag must sit on the `dev` service itself, alongside the NET_ADMIN and NET_RAW capabilities the firewall script needs. The dev service is therefore a privileged container. It is confined to the `dev` compose profile so it never starts with the sandbox stack, and its shape must not be copied to services that execute untrusted code.

The firewall script is the upstream `init-firewall.sh`, vendored unmodified: default-deny egress with an allowlist of GitHub, npm, and Anthropic endpoints, applied at container start via `postStartCommand`.

```sh
just devcontainer-config   # parse and print the resolved configuration
just devcontainer-up       # build and start (bunx @devcontainers/cli)
just devcontainer-shell    # zsh inside the container
```

VS Code and other devcontainer-aware editors pick up `.devcontainer/devcontainer.json` directly.

## Deployment to bb1

Remote recipes reference the `bb1` SSH host alias from your SSH config; the justfile carries no host, port, or user data. Deployment is a manual step:

```sh
just deploy          # rsync stack to bb1, build images, install the unit
just remote-up       # systemctl start claude-sandbox.service
just remote-status
```

The installer stages the stack in `/opt/claude-sandbox`, seeds `/opt/claude-sandbox/.env` from the example if absent, and installs the systemd unit. Fill in the environment key on the host before starting.

## Alternative backend: Cloudflare Sandboxes

`backends/cloudflare/` implements the same execution contract on Cloudflare's Sandbox SDK (GA since April 2026): sessions become `Sandbox` Durable Object instances, the container image re-applies the same provisioning (ant CLI, Bun) on Cloudflare's base image, the same `ant beta:worker poll` can run inside a sandbox, and in-sandbox MCP servers are exposed through the SDK's native cloudflared tunnels instead of mcp-tunnel. The Worker typechecks today; everything requiring an authenticated wrangler (secrets, dev, deploy) is documented in `backends/cloudflare/README.md` as run-later steps, in the same spirit as the bb1 deploy.

## Plugin marketplace

The repository doubles as a Claude Code plugin marketplace. `.claude-plugin/marketplace.json` declares the `systemd-claude-sandbox` marketplace (currently empty; project plugins land under `plugins/`), and `.claude/settings.json` registers three upstream marketplaces at project scope through `extraKnownMarketplaces`: `claude-plugins-official` (anthropics/claude-plugins-official), `claude-code-plugins` (anthropics/claude-code), and `knowledge-work-plugins` (anthropics/knowledge-work-plugins). Anyone who trusts this project folder in Claude Code is prompted to install these sources automatically. The manifest is checked with `claude plugin validate .`; the only current warning is the intentionally empty plugin list.

## Publishing to GitHub

The repository is created and pushed once with:

```sh
just publish         # gh repo create danielbodnar/systemd-claude-sandbox --private --source=. --push
```

## Open decision: tunnel publish transport

How `mcp-tunnel` becomes reachable from outside bb1 is proposed but not confirmed. Cloudflare Tunnel is the proposed default, with WireGuard and plain SSH forwarding as alternatives. The interfaces in `mcp-tunnel/src/transport/` are final and the cloudflared path is scaffolded behind a flag and a compose profile. See `docs/decisions/0001-tunnel-transport.md` and do not implement further until it is accepted.

## Versions verified against

Verified on 2026-08-01: Anthropic `ant` CLI 1.21.0 with the `managed-agents-2026-04-01` beta, MCP spec revision 2026-07-28, Bun 1.3.14, and the docker compose v2 plugin. A note on the repository name: the earlier iteration of this project built a vmspawn VM image with mkosi, and the systemd-first naming survives from that design. The compose runtime replaced it; the tension is recorded in `docs/architecture.md`.
