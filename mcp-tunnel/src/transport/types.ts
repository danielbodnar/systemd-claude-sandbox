import type { Config } from "../config.ts";

/**
 * A publish transport takes the local proxy URL and makes it reachable by
 * remote MCP clients. Transports are plain async functions returning a
 * handle; adding one means adding a module here and a case in index.ts.
 *
 * The choice of default transport is an open decision. See
 * docs/decisions/0001-tunnel-transport.md before implementing beyond the
 * cloudflared adapter.
 */

export type TransportHandle = {
  readonly kind: string;
  readonly stop: () => Promise<void>;
};

export type TransportOptions = {
  readonly localUrl: string;
  readonly config: Config;
};

export type StartTransport = (options: TransportOptions) => Promise<TransportHandle>;
