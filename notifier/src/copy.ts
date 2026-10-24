import { afterFees, type Display } from "./display";
import { STRINGS, type Language, type Strings } from "./strings";

/**
 * Notification text for a RevenueCat webhook event. Field reference:
 * https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields
 */

/** The fields of a webhook event that notifications use. */
export interface WebhookEvent {
  id?: unknown;
  type?: unknown;
  transaction_id?: unknown;
  period_type?: unknown;
  environment?: unknown;
  product_id?: unknown;
  new_product_id?: unknown;
  store?: unknown;
  country_code?: unknown;
  price?: unknown;
  price_in_purchased_currency?: unknown;
  currency?: unknown;
  is_trial_conversion?: unknown;
  cancel_reason?: unknown;
}

export interface NotificationCopy {
  title: string;
  body: string;
}

const STORES: Record<string, string> = {
  APP_STORE: "App Store",
  MAC_APP_STORE: "Mac App Store",
  PLAY_STORE: "Google Play",
  AMAZON: "Amazon",
  STRIPE: "Stripe",
  RC_BILLING: "Web Billing",
  PADDLE: "Paddle",
  ROKU: "Roku",
  PROMOTIONAL: "Promotional",
  EXTERNAL: "External",
  TEST_STORE: "Test Store",
};

/**
 * The kinds of notification someone can choose, as the app names them in a
 * webhook URL's `notify` parameter (`lib/services/push/push_kinds.dart`).
 */
export const KINDS = [
  "new",
  "trial",
  "conversion",
  "renewal",
  "purchase",
  "resubscribe",
  "cancel",
  "refund",
  "billing",
  "expire",
  "change",
] as const;

export type Kind = (typeof KINDS)[number];

/** Which kind [event] is, or null for events outside every kind. */
export function kindOf(event: WebhookEvent): Kind | null {
  switch (event.type) {
    case "INITIAL_PURCHASE":
      return event.period_type === "TRIAL" ? "trial" : "new";
    case "NON_RENEWING_PURCHASE":
      return "purchase";
    case "RENEWAL":
      return event.is_trial_conversion === true ? "conversion" : "renewal";
    case "UNCANCELLATION":
      return "resubscribe";
    case "CANCELLATION":
      return event.cancel_reason === "CUSTOMER_SUPPORT" ? "refund" : "cancel";
    case "REFUND_REVERSED":
      return "refund";
    case "BILLING_ISSUE":
      return "billing";
    case "EXPIRATION":
      return "expire";
    case "PRODUCT_CHANGE":
    case "SUBSCRIPTION_PAUSED":
    case "SUBSCRIPTION_EXTENDED":
      return "change";
    default:
      return null;
  }
}

/**
 * The kinds a `notify` parameter asks for: null when it's missing, which
 * means every kind. Unknown names are ignored.
 */
export function parseKinds(param: string | null): Set<Kind> | null {
  if (param === null) return null;
  const known = new Set<string>(KINDS);
  return new Set(param.split(",").filter((k): k is Kind => known.has(k)));
}

/**
 * What a notification calls an event, or null for events that aren't about
 * a customer's purchase (aliases, experiments, virtual currency, invoices).
 */
function label(event: WebhookEvent, s: Strings): string | null {
  const trial = event.period_type === "TRIAL";
  switch (event.type) {
    case "INITIAL_PURCHASE":
      return trial ? `🟠 ${s.trialStarted}` : `🔵 ${s.newSubscription}`;
    case "NON_RENEWING_PURCHASE":
      return `🟣 ${s.purchase}`;
    case "RENEWAL":
      return event.is_trial_conversion === true ? `🔵 ${s.trialConverted}` : `🟢 ${s.renewal}`;
    case "PRODUCT_CHANGE":
      return `⚪ ${s.planChange}`;
    case "CANCELLATION":
      if (event.cancel_reason === "CUSTOMER_SUPPORT") return `🔴 ${s.refund}`;
      return trial ? `🟡 ${s.trialCancelled}` : `🟡 ${s.cancellation}`;
    case "UNCANCELLATION":
      return `🟢 ${s.resubscribed}`;
    case "EXPIRATION":
      return `🔴 ${s.expired}`;
    case "BILLING_ISSUE":
      return `🔴 ${s.billingIssue}`;
    case "SUBSCRIPTION_PAUSED":
      return `⚪ ${s.paused}`;
    case "SUBSCRIPTION_EXTENDED":
      return `⚪ ${s.extended}`;
    case "REFUND_REVERSED":
      return `🟢 ${s.refundReversed}`;
    case "TEST":
      return `⚪ ${s.test}`;
    default:
      return null;
  }
}

function text(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function money(amount: unknown, currency: string, language: Language): string | undefined {
  if (typeof amount !== "number" || !Number.isFinite(amount) || amount === 0) {
    return undefined;
  }
  try {
    return new Intl.NumberFormat(language, { style: "currency", currency }).format(amount);
  } catch {
    return undefined;
  }
}

function country(code: unknown, language: Language): string | undefined {
  const cc = text(code)?.toUpperCase();
  if (!cc || !/^[A-Z]{2}$/.test(cc)) return undefined;
  const flag = String.fromCodePoint(...[...cc].map((c) => 0x1f1e6 + c.charCodeAt(0) - 65));
  let name = cc;
  try {
    name = new Intl.DisplayNames([language, "en"], { type: "region" }).of(cc) ?? cc;
  } catch {}
  return `${flag} ${name}`;
}

function store(value: unknown): string | undefined {
  const id = text(value);
  if (!id) return undefined;
  return STORES[id] ?? id.charAt(0) + id.slice(1).toLowerCase().replace(/_/g, " ");
}

/**
 * Title and body for [event] in the device's language, or null when it
 * shouldn't notify. The title's
 * amount follows the device's [display]: after store fees when it subtracts
 * them, and in its currency at [rate] (one US dollar in it); without a rate
 * it stays in US dollars.
 */
export function notificationFor(
  event: WebhookEvent,
  display: Display = { currency: "USD", fees: null, savedRate: null },
  rate: number | null = 1,
): NotificationCopy | null {
  const language = display.language ?? "en";
  const s = STRINGS[language];
  const name = label(event, s);
  if (!name) return null;
  if (event.type === "TEST") {
    return { title: name, body: s.testBody };
  }

  const net = typeof event.price === "number" ? afterFees(event.price, event.store, display) : undefined;
  const shown = rate !== null && display.currency !== "USD"
    ? money(net !== undefined ? net * rate : undefined, display.currency, language)
    : money(net, "USD", language);
  const currency = text(event.currency)?.toUpperCase();
  // What the customer paid, when it wasn't in the currency shown.
  const shownCurrency = rate !== null ? display.currency : "USD";
  const paid = currency && currency !== shownCurrency
    ? money(event.price_in_purchased_currency, currency, language)
    : undefined;

  const product = text(event.product_id);
  const newProduct = text(event.new_product_id);
  const body = [
    product && newProduct ? `${product} → ${newProduct}` : product,
    paid,
    country(event.country_code, language),
    store(event.store),
    event.environment === "SANDBOX" ? s.sandbox : undefined,
  ].filter(Boolean).join(" · ");

  return {
    title: shown ? `${name} · ${shown}` : name,
    body: body || s.fallbackBody,
  };
}
