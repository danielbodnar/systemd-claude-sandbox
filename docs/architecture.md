# Architecture notes

## Contract first

The design follows the Managed Agents self-hosted sandbox guide rather than inventing a sandbox API. Anthropic's control plane holds the queue; nothing on bb1 accepts inbound connections from Anthropic. The worker authenticates with an environment key scoped to posting results for its own queue, which is why the stack never sees the organization API key. Session inputs that would normally be mounted by Anthropic (files, repositories) do not exist on self-hosted sandboxes; anything the session needs is passed through session `metadata` and fetched by the worker or the session itself.

## Two isolation modes

The compose `worker` service is the always-on poller: simple, fast, one filesystem shared across sessions inside the `workspace` volume. This is the right mode for a single trusted user iterating quickly.

`sandbox/spawn.sh` is the per-session mode from the upstream guide. The poller runs on the host with `--on-work sandbox/spawn.sh`, and each claimed work item becomes a fresh `docker run --rm` container with its own `/workspace` bind mount, memory, CPU, and pid limits. Session state dies with the container; deliverables survive in the per-session output directory on the host. Choose this mode when sessions run untrusted code or when sessions must not see one another's files.

## Where systemd fits now

The first iteration of this repository built a bootable VM image with mkosi and ran it under `systemd-vmspawn --ephemeral`, with a slice hierarchy and networkd files in the style of the BitBuilder hypervisor. The runtime pivoted to docker compose, which collapses most of that machinery: image building becomes a Dockerfile, per-session ephemerality becomes `docker run --rm`, and the network becomes a compose network.

There is a real tension worth recording. Container isolation is weaker than hardware virtualization, and the vmspawn design offered a stronger boundary for hostile code at the cost of a second image pipeline. The compose-first layout keeps exactly one pipeline, per the direction to not build both. If the stronger boundary is wanted later, the clean seam is the container runtime, not a parallel image build: point the compose services or `spawn.sh` at a VM-isolated OCI runtime rather than reintroducing mkosi. The remaining systemd surface is a single supervising unit, `claude-sandbox.service`, which is honest about what it can control: restart policy and boot ordering, not container cgroups.

## mcp-tunnel

The tunnel exists for interactive MCP clients. Claude Desktop and claude.ai connect to remote MCP servers over Streamable HTTP, and servers inside the sandbox network are not reachable from the internet. The tunnel is one listener that multiplexes servers by path prefix, so a single published hostname serves any number of sandbox-internal MCP servers.

Two design choices keep it thin. First, the proxy is protocol-transparent: it forwards any method and streams bodies both ways, so both the 2026-07-28 revision (single POST endpoint, sessions removed) and older 2025-11-25 clients (GET event streams, session headers) pass through without the proxy tracking any of it. Second, publishing is separated from listening. A transport adapter is an async function that makes the local listener reachable and returns a stop handle. The cloudflared adapter spawns a token-mode `cloudflared`; the WireGuard and SSH adapters are placeholders pending the transport decision.

Note the distinction with the worker path: MCP servers that only the agent needs are better wrapped as custom tools by the worker (no inbound connectivity, no tunnel at all). The tunnel is for humans pointing Claude Desktop or claude.ai at the sandbox.

## Security posture

The worker host holds one secret, the environment key. The tunnel listener binds loopback on the host by default (`127.0.0.1:8787`); only a transport makes it reachable, and the proposed transport (Cloudflare Tunnel) adds Zero Trust access control in front of it, which matters because MCP servers behind the tunnel trust their callers. Sandbox containers run with `no-new-privileges`, pid limits, and memory and CPU ceilings. Anything stronger, such as gVisor, Kata, or a return to hardware virtualization, slots in at the runtime seam described above.
