import {
  getSandbox,
  proxyToSandbox,
  type Sandbox as SandboxClass,
} from "@cloudflare/sandbox";

// Required: the Worker must re-export the Sandbox Durable Object class.
export { Sandbox } from "@cloudflare/sandbox";

/**
 * Cloudflare Sandboxes backend for the Claude self-hosted sandbox project.
 * Same contract as the local compose backend, different runtime: a session
 * is an isolated container with /bin/bash, a /workspace directory, Bun,
 * Python, and the ant CLI; per-session isolation comes from one Sandbox
 * instance per session id instead of one docker run per work item.
 *
 * Routes (session id in the path selects the sandbox):
 *   GET    /healthz
 *   POST   /sessions/:id/exec      { "command": "..." }
 *   POST   /sessions/:id/ant       start the Anthropic work poller inside
 *   PUT    /sessions/:id/files     { "path": "...", "content": "..." }
 *   GET    /sessions/:id/files?path=...
 *   POST   /sessions/:id/expose    { "port": 9101 } -> tunnel or preview URL
 *   DELETE /sessions/:id           destroy the sandbox
 */

type Env = {
  // biome-ignore lint/suspicious/noExplicitAny: the SDK's own examples type
  // the namespace over Sandbox<any>; the Env type parameter is not used here.
  Sandbox: DurableObjectNamespace<SandboxClass<any>>;
  ANTHROPIC_ENVIRONMENT_KEY?: string;
  ANTHROPIC_ENVIRONMENT_ID?: string;
};

const json = (data: unknown, status = 200): Response =>
  Response.json(data, { status });

const sessionPattern = /^\/sessions\/([a-zA-Z0-9_-]+)(\/[a-z]+)?$/;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Preview URL requests must be proxied before any application routing.
    const proxied = await proxyToSandbox(request, env);
    if (proxied) return proxied;

    const url = new URL(request.url);
    if (url.pathname === "/healthz") return json({ ok: true });

    const match = sessionPattern.exec(url.pathname);
    if (!match) return json({ error: "no such route" }, 404);
    const [, sessionId, action] = match;

    const sandbox = getSandbox(env.Sandbox, sessionId!);

    if (request.method === "DELETE" && !action) {
      await sandbox.destroy();
      return json({ destroyed: sessionId });
    }

    switch (action) {
      case "/exec": {
        const { command } = (await request.json()) as { command: string };
        const result = await sandbox.exec(command);
        return json(result);
      }
      case "/ant": {
        // Runs this session as an Anthropic self-hosted worker. The
        // environment key comes from Worker secrets; it is scoped to the
        // work queue and safe to hand to the sandbox, unlike an API key.
        if (!env.ANTHROPIC_ENVIRONMENT_KEY || !env.ANTHROPIC_ENVIRONMENT_ID) {
          return json({ error: "environment secrets not configured" }, 503);
        }
        const process = await sandbox.startProcess(
          "ant beta:worker poll --workdir /workspace",
          {
            env: {
              ANTHROPIC_ENVIRONMENT_KEY: env.ANTHROPIC_ENVIRONMENT_KEY,
              ANTHROPIC_ENVIRONMENT_ID: env.ANTHROPIC_ENVIRONMENT_ID,
            },
          },
        );
        return json({ started: process.id });
      }
      case "/files": {
        if (request.method === "PUT") {
          const { path, content } = (await request.json()) as {
            path: string;
            content: string;
          };
          await sandbox.writeFile(path, content);
          return json({ written: path });
        }
        const path = url.searchParams.get("path");
        if (!path) return json({ error: "path query parameter required" }, 400);
        const file = await sandbox.readFile(path);
        return json(file);
      }
      case "/expose": {
        // For MCP servers running inside the sandbox this is the analogue
        // of mcp-tunnel plus cloudflared: tunnels.get() starts a quick
        // tunnel (*.trycloudflare.com) via cloudflared inside the sandbox,
        // with named tunnels and exposePort() preview URLs as the custom
        // domain alternatives.
        const { port } = (await request.json()) as { port: number };
        const tunnel = await sandbox.tunnels.get(port);
        return json({ url: tunnel.url });
      }
      default:
        return json({ error: "no such route" }, 404);
    }
  },
};
