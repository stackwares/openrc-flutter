/**
 * OpenRC relay: lets the OpenRC web app reach RevenueCat's developer API,
 * which answers browsers only from RevenueCat's own dashboard. Stateless:
 * nothing is stored, and request and response bodies stream through unread.
 */

import { isAllowedOrigin, preflight, withCors } from "./cors";
import { iconResponse } from "./icons";

const UPSTREAM = "https://api.revenuecat.com";

/** RevenueCat's developer API: the only paths passed through. */
const API_PATH = /^\/(?:internal\/)?v1\/developers(?:\/|$)/;

const API_METHODS = new Set(["GET", "POST", "PUT", "PATCH", "DELETE"]);

/** What RevenueCat needs from the browser's request; cookies stay behind. */
const FORWARDED_HEADERS = [
  "accept",
  "accept-language",
  "authorization",
  "content-type",
  "user-agent",
  "x-requested-with",
];

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/" && request.method === "GET") {
      return Response.json({ service: "openrc-relay", ok: true });
    }

    // Only the OpenRC web app's own pages may use the relay.
    const origin = request.headers.get("Origin");
    if (!origin || !isAllowedOrigin(origin, env.ALLOWED_ORIGINS)) {
      return Response.json({ error: "origin_not_allowed" }, { status: 403 });
    }
    if (request.method === "OPTIONS") return preflight(origin);
    return withCors(await route(request, url), origin);
  },
} satisfies ExportedHandler<Env>;

async function route(request: Request, url: URL): Promise<Response> {
  if (url.pathname === "/icon") {
    return request.method === "GET" ? iconResponse(url) : methodNotAllowed();
  }
  if (API_PATH.test(url.pathname)) {
    return API_METHODS.has(request.method) ? forward(request, url) : methodNotAllowed();
  }
  return Response.json({ error: "not_found" }, { status: 404 });
}

async function forward(request: Request, url: URL): Promise<Response> {
  const headers = new Headers();
  for (const name of FORWARDED_HEADERS) {
    const value = request.headers.get(name);
    if (value !== null) headers.set(name, value);
  }
  const hasBody = request.method !== "GET" && request.method !== "HEAD";

  let upstream: Response;
  try {
    upstream = await fetch(`${UPSTREAM}${url.pathname}${url.search}`, {
      method: request.method,
      headers,
      body: hasBody ? request.body : null,
      redirect: "manual",
    });
  } catch (error) {
    console.error(
      JSON.stringify({
        message: "RevenueCat unreachable",
        error: error instanceof Error ? error.message : String(error),
      }),
    );
    return Response.json({ error: "upstream_unreachable" }, { status: 502 });
  }

  const responseHeaders = new Headers(upstream.headers);
  for (const name of [...responseHeaders.keys()]) {
    if (name === "set-cookie" || name.startsWith("access-control-")) {
      responseHeaders.delete(name);
    }
  }
  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: responseHeaders,
  });
}

function methodNotAllowed(): Response {
  return Response.json({ error: "method_not_allowed" }, { status: 405 });
}
