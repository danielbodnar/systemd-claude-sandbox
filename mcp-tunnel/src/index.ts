import { parseArgs } from "node:util";
import { loadConfig } from "./config.ts";
import { startProxy } from "./proxy.ts";
import { startCloudflared } from "./transport/cloudflared.ts";
import { startSsh } from "./transport/ssh.ts";
import type { TransportHandle } from "./transport/types.ts";
import { startWireguard } from "./transport/wireguard.ts";

const { values } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    config: { type: "string", default: "/etc/mcp-tunnel/tunnel.jsonc" },
    // Guard rail: the cloudflared transport stays off until the transport
    // decision is accepted, even if the config asks for it.
    "enable-cloudflared": { type: "boolean", default: false },
  },
});

const config = await loadConfig(values.config);
const proxy = startProxy(config);
console.log(`mcp-tunnel listening on ${proxy.url}`);
for (const route of config.routes) {
  console.log(`  /mcp/${route.name} -> ${route.upstream}`);
}

let transport: TransportHandle | undefined;
switch (config.transport.kind) {
  case "none":
    break;
  case "cloudflared":
    if (!values["enable-cloudflared"]) {
      console.warn(
        "transport.kind is cloudflared but --enable-cloudflared was not passed; " +
          "running local listener only (decision pending, see docs/decisions/0001-tunnel-transport.md)",
      );
      break;
    }
    transport = await startCloudflared({ localUrl: proxy.url, config });
    break;
  case "wireguard":
    transport = await startWireguard({ localUrl: proxy.url, config });
    break;
  case "ssh":
    transport = await startSsh({ localUrl: proxy.url, config });
    break;
}

const shutdown = async () => {
  await transport?.stop();
  await proxy.stop();
  process.exit(0);
};
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
