/**
 * How a device shows amounts, as the app puts it in the webhook URL:
 * `currency=EUR` for its display currency and `fees=15,30` (App Store, then
 * Google Play, in percent) when it subtracts store fees, plus `rate`, the
 * app's last saved rate for that currency, in case no fresh one can be had.
 * Like the app (`lib/core/utils/store_commission.dart`), other stores keep
 * no fee.
 */
export interface Display {
  currency: string;
  fees: { apple: number; google: number } | null;
  /** The app's last saved rate: one US dollar in [currency]. */
  savedRate: number | null;
}

export function parseDisplay(params: URLSearchParams): Display {
  const code = params.get("currency")?.toUpperCase();
  const currency = code && /^[A-Z]{3}$/.test(code) ? code : "USD";
  const [apple, google] = (params.get("fees") ?? "").split(",").map(Number);
  const fee = (n: number | undefined) => n !== undefined && Number.isFinite(n) && n >= 0 && n <= 100;
  const rate = Number(params.get("rate"));
  return {
    currency,
    fees: fee(apple) && fee(google) ? { apple: apple!, google: google! } : null,
    savedRate: Number.isFinite(rate) && rate > 0 ? rate : null,
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
