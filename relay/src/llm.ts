/** Allowlisted BYOK LLM upstreams for the web app (stateless pass-through). */

export const LLM_PRESETS = {
  openrouter: "https://openrouter.ai/api/v1",
  openai: "https://api.openai.com/v1",
  anthropic: "https://api.anthropic.com",
  deepseek: "https://api.deepseek.com",
} as const;

export type LlmPreset = keyof typeof LLM_PRESETS;

export const LLM_PRESET_LIST = Object.keys(LLM_PRESETS) as LlmPreset[];

const LLM_FORWARD_HEADERS = [
  "accept",
  "accept-language",
  "authorization",
  "content-type",
  "x-api-key",
  "anthropic-version",
  "x-title",
  "http-referer",
];

export function isLlmPath(pathname: string): boolean {
  return pathname.startsWith("/llm/");
}

export function parseLlmPath(
  pathname: string,
  rawUrl?: string,
): { preset: LlmPreset; rest: string } | null {
  const raw = rawUrl ?? pathname;
  if (/\.\.|%2e%2e/i.test(raw)) return null;
  const parts = pathname.split("/").filter(Boolean);
  if (parts[0] !== "llm" || parts.length < 2) return null;
  for (const segment of parts.slice(2)) {
    let decoded = segment;
    try {
      decoded = decodeURIComponent(segment);
    } catch {
      return null;
    }
    if (decoded === ".." || decoded === "." || decoded.includes("\\")) {
      return null;
    }
  }
  const preset = parts[1] as LlmPreset;
  if (!(preset in LLM_PRESETS)) return null;
  const rest = `/${parts.slice(2).join("/")}`;
  let decoded = rest;
  try {
    decoded = decodeURIComponent(rest);
  } catch {
    return null;
  }
  if (
    rest.includes("..") ||
    decoded.includes("..") ||
    rest.includes("\\") ||
    decoded.includes("\\") ||
    /^https?:/i.test(rest) ||
    /^https?:/i.test(decoded)
  ) {
    return null;
  }
  return { preset, rest: rest === "/" ? "" : rest };
}

export async function forwardLlm(
  request: Request,
  preset: LlmPreset,
  rest: string,
): Promise<Response> {
  const upstream = LLM_PRESETS[preset];
  const headers = new Headers();
  for (const name of LLM_FORWARD_HEADERS) {
    const value = request.headers.get(name);
    if (value !== null) headers.set(name, value);
  }
  const hasBody = request.method !== "GET" && request.method !== "HEAD";
  const url = `${upstream}${rest}${new URL(request.url).search}`;
  let upstreamResponse: Response;
  try {
    upstreamResponse = await fetch(url, {
      method: request.method,
      headers,
      body: hasBody ? request.body : null,
      redirect: "manual",
    });
  } catch (error) {
    console.error(
      JSON.stringify({
        message: "LLM provider unreachable",
        preset,
        error: error instanceof Error ? error.message : String(error),
      }),
    );
    return Response.json({ error: "upstream_unreachable" }, { status: 502 });
  }
  const responseHeaders = new Headers(upstreamResponse.headers);
  for (const name of [...responseHeaders.keys()]) {
    if (name === "set-cookie" || name.startsWith("access-control-")) {
      responseHeaders.delete(name);
    }
  }
  return new Response(upstreamResponse.body, {
    status: upstreamResponse.status,
    statusText: upstreamResponse.statusText,
    headers: responseHeaders,
  });
}

export const LLM_ALLOWED_HEADERS =
  "Authorization, Content-Type, Accept, X-Api-Key, Anthropic-Version, X-Title, HTTP-Referer";
