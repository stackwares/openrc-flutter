/**
 * Ported from Kedi EventNotification.swift (notification title/body from RC webhook event).
 */

export interface RCWebhookEvent {
  id?: string;
  app_id?: string;
  app_user_id?: string;
  type?: string;
  period_type?: string;
  environment?: string;
  event_timestamp_ms?: number;
  purchased_at_ms?: number;
  price?: number;
  product_id?: string;
  new_product_id?: string;
  store?: string;
  country_code?: string;
  offer_code?: string;
  is_trial_conversion?: boolean;
  cancel_reason?: string;
  expiration_reason?: string;
}

export enum EventNotificationType {
  initialPurchase,
  oneTimePurchase,
  renewalExisting,
  renewalLapsed,
  trial,
  conversion,
  resubscription,
  unsubscription,
  expiration,
  billingIssue,
  refund,
  transfer,
  productChange,
  test,
  unknown,
}

function countryFlagEmoji(code: string | undefined): string {
  if (!code || code.length !== 2) return "";
  const cc = code.toUpperCase();
  const A = 0x1f1e6;
  const pts = [...cc].map((c) => A + (c.charCodeAt(0) - 65));
  return String.fromCodePoint(...pts);
}

function countryFlagAndName(code: string | undefined): string | undefined {
  if (!code) return undefined;
  const flag = countryFlagEmoji(code);
  const u = code.toUpperCase();
  return flag ? `${flag} ${u}` : u;
}

function classifyEvent(data: RCWebhookEvent): EventNotificationType {
  const t = data.type ?? "";
  switch (t) {
    case "INITIAL_PURCHASE":
      return data.period_type === "TRIAL"
        ? EventNotificationType.trial
        : EventNotificationType.initialPurchase;
    case "NON_RENEWING_PURCHASE":
      return EventNotificationType.oneTimePurchase;
    case "RENEWAL": {
      if (data.is_trial_conversion === true) return EventNotificationType.conversion;
      const diffMs =
        (data.event_timestamp_ms ?? 0) - (data.purchased_at_ms ?? 0);
      return diffMs >= 0
        ? EventNotificationType.renewalLapsed
        : EventNotificationType.renewalExisting;
    }
    case "CANCELLATION":
      return data.cancel_reason === "CUSTOMER_SUPPORT"
        ? EventNotificationType.refund
        : EventNotificationType.unsubscription;
    case "UNCANCELLATION":
      return EventNotificationType.resubscription;
    case "EXPIRATION":
      return EventNotificationType.expiration;
    case "PRODUCT_CHANGE":
      return EventNotificationType.productChange;
    case "BILLING_ISSUE":
      return EventNotificationType.billingIssue;
    case "TRANSFER":
      return EventNotificationType.transfer;
    case "TEST":
      return EventNotificationType.test;
    default:
      return EventNotificationType.unknown;
  }
}

function typeEmoji(type: EventNotificationType): string {
  switch (type) {
    case EventNotificationType.initialPurchase:
      return "🔵";
    case EventNotificationType.oneTimePurchase:
      return "🟣";
    case EventNotificationType.renewalExisting:
      return "🟢";
    case EventNotificationType.renewalLapsed:
      return "🔵";
    case EventNotificationType.trial:
      return "🟠";
    case EventNotificationType.conversion:
      return "🔵";
    case EventNotificationType.resubscription:
      return "🟢";
    case EventNotificationType.unsubscription:
      return "🟡";
    case EventNotificationType.expiration:
      return "🔴";
    case EventNotificationType.billingIssue:
      return "🔴";
    case EventNotificationType.refund:
      return "🔴";
    case EventNotificationType.transfer:
      return "⚪";
    case EventNotificationType.productChange:
      return "⚪";
    case EventNotificationType.test:
      return "⚪";
    case EventNotificationType.unknown:
      return "⚪";
  }
}

function typeText(type: EventNotificationType): string {
  switch (type) {
    case EventNotificationType.initialPurchase:
      return "New Subscription";
    case EventNotificationType.oneTimePurchase:
      return "One-Time Purchase";
    case EventNotificationType.renewalExisting:
      return "Renewal (Existing)";
    case EventNotificationType.renewalLapsed:
      return "Renewal (Lapsed)";
    case EventNotificationType.trial:
      return "Trial";
    case EventNotificationType.conversion:
      return "Conversion";
    case EventNotificationType.resubscription:
      return "Resubscription";
    case EventNotificationType.unsubscription:
      return "Unsubscription";
    case EventNotificationType.expiration:
      return "Expiration";
    case EventNotificationType.billingIssue:
      return "Billing Issue";
    case EventNotificationType.refund:
      return "Refund";
    case EventNotificationType.transfer:
      return "Transfer";
    case EventNotificationType.productChange:
      return "Product Change";
    case EventNotificationType.test:
      return "Test";
    case EventNotificationType.unknown:
      return "Unknown";
  }
}

function formatUsd(price: number | undefined): string | undefined {
  if (price === undefined || price === 0) return undefined;
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
  }).format(price);
}

export function buildNotificationCopy(data: RCWebhookEvent): {
  title: string;
  body: string;
} {
  const kind = classifyEvent(data);
  const price = formatUsd(data.price);
  const title = [typeEmoji(kind) + " " + typeText(kind), price]
    .filter(Boolean)
    .join(" • ");

  let productIdentifier: string | undefined;
  if (data.product_id && data.new_product_id) {
    productIdentifier = `${data.product_id} → ${data.new_product_id}`;
  } else {
    productIdentifier = data.product_id;
  }

  const store = data.store?.replace(/_/g, " ");
  const storeCap =
    store && store.length > 0
      ? store.charAt(0).toUpperCase() + store.slice(1).toLowerCase()
      : undefined;

  const body = [
    countryFlagAndName(data.country_code),
    data.app_id,
    productIdentifier,
    storeCap,
    data.offer_code,
    data.environment && data.environment !== "PRODUCTION"
      ? data.environment.charAt(0) + data.environment.slice(1).toLowerCase()
      : undefined,
  ]
    .filter(Boolean)
    .join(" • ");

  return {title, body: body || "RevenueCat event"};
}
