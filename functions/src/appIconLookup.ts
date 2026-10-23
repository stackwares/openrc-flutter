import {onRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

const BUNDLE_ID = /^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+$/;

const STORE_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (compatible; RevenueCatIconLookup/1.0; +https://revenuecat.com)",
  "Accept-Language": "en",
};

type StoreHint = "apple" | "google" | "unknown";

function hintOf(value: unknown): StoreHint {
  if (value === "google") return "google";
  if (value === "apple") return "apple";
  return "unknown";
}

/** Same artwork selection as the Flutter `parseItunesLookupIcon`. */
export function parseItunesLookupIcon(data: unknown): string | null {
  if (typeof data === "string") {
    try {
      data = JSON.parse(data) as unknown;
    } catch {
      return null;
    }
  }
  if (data == null || typeof data !== "object") return null;
  const results = (data as {results?: unknown}).results;
  if (!Array.isArray(results) || results.length === 0) return null;
  const first = results[0];
  if (first == null || typeof first !== "object") return null;
  const row = first as Record<string, unknown>;
  for (const key of ["artworkUrl512", "artworkUrl100", "artworkUrl60"]) {
    const v = row[key];
    if (typeof v === "string" && v.startsWith("https://")) return v;
  }
  return null;
}

/** Same og:image selection as the Flutter `parseGooglePlayIcon`. */
export function parseGooglePlayIcon(html: string | null | undefined): string | null {
  if (!html) return null;
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

async function fetchText(url: string): Promise<{status: number; body: string} | null> {
  try {
    const res = await fetch(url, {
      headers: STORE_HEADERS,
      redirect: "follow",
      signal: AbortSignal.timeout(12_000),
    });
    return {status: res.status, body: await res.text()};
  } catch (e) {
    logger.info("Store fetch failed", {url: new URL(url).hostname, error: String(e)});
    return null;
  }
}

async function fromAppStore(bundleId: string): Promise<string | null> {
  for (const entity of [null, "macSoftware"]) {
    const url = new URL("https://itunes.apple.com/lookup");
    url.searchParams.set("bundleId", bundleId);
    if (entity) url.searchParams.set("entity", entity);
    const res = await fetchText(url.toString());
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
  const res = await fetchText(url.toString());
  if (!res || res.status !== 200) return null;
  return parseGooglePlayIcon(res.body);
}

async function findIcon(bundleId: string, hint: StoreHint): Promise<string | null> {
  const order = hint === "google"
    ? [fromGooglePlay, fromAppStore]
    : [fromAppStore, fromGooglePlay];
  for (const source of order) {
    const url = await source(bundleId);
    if (url) return url;
  }
  return null;
}

/**
 * Public icon lookup for the Flutter web app. Browsers cannot call the
 * stores directly (CORS). Only reverse-DNS ids are accepted, and only the
 * two fixed store hosts are fetched.
 */
export const lookupAppIcon = onRequest(
  {
    region: "us-central1",
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (req.method !== "GET") {
      res.status(405).send("Method Not Allowed");
      return;
    }
    const bundleId = typeof req.query.bundleId === "string" ? req.query.bundleId.trim() : "";
    if (!BUNDLE_ID.test(bundleId) || bundleId.length > 255) {
      res.status(400).json({url: null});
      return;
    }
    const url = await findIcon(bundleId, hintOf(req.query.hint));
    res.set("Cache-Control", "public, max-age=86400");
    res.status(200).json({url});
  },
);
