# MCP tunnel container. Bun runs TypeScript directly; there is no build
# step. Built from the repository root context so the workspace's single
# root lockfile drives a reproducible, filtered install.

FROM oven/bun:1.3-slim

WORKDIR /app
COPY package.json bun.lock ./
COPY mcp-tunnel/package.json mcp-tunnel/
# bun resolves every workspace declared in the root package.json, so the other
# two manifests must be present even though only mcp-tunnel is installed.
# Without them: `error: Workspace not found "site"`.
COPY site/package.json site/
COPY backends/cloudflare/package.json backends/cloudflare/
RUN bun install --filter ./mcp-tunnel --production --frozen-lockfile

COPY mcp-tunnel/src mcp-tunnel/src

WORKDIR /app/mcp-tunnel
EXPOSE 8787
ENTRYPOINT ["bun", "run", "src/index.ts"]
CMD ["--config", "/etc/mcp-tunnel/tunnel.jsonc"]
