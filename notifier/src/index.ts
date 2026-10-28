/**
 * OpenRC notifier: turns RevenueCat webhooks into push notifications.
 * Stateless: nothing is stored. Each event is read in memory to write the
 * notification and then dropped; bodies, secrets and topics are never
 * logged.
 */

import { kindOf, notificationFor, parseKinds, type Kind, type WebhookEvent } from "./copy";
import { parseDisplay, usdRate, type Display } from "./display";
import { FcmError, parseServiceAccount, sendToTopic, setTopicSubscription } from "./fcm";
import { parseSecret, topicFor } from "./topic";

/** `/revenuecat`, or `/revenuecat/<device tag>`. */
const WEBHOOK_PATH = /^\/revenuecat(?:\/[A-Za-z0-9_-]{1,64})?$/;

/** A Firebase installation id or FCM registration token. */
const REGISTRATION = /^[A-Za-z0-9_:-]{10,4096}$/;

/**
 * Browsers call `/subscribe` from the web app. Its authorization is the
 * device's secret, not a cookie, so any origin may ask.
 */
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
  "Access-Control-Max-Age": "86400",
};

/** Webhook events are a few kilobytes; anything far bigger isn't one. */
const MAX_BODY_BYTES = 64 * 1024;

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/" && request.method === "GET") {
      return Response.json({ service: "openrc-notifier", ok: true });
    }
    if (url.pathname === "/subscribe" || url.pathname === "/unsubscribe") {
      if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
      if (request.method !== "POST") {
        return Response.json({ error: "method_not_allowed" }, { status: 405, headers: CORS });
      }
      const response = await subscription(request, env, url.pathname === "/subscribe");
      for (const [name, value] of Object.entries(CORS)) response.headers.set(name, value);
      return response;
    }
    // Each device's webhook has its own URL (RevenueCat allows one webhook
    // per URL in a project); the last segment is only a label.
    if (!WEBHOOK_PATH.test(url.pathname)) {
      return Response.json({ error: "not_found" }, { status: 404 });
    }
    if (request.method !== "POST") {
      return Response.json({ error: "method_not_allowed" }, { status: 405 });
    }
    return webhook(
      request,
      env,
      parseKinds(url.searchParams.get("notify")),
      parseDisplay(url.searchParams),
    );
  },
} satisfies ExportedHandler<Env>;

/** [kinds]: what this webhook's device chose to hear about; null for all. */
async function webhook(
  request: Request,
  env: Env,
  kinds: Set<Kind> | null,
  display: Display,
): Promise<Response> {
  const secret = parseSecret(request.headers.get("Authorization"));
  if (!secret) return Response.json({ error: "unauthorized" }, { status: 401 });

  // Fails closed: without credentials nothing can be delivered, so say so
  // and let RevenueCat retry rather than report success.
  const account = parseServiceAccount(env.FCM_SERVICE_ACCOUNT);
  if (!account) {
    console.error(JSON.stringify({ message: "FCM_SERVICE_ACCOUNT is missing or invalid" }));
    return Response.json({ error: "not_configured" }, { status: 500 });
  }

  const declared = Number(request.headers.get("Content-Length") ?? 0);
  if (declared > MAX_BODY_BYTES) return tooLarge();
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) return tooLarge();

  let event: WebhookEvent | undefined;
  try {
    const body = JSON.parse(raw) as { event?: unknown };
    if (body.event && typeof body.event === "object") event = body.event as WebhookEvent;
  } catch {
    return Response.json({ error: "invalid_json" }, { status: 400 });
  }

  const copy = event
    ? notificationFor(event, display, await usdRate(display))
    : null;
  // RevenueCat's test event always gets through, so setup can be checked.
  const kind = event ? kindOf(event) : null;
  const chosen = event?.type === "TEST" || kinds === null || (kind !== null && kinds.has(kind));
  // Answered with 200 so RevenueCat doesn't retry events that never notify.
  if (!event || !copy || !chosen) return Response.json({ sent: false });

  const id = typeof event.id === "string" && event.id.length <= 64 ? event.id : undefined;
  // The store's transaction id lets a tap open the transaction in the app.
  const transactionId =
    typeof event.transaction_id === "string" && event.transaction_id.length <= 200
      ? event.transaction_id
      : undefined;
  try {
    await sendToTopic(account, {
      topic: await topicFor(secret),
      ...copy,
      collapseId: id,
      transactionId,
      imageUrl: display.icon,
    });
  } catch (error) {
    console.error(
      JSON.stringify(
        error instanceof FcmError
          ? { message: "FCM call failed", stage: error.stage, status: error.status }
          : { message: "FCM unreachable" },
      ),
    );
    // RevenueCat retries anything but a 200, with backoff, for about 80 min.
    return Response.json({ error: "delivery_failed" }, { status: 502 });
  }
  return Response.json({ sent: true });
}

/**
 * Puts a browser on its device's topic, or takes it off. Phones subscribe
 * themselves; browsers can't, so they ask here with their secret.
 */
async function subscription(request: Request, env: Env, subscribe: boolean): Promise<Response> {
  const secret = parseSecret(request.headers.get("Authorization"));
  if (!secret) return Response.json({ error: "unauthorized" }, { status: 401 });
  const account = parseServiceAccount(env.FCM_SERVICE_ACCOUNT);
  if (!account) {
    console.error(JSON.stringify({ message: "FCM_SERVICE_ACCOUNT is missing or invalid" }));
    return Response.json({ error: "not_configured" }, { status: 500 });
  }
  let registration: unknown;
  try {
    const raw = await request.text();
    if (raw.length > 8 * 1024) return tooLarge();
    registration = (JSON.parse(raw) as { registration?: unknown }).registration;
  } catch {
    return Response.json({ error: "invalid_json" }, { status: 400 });
  }
  if (typeof registration !== "string" || !REGISTRATION.test(registration)) {
    return Response.json({ error: "invalid_registration" }, { status: 400 });
  }
  try {
    await setTopicSubscription(account, registration, await topicFor(secret), subscribe);
  } catch (error) {
    console.error(
      JSON.stringify(
        error instanceof FcmError
          ? { message: "FCM call failed", stage: error.stage, status: error.status }
          : { message: "FCM unreachable" },
      ),
    );
    return Response.json({ error: "subscription_failed" }, { status: 502 });
  }
  return Response.json({ subscribed: subscribe });
}

function tooLarge(): Response {
  return Response.json({ error: "too_large" }, { status: 413 });
}
