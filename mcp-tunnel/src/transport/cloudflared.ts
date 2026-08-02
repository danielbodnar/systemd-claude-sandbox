import type { StartTransport } from "./types.ts";

/**
 * Cloudflare Tunnel adapter. Proposed default, pending confirmation
 * (docs/decisions/0001-tunnel-transport.md). Runs a token-mode cloudflared
 * whose ingress rule, configured in the Zero Trust dashboard, points at the
 * local proxy. In compose, prefer the dedicated cloudflared service under
 * the "cloudflared" profile; this adapter exists for single-process
 * deployments and local testing.
 */
export const startCloudflared: StartTransport = async ({ config }) => {
  const settings = config.transport.cloudflared ?? {
    binary: "cloudflared",
    tokenEnv: "CLOUDFLARE_TUNNEL_TOKEN",
  };
  const token = Bun.env[settings.tokenEnv];
  if (!token) {
    throw new Error(`missing tunnel token in $${settings.tokenEnv}`);
  }

  const child = Bun.spawn([settings.binary, "tunnel", "--no-autoupdate", "run", "--token", token], {
    stdout: "inherit",
    stderr: "inherit",
  });

  return {
    kind: "cloudflared",
    stop: async () => {
      child.kill("SIGTERM");
      await child.exited;
    },
  };
};
