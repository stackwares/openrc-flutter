import { isLlmPath, LLM_ALLOWED_HEADERS } from "./llm";

/** Headers the web app sends; anything else fails the preflight. */
const ALLOWED_HEADERS = "Authorization, Content-Type, X-Requested-With";
const ALLOWED_METHODS = "GET, POST, PUT, PATCH, DELETE, OPTIONS";

/**
 * Whether a browser page at `origin` may use the relay. `allowList` is
 * comma-separated: exact origins, `https://*.example.com` for subdomains,
 * and `http://localhost:*` for any port.
 */
export function isAllowedOrigin(origin: string | null, allowList: string): boolean {
  if (!origin) return false;
  let url: URL;
  try {
    url = new URL(origin);
  } catch {
    return false;
  }
  // An Origin is scheme, host and port only; anything else is not genuine.
  if (url.origin !== origin) return false;
  return allowList
    .split(",")
    .map((entry) => entry.trim())
    .some((entry) => entry !== "" && matches(url, entry));
}

function matches(origin: URL, entry: string): boolean {
  const parts = /^(https?):\/\/(\*\.)?([a-z0-9.-]+)(?::(\*|\d+))?$/i.exec(entry);
  if (!parts) return false;
  const [, scheme, wildcard, host, port] = parts;
  if (origin.protocol !== `${scheme.toLowerCase()}:`) return false;
  const hostname = host.toLowerCase();
  const hostMatches = wildcard
    ? origin.hostname.endsWith(`.${hostname}`)
    : origin.hostname === hostname;
  if (!hostMatches) return false;
  if (port === "*") return true;
  // URL.port is empty for the scheme's default port.
  return origin.port === (port ?? "");
}

/** Answers a CORS preflight from an allowed origin. */
export function preflight(origin: string, requestUrl?: string): Response {
  const pathname = requestUrl ? new URL(requestUrl).pathname : "";
  const headers = isLlmPath(pathname)
    ? `${ALLOWED_HEADERS}, ${LLM_ALLOWED_HEADERS}`
    : ALLOWED_HEADERS;
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Methods": ALLOWED_METHODS,
      "Access-Control-Allow-Headers": headers,
      "Access-Control-Max-Age": "86400",
      Vary: "Origin",
    },
  });
}

/** Lets the page at `origin` read `response`. */
export function withCors(response: Response, origin: string): Response {
  const headers = new Headers(response.headers);
  headers.set("Access-Control-Allow-Origin", origin);
  headers.set("Access-Control-Expose-Headers", "Retry-After");
  headers.append("Vary", "Origin");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
