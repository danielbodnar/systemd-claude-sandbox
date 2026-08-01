# MCP tunnel container. Bun runs TypeScript directly; there is no build step.

FROM oven/bun:1.3-slim

WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production

COPY src ./src

EXPOSE 8787
ENTRYPOINT ["bun", "run", "src/index.ts"]
CMD ["--config", "/etc/mcp-tunnel/tunnel.jsonc"]
