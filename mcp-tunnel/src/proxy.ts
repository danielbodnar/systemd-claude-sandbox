import type { Config, Route } from "./config.ts";

/**
 * Reverse proxy for MCP Streamable HTTP. One local listener multiplexes any
 * number of in-sandbox MCP servers under /mcp/<route>. The proxy is method
 * agnostic: revision 2026-07-28 needs POST only, while clients on the
 * 2025-11-25 revision may also open GET streams and DELETE sessions, and all
 * of that passes through unchanged.
 */

const hopByHop = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
  "host",
]);

const forwardHeaders = (from: Headers): Headers => {
  const out = new Headers();
  from.forEach((value, key) => {
    if (!hopByHop.has(key.toLowerCase())) out.set(key, value);
  });
  return out;
};

const matchRoute = (
  routes: readonly Route[],
  pathname: string,
): { route: Route; rest: string } | undefined => {
  for (const route of routes) {
    const prefix = `/mcp/${route.name}`;
    if (pathname === prefix || pathname.startsWith(`${prefix}/`)) {
      return { route, rest: pathname.slice(prefix.length) };
    }
  }
  return undefined;
};

export const handleRequest = async (
  config: Config,
  request: Request,
): Promise<Response> => {
  const url = new URL(request.url);

  if (url.pathname === "/healthz") {
    return Response.json({
      ok: true,
      routes: config.routes.map((route) => route.name),
    });
  }

  const match = matchRoute(config.routes, url.pathname);
  if (!match) return new Response("no such route", { status: 404 });

  const upstream = new URL(match.route.upstream);
  upstream.pathname = `${upstream.pathname.replace(/\/$/, "")}${match.rest}` || upstream.pathname;
  upstream.search = url.search;

  return fetch(upstream, {
    method: request.method,
    headers: forwardHeaders(request.headers),
    body: request.body,
    // Streams request bodies instead of buffering them.
    duplex: "half",
    redirect: "manual",
  } as RequestInit);
};

export const startProxy = (config: Config) => {
  const server = Bun.serve({
    hostname: config.listen.hostname,
    port: config.listen.port,
    idleTimeout: 0,
    fetch: (request) => handleRequest(config, request),
  });
  return {
    url: `http://${config.listen.hostname}:${server.port}`,
    stop: () => server.stop(),
  };
};
