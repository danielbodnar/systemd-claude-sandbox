# MCP tunnel container. Bun runs TypeScript directly; there is no build
# step. Built from the repository root context so the workspace's single
# root lockfile drives a reproducible, filtered install.

FROM oven/bun:1.3-slim

WORKDIR /app
COPY package.json bun.lock ./
COPY mcp-tunnel/package.json mcp-tunnel/
#RUN bun install --filter ./mcp-tunnel --production --frozen-lockfile
RUN bun install --filter ./mcp-tunnel --production
COPY mcp-tunnel/src mcp-tunnel/src

WORKDIR /app/mcp-tunnel
EXPOSE 8787
ENTRYPOINT ["bun", "run", "src/index.ts"]
CMD ["--config", "/etc/mcp-tunnel/tunnel.jsonc"]
