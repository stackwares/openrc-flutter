/**
 * App icon lookup for the web app: browsers can't call the App Store or
 * Google Play directly. Accepts only reverse-DNS ids and fetches only the two
 * fixed store hosts.
 */

const BUNDLE_ID = /^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+$/;

const STORE_HEADERS = {
  "User-Agent": "Mozilla/5.0 (compatible; OpenRCIconLookup/1.0; +https://github.com/stackwares/openrc)",
  "Accept-Language": "en",
};

type StoreHint = "apple" | "google" | "unknown";

function hintOf(value: string | null): StoreHint {
  return value === "apple" || value === "google" ? value : "unknown";
}

/** Same artwork choice as the app's `parseItunesLookupIcon`. */
export function parseItunesLookupIcon(body: string): string | null {
  let data: unknown;
  try {
    data = JSON.parse(body);
  } catch {
    return null;
  }
  if (data === null || typeof data !== "object") return null;
  const results = (data as { results?: unknown }).results;
  if (!Array.isArray(results) || results.length === 0) return null;
  const first: unknown = results[0];
  if (first === null || typeof first !== "object") return null;
  const row = first as Record<string, unknown>;
  for (const key of ["artworkUrl512", "artworkUrl100", "artworkUrl60"]) {
    const value = row[key];
    if (typeof value === "string" && value.startsWith("https://")) return value;
  }
  return null;
}

/** Same og:image choice as the app's `parseGooglePlayIcon`. */
export function parseGooglePlayIcon(html: string): string | null {
  const patterns = [
    /<meta[^>]+property="og:image"[^>]+content="([^"]+)"/,
    /<meta[^>]+content="([^"]+)"[^>]+property="og:image"/,
    /<img[^>]+itemprop="image"[^>]+src="([^"]+)"/,
  ];
  for (const pattern of patterns) {
    const url = pattern.exec(html)?.[1]?.replace(/&amp;/g, "&");
    if (!url || !url.startsWith("https://")) continue;
    try {
      if (!new URL(url).hostname.endsWith("googleusercontent.com")) continue;
    } catch {
      continue;
    }
    return url.replace(/=s\d+(?=-|$)/, "=s256");
  }
  return null;
}

/** A store page or lookup; small and bounded, so reading it whole is fine. */
async function fetchText(url: URL): Promise<{ status: number; body: string } | null> {
  try {
    const res = await fetch(url, {
      headers: STORE_HEADERS,
      redirect: "follow",
      signal: AbortSignal.timeout(12_000),
    });
    return { status: res.status, body: await res.text() };
  } catch (error) {
    console.warn(
      JSON.stringify({
        message: "store lookup failed",
        host: url.hostname,
        error: error instanceof Error ? error.message : String(error),
      }),
    );
    return null;
  }
}

async function fromAppStore(bundleId: string): Promise<string | null> {
  for (const entity of [null, "macSoftware"]) {
    const url = new URL("https://itunes.apple.com/lookup");
    url.searchParams.set("bundleId", bundleId);
    if (entity) url.searchParams.set("entity", entity);
    const res = await fetchText(url);
    if (!res) return null;
    const icon = parseItunesLookupIcon(res.body);
    if (icon) return icon;
  }
  return null;
}

async function fromGooglePlay(packageName: string): Promise<string | null> {
  const url = new URL("https://play.google.com/store/apps/details");
  url.searchParams.set("id", packageName);
  url.searchParams.set("hl", "en");
  const res = await fetchText(url);
  if (!res || res.status !== 200) return null;
  return parseGooglePlayIcon(res.body);
}

/** `GET /icon?bundleId=com.example.app&hint=apple|google` → `{ "url": ... }`. */
export async function iconResponse(url: URL): Promise<Response> {
  const bundleId = url.searchParams.get("bundleId")?.trim() ?? "";
  if (bundleId.length > 255 || !BUNDLE_ID.test(bundleId)) {
    return Response.json({ url: null }, { status: 400 });
  }
  const order =
    hintOf(url.searchParams.get("hint")) === "google"
      ? [fromGooglePlay, fromAppStore]
      : [fromAppStore, fromGooglePlay];
  let icon: string | null = null;
  for (const source of order) {
    icon = await source(bundleId);
    if (icon) break;
  }
  return Response.json(
    { url: icon },
    { headers: { "Cache-Control": "public, max-age=86400" } },
  );
}
