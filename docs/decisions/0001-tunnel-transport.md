# ADR 0001: Publish transport for mcp-tunnel

Status: Proposed. Awaiting confirmation from Daniel before implementation proceeds beyond the scaffolded cloudflared adapter.

## Context

`mcp-tunnel` listens on a loopback port on bb1 and must become reachable by remote MCP clients, primarily Claude Desktop and claude.ai connectors, which speak MCP Streamable HTTP to a public URL. Three transports are on the table.

**Cloudflare Tunnel.** A token-mode `cloudflared` makes an outbound connection to Cloudflare's edge and publishes the listener at a hostname under a zone Daniel controls. No inbound ports on bb1, TLS termination and DDoS posture handled at the edge, and Cloudflare Access can require authentication in front of the tunnel. This matches the existing platform preference and is the only option that gives claude.ai connectors a clean public HTTPS endpoint without exposing bb1. The costs are a dependency on Cloudflare's availability and the tunnel token as a new secret.

**WireGuard.** A point-to-point tunnel between bb1 and each client machine. Strongest network posture and no third party, but every client needs a WireGuard peer configuration, and claude.ai connectors cannot join a private network at all, so this only serves Claude Desktop from machines Daniel controls.

**SSH forwarding.** `ssh -N -L 8787:localhost:8787 bb1` and pointing Claude Desktop at localhost. Zero new infrastructure and it reuses the existing bb1 SSH access, but it is per-machine, manual, breaks on network changes, and likewise cannot serve claude.ai.

## Decision

Proposed, not accepted: default to Cloudflare Tunnel, keep the transport pluggable so WireGuard or SSH can be selected per deployment. The deciding constraint is claude.ai connector support, which requires a public HTTPS endpoint that only the Cloudflare option provides without opening inbound ports on bb1.

## Consequences

Until acceptance, the cloudflared path stays double-gated: the compose service sits behind the `cloudflared` profile, and the in-process adapter requires the `--enable-cloudflared` flag in addition to the config setting. The WireGuard and SSH adapters remain intentional stubs that fail loudly and point here. Accepting this record means enabling the profile by default, pinning the cloudflared image tag, documenting tunnel and Access setup, and implementing health reporting for the publisher. Rejecting it in favor of WireGuard or SSH means implementing the corresponding adapter and documenting that claude.ai connectors are out of scope.
