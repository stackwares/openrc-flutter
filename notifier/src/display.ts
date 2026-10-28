import { parseLanguage, type Language } from "./strings";

/**
 * How a device shows notifications, as the app puts it in the webhook URL:
 * `lang=de` for the app's language (English when missing),
 * `currency=EUR` for its display currency and `fees=15,30` (App Store, then
 * Google Play, in percent) when it subtracts store fees, plus `rate`, the
 * app's last saved rate for that currency, in case no fresh one can be had.
 * Like the app (`lib/core/utils/store_commission.dart`), other stores keep
 * no fee. `names` holds the product names Settings gave.
 */
export interface Display {
  /** The app's language; also formats amounts and country names. */
  language?: Language;
  currency: string;
  fees: { apple: number; google: number } | null;
  /** The app's last saved rate: one US dollar in [currency]. */
  savedRate: number | null;
  /** The RevenueCat project the webhook belongs to, when the app names it. */
  project?: string;
  /** The app's product names by store product id, when Settings gave any. */
  names: Record<string, string>;
  /** The project's icon URL, when the app has one, shown in the push. */
  icon?: string;
}

/** How many product names a webhook URL may carry, and how long each may be. */
const MAX_NAMES = 200;
const MAX_NAME = 60;
const MAX_ID = 200;
const MAX_NAMES_PARAM = 4096;

/**
 * `names=com.acme.pro%0APro%09com.acme.lite%0ALite`: the names Settings gave,
 * as `id`, a newline, then the name, one entry per product, entries split by
 * tabs (`PushNames` in `lib/services/push/push_names.dart`). Read and
 * dropped with the request: the URL is where they come from, and this worker
 * stores nothing.
 */
export function parseNames(raw: string | null): Record<string, string> {
  // A null prototype, so a product id like `__proto__` is just a key.
  const names = Object.create(null) as Record<string, string>;
  if (!raw || raw.length > MAX_NAMES_PARAM) return names;
  const entries = raw.split("\t");
  for (const entry of entries.slice(0, MAX_NAMES)) {
    const split = entry.indexOf("\n");
    if (split <= 0) continue;
    const id = entry.slice(0, split).trim();
    if (!id || id.length > MAX_ID || id in names) continue;
    const name = entry
      .slice(split + 1)
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, MAX_NAME)
      .trim();
    if (name) names[id] = name;
  }
  return names;
}

/** Longest icon URL worth carrying; store artwork links are far shorter. */
const MAX_ICON = 1024;

/**
 * `icon=https://…`: the project's icon, which the app takes from RevenueCat
 * and puts in its webhook URL so a push can show it. Only an https URL with
 * no spaces, quotes or control characters, so the notifier hands FCM an
 * address of the store's or RevenueCat's making, never one of its own. Read
 * and dropped with the request like the rest of the URL.
 */
export function parseIcon(raw: string | null): string | undefined {
  const url = raw?.trim();
  if (!url || url.length > MAX_ICON) return undefined;
  if (!url.startsWith("https://") || /[\s"'<>\\]/.test(url)) return undefined;
  try {
    if (new URL(url).protocol !== "https:") return undefined;
  } catch {
    return undefined;
  }
  return url;
}

export function parseDisplay(params: URLSearchParams): Display {
  const code = params.get("currency")?.toUpperCase();
  const currency = code && /^[A-Z]{3}$/.test(code) ? code : "USD";
  const [apple, google] = (params.get("fees") ?? "").split(",").map(Number);
  const fee = (n: number | undefined) => n !== undefined && Number.isFinite(n) && n >= 0 && n <= 100;
  const rate = Number(params.get("rate"));
  const project = params.get("project")?.replace(/\s+/g, " ").trim().slice(0, 60);
  const icon = parseIcon(params.get("icon"));
  return {
    language: parseLanguage(params.get("lang")),
    currency,
    fees: fee(apple) && fee(google) ? { apple: apple!, google: google! } : null,
    savedRate: Number.isFinite(rate) && rate > 0 ? rate : null,
    names: parseNames(params.get("names")),
    ...(project ? { project } : {}),
    ...(icon ? { icon } : {}),
  };
}

/** What's left of [usd] after the store's fee. */
export function afterFees(usd: number, store: unknown, display: Display): number {
  if (!display.fees) return usd;
  const percent =
    store === "APP_STORE" || store === "MAC_APP_STORE"
      ? display.fees.apple
      : store === "PLAY_STORE"
        ? display.fees.google
        : 0;
  return usd * (1 - percent / 100);
}

/** Exchange rates from US dollars, the same free source the app uses. */
const RATE_URLS = [
  "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json",
  "https://latest.currency-api.pages.dev/v1/currencies/usd.json",
];

/**
 * Rates change daily: refreshed after 6 hours, but kept when a refresh
 * fails, so the last good rate beats none.
 */
let cachedRates: { rates: Record<string, number>; at: number } | null = null;

export function forgetRates(): void {
  cachedRates = null;
}

/**
 * One US dollar in [display]'s currency: a fresh rate, else the last one
 * fetched, else the app's saved one; null leaves amounts in US dollars.
 */
export async function usdRate(display: Display): Promise<number | null> {
  const { currency } = display;
  if (currency === "USD") return 1;
  if (!cachedRates || Date.now() - cachedRates.at > 6 * 3600_000) {
    let fresh = false;
    for (const url of RATE_URLS) {
      try {
        const response = await fetch(url, { signal: AbortSignal.timeout(4000) });
        if (!response.ok) continue;
        const json = await response.json<{ usd?: Record<string, unknown> }>();
        const rates: Record<string, number> = {};
        for (const [code, rate] of Object.entries(json.usd ?? {})) {
          if (typeof rate === "number" && rate > 0) rates[code.toUpperCase()] = rate;
        }
        if (Object.keys(rates).length) {
          cachedRates = { rates, at: Date.now() };
          fresh = true;
          break;
        }
      } catch {
        // Try the next source.
      }
    }
    // Keep the old rates, and try again in 10 minutes, not on every event.
    if (!fresh && cachedRates) cachedRates.at = Date.now() - 6 * 3600_000 + 600_000;
  }
  return cachedRates?.rates[currency] ?? display.savedRate;
}
