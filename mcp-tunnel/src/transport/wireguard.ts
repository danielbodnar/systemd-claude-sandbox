import type { StartTransport } from "./types.ts";

/**
 * WireGuard adapter placeholder. Intentionally unimplemented until the
 * transport decision (docs/decisions/0001-tunnel-transport.md) is settled.
 * The shape it would take: assert the wg interface is up via networkctl or
 * wg show, then simply report the proxy's address on the tunnel network,
 * since WireGuard makes the listener reachable without a helper process.
 */
export const startWireguard: StartTransport = async () => {
  throw new Error(
    "wireguard transport is not implemented; the transport decision is pending (docs/decisions/0001-tunnel-transport.md)",
  );
};
