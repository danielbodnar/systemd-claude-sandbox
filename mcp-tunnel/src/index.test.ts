import { describe, expect, test } from "bun:test";
import { configSchema, stripJsonc } from "./config.ts";
import { handleRequest } from "./proxy.ts";

describe("config", () => {
  test("parses a minimal config with defaults", () => {
    const config = configSchema.parse({
      routes: [{ name: "filesystem", upstream: "http://mcp-filesystem:9101/mcp" }],
    });
    expect(config.listen.port).toBe(8787);
    expect(config.transport.kind).toBe("none");
  });

  test("rejects invalid route names", () => {
    expect(() =>
      configSchema.parse({
        routes: [{ name: "Bad Name!", upstream: "http://x:1/mcp" }],
      }),
    ).toThrow();
  });

  test("strips jsonc comments and trailing commas", () => {
    const jsonc = `{
      // line comment
      "routes": [ /* inline */ { "name": "a", "upstream": "http://a:1/mcp" }, ],
    }`;
    const parsed = JSON.parse(stripJsonc(jsonc));
    expect(parsed.routes[0].name).toBe("a");
  });
});

describe("proxy", () => {
  const config = configSchema.parse({
    routes: [{ name: "echo", upstream: "http://127.0.0.1:1/mcp" }],
  });

  test("healthz reports routes", async () => {
    const response = await handleRequest(
      config,
      new Request("http://localhost/healthz"),
    );
    const body = (await response.json()) as { ok: boolean; routes: string[] };
    expect(body.ok).toBe(true);
    expect(body.routes).toEqual(["echo"]);
  });

  test("unknown routes 404", async () => {
    const response = await handleRequest(
      config,
      new Request("http://localhost/mcp/nope", { method: "POST" }),
    );
    expect(response.status).toBe(404);
  });

  test("forwards to the upstream endpoint", async () => {
    const upstream = Bun.serve({
      port: 0,
      fetch: async (request) =>
        Response.json({
          path: new URL(request.url).pathname,
          method: request.method,
          echo: await request.text(),
        }),
    });
    const forwarded = configSchema.parse({
      routes: [
        { name: "echo", upstream: `http://127.0.0.1:${upstream.port}/mcp` },
      ],
    });
    const response = await handleRequest(
      forwarded,
      new Request("http://localhost/mcp/echo", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", method: "ping", id: 1 }),
      }),
    );
    const body = (await response.json()) as {
      path: string;
      method: string;
      echo: string;
    };
    expect(body.path).toBe("/mcp");
    expect(body.method).toBe("POST");
    expect(JSON.parse(body.echo).method).toBe("ping");
    await upstream.stop();
  });
});
