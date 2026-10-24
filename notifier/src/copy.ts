import { afterFees, type Display } from "./display";

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
function label(event: WebhookEvent): string | null {
  const trial = event.period_type === "TRIAL";
  switch (event.type) {
    case "INITIAL_PURCHASE":
      return trial ? "🟠 Trial started" : "🔵 New subscription";
    case "NON_RENEWING_PURCHASE":
      return "🟣 Purchase";
    case "RENEWAL":
      return event.is_trial_conversion === true ? "🔵 Trial converted" : "🟢 Renewal";
    case "PRODUCT_CHANGE":
      return "⚪ Plan change";
    case "CANCELLATION":
      if (event.cancel_reason === "CUSTOMER_SUPPORT") return "🔴 Refund";
      return trial ? "🟡 Trial cancelled" : "🟡 Cancellation";
    case "UNCANCELLATION":
      return "🟢 Resubscribed";
    case "EXPIRATION":
      return "🔴 Expired";
    case "BILLING_ISSUE":
      return "🔴 Billing issue";
    case "SUBSCRIPTION_PAUSED":
      return "⚪ Subscription paused";
    case "SUBSCRIPTION_EXTENDED":
      return "⚪ Subscription extended";
    case "REFUND_REVERSED":
      return "🟢 Refund reversed";
    case "TEST":
      return "⚪ Test notification";
    default:
      return null;
  }
}

function text(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function money(amount: unknown, currency: string): string | undefined {
  if (typeof amount !== "number" || !Number.isFinite(amount) || amount === 0) {
    return undefined;
  }
  try {
    return new Intl.NumberFormat("en-US", { style: "currency", currency }).format(amount);
  } catch {
    return undefined;
  }
}

function country(code: unknown): string | undefined {
  const cc = text(code)?.toUpperCase();
  if (!cc || !/^[A-Z]{2}$/.test(cc)) return undefined;
  const flag = String.fromCodePoint(...[...cc].map((c) => 0x1f1e6 + c.charCodeAt(0) - 65));
  let name = cc;
  try {
    name = new Intl.DisplayNames(["en"], { type: "region" }).of(cc) ?? cc;
  } catch {}
  return `${flag} ${name}`;
}

function store(value: unknown): string | undefined {
  const id = text(value);
  if (!id) return undefined;
  return STORES[id] ?? id.charAt(0) + id.slice(1).toLowerCase().replace(/_/g, " ");
}

/**
 * Title and body for [event], or null when it shouldn't notify. The title's
 * amount follows the device's [display]: after store fees when it subtracts
 * them, and in its currency at [rate] (one US dollar in it); without a rate
 * it stays in US dollars.
 */
export function notificationFor(
  event: WebhookEvent,
  display: Display = { currency: "USD", fees: null, savedRate: null },
  rate: number | null = 1,
): NotificationCopy | null {
  const name = label(event);
  if (!name) return null;
  if (event.type === "TEST") {
    return { title: name, body: "RevenueCat can reach this device." };
  }

  const net = typeof event.price === "number" ? afterFees(event.price, event.store, display) : undefined;
  const shown = rate !== null && display.currency !== "USD"
    ? money(net !== undefined ? net * rate : undefined, display.currency)
    : money(net, "USD");
  const currency = text(event.currency)?.toUpperCase();
  // What the customer paid, when it wasn't in the currency shown.
  const shownCurrency = rate !== null ? display.currency : "USD";
  const paid = currency && currency !== shownCurrency
    ? money(event.price_in_purchased_currency, currency)
    : undefined;

  const product = text(event.product_id);
  const newProduct = text(event.new_product_id);
  const body = [
    product && newProduct ? `${product} → ${newProduct}` : product,
    paid,
    country(event.country_code),
    store(event.store),
    event.environment === "SANDBOX" ? "Sandbox" : undefined,
  ].filter(Boolean).join(" · ");

  return {
    title: shown ? `${name} · ${shown}` : name,
    body: body || "RevenueCat event",
  };
}
