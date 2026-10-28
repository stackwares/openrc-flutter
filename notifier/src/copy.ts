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
  purchased_at_ms?: unknown;
  expiration_at_ms?: unknown;
}

export interface NotificationCopy {
  title: string;
  body: string;
}

const STORES: Record<string, string> = {
  APP_STORE: "Apple",
  MAC_APP_STORE: "Apple",
  PLAY_STORE: "Google",
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

/** Capitalizes each word (“New Subscription”), leaving emojis untouched. */
function titleCase(value: string, language: Language): string {
  return value.replace(/(^|\s)(\p{L})/gu, (_, pre: string, ch: string) => pre + ch.toLocaleUpperCase(language));
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

function country(code: unknown): string | undefined {
  const cc = text(code)?.toUpperCase();
  if (!cc || !/^[A-Z]{2}$/.test(cc)) return undefined;
  const flag = String.fromCodePoint(...[...cc].map((c) => 0x1f1e6 + c.charCodeAt(0) - 65));
  return `${flag} ${cc}`;
}

/** Apple's and Google's stores with their platforms; others keep their names. */
const STORE_EMOJI: Record<string, string> = {
  APP_STORE: "iOS",
  MAC_APP_STORE: "macOS",
  PLAY_STORE: "👾Android",
};

function store(value: unknown): string | undefined {
  const id = text(value);
  if (!id) return undefined;
  return STORE_EMOJI[id] ?? STORES[id] ?? id.charAt(0) + id.slice(1).toLowerCase().replace(/_/g, " ");
}

/** Events whose dates describe one billing period. */
const PERIOD_EVENTS: Record<string, true> = {
  INITIAL_PURCHASE: true,
  RENEWAL: true,
  NON_RENEWING_PURCHASE: true,
  CANCELLATION: true,
  UNCANCELLATION: true,
  EXPIRATION: true,
};

/**
 * The plan's length, from the store's own dates: `Weekly`, `Monthly`,
 * `Annual`, `3 months`, `14 days`, mirroring `planLengthLabel` in
 * `lib/core/utils/plan_display.dart`. Sandbox purchases shorten periods to
 * minutes, and trials or intro offers expire when the offer ends, not when
 * the plan does, so neither is labelled.
 */
function period(event: WebhookEvent, s: Strings, language: Language): string | undefined {
  if (event.environment === "SANDBOX") return undefined;
  if (event.period_type === "TRIAL" || event.period_type === "INTRO") return undefined;
  if (typeof event.type !== "string" || !PERIOD_EVENTS[event.type]) return undefined;
  const purchased = typeof event.purchased_at_ms === "number" ? event.purchased_at_ms : NaN;
  const expires = typeof event.expiration_at_ms === "number" ? event.expiration_at_ms : NaN;
  if (!Number.isFinite(purchased) || !Number.isFinite(expires) || expires <= purchased) {
    return undefined;
  }
  const days = Math.round((expires - purchased) / 86_400_000);
  if (days <= 0) return undefined;
  if (days >= 6 && days <= 8) return s.weekly;
  if (days >= 358 && days <= 372) return s.annual;
  for (const months of [1, 2, 3, 6]) {
    if (Math.abs(days - months * 30.44) <= months * 2 + 1) {
      return months === 1 ? s.monthly : unitLabel(months, "month", language);
    }
  }
  return unitLabel(days, "day", language);
}

/**
 * True when [name] already says the plan length, so a body doesn't read
 * `Monthly · Monthly` or `Yearly · Annual`, mirroring `_nameStatesLength` in
 * `lib/core/utils/plan_display.dart`.
 */
function statesLength(name: string, length: string, s: Strings): boolean {
  const n = name.trim().toLowerCase();
  const l = length.trim().toLowerCase();
  if (!n) return false;
  if (n === l) return true;
  const kind = s.periodNames[n];
  if (kind !== "annual" && kind !== "monthly" && kind !== "weekly") return false;
  const label = kind === "annual" ? s.annual : kind === "monthly" ? s.monthly : s.weekly;
  return label.trim().toLowerCase() === l;
}

/** `3 months`, `14 days`, pluralized for [language]. */
function unitLabel(count: number, unit: "month" | "day", language: Language): string {
  try {
    return new Intl.NumberFormat(language, { style: "unit", unit, unitDisplay: "long" }).format(count);
  } catch {
    return `${count} ${unit}${count === 1 ? "" : "s"}`;
  }
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
  display: Display = { currency: "USD", fees: null, savedRate: null, names: {} },
  rate: number | null = 1,
): NotificationCopy | null {
  const language = display.language ?? "en";
  const s = STRINGS[language];
  const name = label(event, s);
  if (!name) return null;
  const titleName = titleCase(name, language);
  if (event.type === "TEST") {
    return { title: titleName, body: display.project ? `${display.project} · ${s.testBody}` : s.testBody };
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
  const length = period(event, s, language);
  // The name Settings gave the product, else the store's own id.
  const nameOf = (id: string) => display.names[id] ?? id;
  // `Pro · Monthly`, but `Monthly` when the name already says the length.
  const withLength = (id: string) => {
    const shown = nameOf(id);
    return length && !statesLength(shown, length, s) ? `${shown} · ${length}` : shown;
  };
  const plan =
    product && newProduct
      ? `${nameOf(product)} → ${nameOf(newProduct)}`
      : product
        ? withLength(product)
        : length;
  const body = [
    display.project,
    plan,
    paid,
    country(event.country_code),
    store(event.store),
    event.environment === "SANDBOX" ? s.sandbox : undefined,
  ].filter(Boolean).join(" · ");

  return {
    title: shown ? `${titleName} · ${shown}` : titleName,
    body: body || s.fallbackBody,
  };
}
