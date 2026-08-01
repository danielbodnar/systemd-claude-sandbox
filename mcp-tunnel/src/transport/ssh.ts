import type { StartTransport } from "./types.ts";

/**
 * SSH forwarding adapter placeholder. Intentionally unimplemented until the
 * transport decision (docs/decisions/0001-tunnel-transport.md) is settled.
 * The shape it would take: no daemon at all. Clients forward the port
 * themselves (ssh -N -L 8787:localhost:8787 bb1) and this adapter merely
 * documents and verifies the expectation.
 */
export const startSsh: StartTransport = async () => {
  throw new Error(
    "ssh transport is not implemented; the transport decision is pending (docs/decisions/0001-tunnel-transport.md)",
  );
};
