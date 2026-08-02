import { z } from "zod";

/**
 * Tunnel configuration. Loaded from a JSONC file so the deployed config can
 * carry commentary. Validation happens at the edge; everything past this
 * module is typed data.
 */

export const routeSchema = z.object({
  /** Path segment under /mcp/. Becomes the public route name. */
  name: z.string().regex(/^[a-z0-9][a-z0-9-]*$/),
  /**
   * Full upstream MCP endpoint URL inside the sandbox network, for example
   * http://mcp-filesystem:9101/mcp. The upstream must speak MCP Streamable
   * HTTP (spec revision 2026-07-28 or the 2025-11-25 revision).
   */
  upstream: z.url(),
});

export const transportKindSchema = z.enum(["none", "cloudflared", "wireguard", "ssh"]);

export const configSchema = z.object({
  listen: z
    .object({
      hostname: z.string().default("0.0.0.0"),
      port: z.int().min(1).max(65535).default(8787),
    })
    .prefault({}),
  routes: z.array(routeSchema).min(1),
  transport: z
    .object({
      kind: transportKindSchema.default("none"),
      cloudflared: z
        .object({
          binary: z.string().default("cloudflared"),
          tokenEnv: z.string().default("CLOUDFLARE_TUNNEL_TOKEN"),
        })
        .optional(),
    })
    .prefault({ kind: "none" }),
});

export type Route = z.infer<typeof routeSchema>;
export type TransportKind = z.infer<typeof transportKindSchema>;
export type Config = z.infer<typeof configSchema>;

/** Strips // and /* *\/ comments plus trailing commas from JSONC. */
export const stripJsonc = (text: string): string =>
  text
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:"'\\])\/\/.*$/gm, "$1")
    .replace(/,(\s*[}\]])/g, "$1");

export const loadConfig = async (path: string): Promise<Config> => {
  const raw = await Bun.file(path).text();
  return configSchema.parse(JSON.parse(stripJsonc(raw)));
};
