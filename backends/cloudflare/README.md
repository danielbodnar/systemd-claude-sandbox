# Cloudflare Sandboxes backend

[![Deploy to Cloudflare](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https%3A%2F%2Fgithub.com%2Fdanielbodnar%2Fsystemd-claude-sandbox%2Ftree%2Fmain%2Fbackends%2Fcloudflare)

The button deploys your own instance of this backend to your own Cloudflare account: it clones the repository into your GitHub or GitLab account, prompts for the secrets declared in [`.dev.vars.example`](.dev.vars.example) (`ANTHROPIC_ENVIRONMENT_KEY`, `ANTHROPIC_ENVIRONMENT_ID`, and `SANDBOX_API_TOKEN`), provisions the `Sandbox` Durable Object, and builds and deploys this directory's Worker (`wrangler.jsonc`) through Workers Builds, redeploying on every push to your clone. The container image requires a Workers paid plan with Containers enabled. Deploying by hand instead follows the run-later steps below.

The Worker lands on a public `workers.dev` endpoint, and every route except `/healthz` executes commands or allocates paid container resources, so the API is gated: requests must carry `Authorization: Bearer <SANDBOX_API_TOKEN>`, and the Worker refuses all requests until that secret is set. Generate a strong token (`openssl rand -hex 32`) when prompted. For defense in depth, put the Worker behind [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/policies/access/) as well.

An alternative execution backend for the Claude self-hosted sandbox: the same contract as the local compose stack, running on Cloudflare's Sandbox SDK (generally available since April 2026) instead of Docker on a self-hosted server. A session is still an isolated Linux container with `/bin/bash`, a `/workspace` directory, Bun, Python, and the `ant` CLI; what changes is who runs the container and how it is reached.

## Contract mapping

| Concern           | Local compose backend                                | Cloudflare backend                                                                    |
| ----------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Session isolation | `docker run --rm` per work item (`sandbox/spawn.sh`) | One `Sandbox` Durable Object instance per session id                                  |
| Image             | `sandbox/Dockerfile` (Debian base)                   | `Dockerfile` here, extending `docker.io/cloudflare/sandbox`                           |
| Anthropic worker  | compose `worker` service runs `ant beta:worker poll` | `POST /sessions/:id/ant` starts the same poller inside the sandbox                    |
| MCP exposure      | `mcp-tunnel` plus a publish transport                | `sandbox.tunnels.get(port)` (cloudflared quick tunnel) or `exposePort()` preview URLs |
| Egress control    | vendored `init-firewall.sh`, compose network         | SDK outbound handlers (`setOutboundHandler`)                                          |
| Supervision       | systemd unit on the deploy host                      | Cloudflare's control plane                                                            |

Cloudflare requires containers to extend its base image, so this backend cannot share the Debian base image literally. The Dockerfile instead re-applies the identical provisioning steps (same `ant` and Bun versions, same install commands) on top of `cloudflare/sandbox`, which keeps the runtime contents aligned. Version bumps should touch both Dockerfiles together.

## Status: scaffold

The Worker compiles and expresses the contract, but everything that needs a Cloudflare account is deliberately left as run-later steps, since this environment's Cloudflare access is unauthenticated. In order:

```sh
cd backends/cloudflare
bun install
bun run typecheck                                  # works now, no account needed
wrangler login                                     # run-later, opens a browser
wrangler secret put ANTHROPIC_ENVIRONMENT_KEY      # run-later
wrangler secret put ANTHROPIC_ENVIRONMENT_ID       # run-later
wrangler secret put SANDBOX_API_TOKEN              # run-later; openssl rand -hex 32
wrangler dev                                       # run-later, needs Docker locally
wrangler deploy                                    # run-later
```

Notes for those steps. `wrangler dev` requires a working Docker daemon to build and run the container locally. Quick tunnels (`tunnels.get`) work from `.workers.dev` with no DNS setup; `exposePort()` preview URLs in production require a custom domain with wildcard DNS, and named tunnels require a Cloudflare Tunnel configured in the zone. The `instance_type` is `lite` in `wrangler.jsonc`; raise it if sessions need more memory or CPU.

## Relationship to ADR 0001

The tunnel transport decision gains a data point here: on this backend, Cloudflare Tunnel is not an optional publisher but the SDK's native path for exposing in-sandbox services. If ADR 0001 is accepted with Cloudflare Tunnel as the default, both backends converge on the same edge.
