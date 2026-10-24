import { env } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { kindOf, notificationFor, parseKinds } from "../src/copy";
import { forgetAccessToken } from "../src/fcm";
import worker from "../src/index";
import { parseSecret, topicFor } from "../src/topic";

const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

// The app's tests use the same vectors (test/push_channel_test.dart).
const SECRET = "A".repeat(43);
const TOPIC = "openrc-OWRekNBZkzKbFFTQk_uwY8KokTiMuahzVgMI9gff0J8";

let testEnv: Env;
let publicKey: CryptoKey;

beforeAll(async () => {
  const pair = (await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  publicKey = pair.publicKey;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
  testEnv = {
    ...env,
    FCM_SERVICE_ACCOUNT: JSON.stringify({
      project_id: "openrc-test",
      client_email: "notifier@openrc-test.iam.gserviceaccount.com",
      private_key: pem,
    }),
  };
});

beforeEach(() => forgetAccessToken());
afterEach(() => vi.restoreAllMocks());

function call(path: string, init: RequestInit<IncomingRequestCfProperties> = {}, e = testEnv) {
  return worker.fetch(new IncomingRequest(`https://openrc-notifier.example.workers.dev${path}`, init), e);
}

function webhook(event: object, authorization: string | null = `Bearer ${SECRET}`) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (authorization !== null) headers.Authorization = authorization;
  return call("/revenuecat", {
    method: "POST",
    headers,
    body: JSON.stringify({ api_version: "1.0", event }),
  });
}

/** Google's token endpoint and FCM, answering with [sendStatus]. */
function mockGoogle(sendStatus = 200) {
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    const url = input instanceof Request ? input.url : String(input);
    if (url === "https://oauth2.googleapis.com/token") {
      return Response.json({ access_token: "ya29.test", expires_in: 3600 });
    }
    if (url.startsWith("https://fcm.googleapis.com/")) {
      return Response.json({ name: "projects/openrc-test/messages/1" }, { status: sendStatus });
    }
    throw new Error(`unexpected fetch ${url}`);
  });
}

function requestsTo(spy: ReturnType<typeof mockGoogle>, prefix: string) {
  return spy.mock.calls.filter(([input]) => String(input).startsWith(prefix));
}

const PURCHASE = {
  id: "9f1c3b2a-0000-4000-8000-000000000001",
  type: "INITIAL_PURCHASE",
  period_type: "NORMAL",
  environment: "PRODUCTION",
  product_id: "pro_monthly",
  store: "APP_STORE",
  country_code: "DE",
  transaction_id: "2000000123456789",
  price: 10.83,
  price_in_purchased_currency: 9.99,
  currency: "EUR",
};

describe("routes", () => {
  it("answers a health check", async () => {
    const res = await call("/");
    expect(await res.json()).toEqual({ service: "openrc-notifier", ok: true });
  });

  it("serves only the webhook", async () => {
    expect((await call("/v1/developers/me")).status).toBe(404);
    expect((await call("/revenuecat")).status).toBe(405);
    expect((await call("/revenuecat/a/b")).status).toBe(404);
    expect((await call("/revenuecat/bad%20tag")).status).toBe(404);
  });

  it("takes each device's own URL", async () => {
    mockGoogle();
    const res = await call("/revenuecat/OWRekN", {
      method: "POST",
      headers: { Authorization: `Bearer ${SECRET}` },
      body: JSON.stringify({ event: PURCHASE }),
    });
    expect(res.status).toBe(200);
  });
});

describe("webhook", () => {
  it("refuses requests without a valid secret, before anything else", async () => {
    const spy = mockGoogle();
    for (const auth of [null, "", "Bearer", "Bearer short", `Basic ${SECRET}`, `Bearer ${SECRET}x`]) {
      expect((await webhook(PURCHASE, auth)).status, String(auth)).toBe(401);
    }
    expect(spy).not.toHaveBeenCalled();
  });

  it("fails closed without credentials, so RevenueCat retries", async () => {
    const spy = mockGoogle();
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    const res = await call(
      "/revenuecat",
      { method: "POST", headers: { Authorization: SECRET }, body: "{}" },
      { ...testEnv, FCM_SERVICE_ACCOUNT: "" },
    );
    expect(res.status).toBe(500);
    expect(spy).not.toHaveBeenCalled();
    expect(error).toHaveBeenCalledOnce();
  });

  it("sends the event to the secret's topic", async () => {
    const spy = mockGoogle();
    const res = await webhook(PURCHASE);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ sent: true });

    const [send] = requestsTo(spy, "https://fcm.googleapis.com/");
    expect(String(send[0])).toBe("https://fcm.googleapis.com/v1/projects/openrc-test/messages:send");
    const init = send[1]!;
    expect(new Headers(init.headers).get("Authorization")).toBe("Bearer ya29.test");
    const { message } = JSON.parse(String(init.body));
    expect(message.topic).toBe(TOPIC);
    expect(message.notification).toEqual({
      title: "🔵 New subscription · $10.83",
      body: "pro_monthly · €9.99 · 🇩🇪 Germany · App Store",
    });
    // Only the store's transaction id, so a tap can open the transaction.
    expect(message.data).toEqual({
      source: "revenuecat",
      transaction_id: "2000000123456789",
      event_id: PURCHASE.id,
    });
    expect(message.android.notification.tag).toBe(PURCHASE.id);
    expect(message.apns.headers["apns-collapse-id"]).toBe(PURCHASE.id);
  });

  it("accepts the secret with or without Bearer", async () => {
    mockGoogle();
    expect((await webhook(PURCHASE, SECRET)).status).toBe(200);
    expect((await webhook(PURCHASE, ` bearer  ${SECRET} `)).status).toBe(200);
  });

  it("signs in to Google with the service account, once per token", async () => {
    const spy = mockGoogle();
    await webhook(PURCHASE);
    await webhook({ ...PURCHASE, type: "RENEWAL" });

    const tokens = requestsTo(spy, "https://oauth2.googleapis.com/");
    expect(tokens).toHaveLength(1);
    expect(requestsTo(spy, "https://fcm.googleapis.com/")).toHaveLength(2);

    const form = new URLSearchParams(String(tokens[0][1]!.body));
    expect(form.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
    const [header, claims, signature] = form.get("assertion")!.split(".");
    const decode = (part: string) =>
      Uint8Array.from(atob(part.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
    expect(JSON.parse(new TextDecoder().decode(decode(header)))).toEqual({ alg: "RS256", typ: "JWT" });
    expect(JSON.parse(new TextDecoder().decode(decode(claims)))).toMatchObject({
      iss: "notifier@openrc-test.iam.gserviceaccount.com",
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
    });
    const valid = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      publicKey,
      decode(signature),
      new TextEncoder().encode(`${header}.${claims}`),
    );
    expect(valid).toBe(true);
  });

  it("answers 200 without sending for events that don't notify", async () => {
    const spy = mockGoogle();
    for (const event of [{ type: "SUBSCRIBER_ALIAS" }, { type: "EXPERIMENT_ENROLLMENT" }, {}]) {
      const res = await webhook(event);
      expect(res.status).toBe(200);
      expect(await res.json()).toEqual({ sent: false });
    }
    const noEvent = await call("/revenuecat", {
      method: "POST",
      headers: { Authorization: SECRET },
      body: JSON.stringify({ api_version: "1.0" }),
    });
    expect(noEvent.status).toBe(200);
    expect(spy).not.toHaveBeenCalled();
  });

  it("rejects bodies that aren't JSON or are far too big", async () => {
    mockGoogle();
    const bad = await call("/revenuecat", { method: "POST", headers: { Authorization: SECRET }, body: "{" });
    expect(bad.status).toBe(400);
    const big = await call("/revenuecat", {
      method: "POST",
      headers: { Authorization: SECRET },
      body: JSON.stringify({ event: { type: "TEST", pad: "x".repeat(70 * 1024) } }),
    });
    expect(big.status).toBe(413);
  });

  it("reports failed deliveries for a retry, logging only the status", async () => {
    mockGoogle(503);
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    const res = await webhook(PURCHASE);
    expect(res.status).toBe(502);
    const logged = error.mock.calls.flat().join(" ");
    expect(logged).toContain("503");
    for (const secret of [SECRET, TOPIC, "pro_monthly", "ya29.test"]) {
      expect(logged).not.toContain(secret);
    }
  });

  it("gets a fresh token after Google rejects one", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    let spy = mockGoogle(401);
    expect((await webhook(PURCHASE)).status).toBe(502);
    spy.mockRestore();
    spy = mockGoogle();
    expect((await webhook(PURCHASE)).status).toBe(200);
    expect(requestsTo(spy, "https://oauth2.googleapis.com/")).toHaveLength(1);
  });
});

describe("browser subscriptions", () => {
  const FID = "cXk2bTdEZ1RreFdQ_x";
  const sub = (path: string, body: object, auth: string | null = `Bearer ${SECRET}`) =>
    call(path, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...(auth ? { Authorization: auth } : {}) },
      body: JSON.stringify(body),
    });

  it("answers the browser's preflight", async () => {
    const res = await call("/subscribe", { method: "OPTIONS" });
    expect(res.status).toBe(204);
    expect(res.headers.get("Access-Control-Allow-Headers")).toContain("Authorization");
  });

  it("puts a browser on its device's topic", async () => {
    const spy = mockGoogle();
    const res = await sub("/subscribe", { registration: FID });
    expect(res.status).toBe(200);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
    const [call0] = requestsTo(spy, "https://fcm.googleapis.com/");
    expect(String(call0[0])).toBe(
      `https://fcm.googleapis.com/v1/projects/openrc-test/registrations/${FID}/topicSubscriptions?topic_name=${TOPIC}`,
    );
    expect(call0[1]!.method).toBe("POST");
  });

  it("treats already subscribed and already gone as done", async () => {
    mockGoogle(409);
    expect((await sub("/subscribe", { registration: FID })).status).toBe(200);
    vi.restoreAllMocks();
    const spy = mockGoogle(404);
    expect((await sub("/unsubscribe", { registration: FID })).status).toBe(200);
    const [call0] = requestsTo(spy, "https://fcm.googleapis.com/");
    expect(String(call0[0])).toBe(
      `https://fcm.googleapis.com/v1/projects/openrc-test/registrations/${FID}/topicSubscriptions/${TOPIC}`,
    );
    expect(call0[1]!.method).toBe("DELETE");
  });

  it("refuses requests without the secret or a registration", async () => {
    const spy = mockGoogle();
    expect((await sub("/subscribe", { registration: FID }, null)).status).toBe(401);
    expect((await sub("/subscribe", { registration: "x" })).status).toBe(400);
    expect((await sub("/subscribe", { registration: "bad/../id1234" })).status).toBe(400);
    expect((await call("/subscribe")).status).toBe(405);
    expect(spy).not.toHaveBeenCalled();
  });

  it("reports a failed subscription by status only", async () => {
    mockGoogle(503);
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    expect((await sub("/subscribe", { registration: FID })).status).toBe(502);
    const logged = error.mock.calls.flat().join(" ");
    expect(logged).toContain("503");
    expect(logged).not.toContain(FID);
    expect(logged).not.toContain(SECRET);
  });
});

describe("notification kinds", () => {
  const send = (query: string, event: object) =>
    call(`/revenuecat/OWRekN${query}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${SECRET}` },
      body: JSON.stringify({ event }),
    });

  it("sends only the kinds a webhook asks for", async () => {
    const spy = mockGoogle();
    const trial = { ...PURCHASE, period_type: "TRIAL", price: 0 };
    const renewal = { ...PURCHASE, type: "RENEWAL" };
    expect(await (await send("?notify=trial,new", trial)).json()).toEqual({ sent: true });
    expect(await (await send("?notify=trial,new", renewal)).json()).toEqual({ sent: false });
    expect(await (await send("?notify=trial", PURCHASE)).json()).toEqual({ sent: false });
    expect(await (await send("", renewal)).json()).toEqual({ sent: true });
    expect(requestsTo(spy, "https://fcm.googleapis.com/")).toHaveLength(2);
  });

  it("always lets RevenueCat's test event through", async () => {
    mockGoogle();
    expect(await (await send("?notify=renewal", { type: "TEST" })).json()).toEqual({ sent: true });
    expect(await (await send("?notify=", { type: "TEST" })).json()).toEqual({ sent: true });
  });

  it("tells conversions from renewals and refunds from cancellations", () => {
    expect(kindOf({ type: "RENEWAL", is_trial_conversion: true })).toBe("conversion");
    expect(kindOf({ type: "RENEWAL" })).toBe("renewal");
    expect(kindOf({ type: "CANCELLATION", cancel_reason: "CUSTOMER_SUPPORT" })).toBe("refund");
    expect(kindOf({ type: "REFUND_REVERSED" })).toBe("refund");
    expect(kindOf({ type: "CANCELLATION", period_type: "TRIAL" })).toBe("cancel");
    expect(kindOf({ type: "SUBSCRIPTION_PAUSED" })).toBe("change");
    expect(kindOf({ type: "EXPERIMENT_ENROLLMENT" })).toBeNull();
    expect(parseKinds("trial,bogus,new")).toEqual(new Set(["trial", "new"]));
    expect(parseKinds(null)).toBeNull();
  });
});

describe("topics", () => {
  it("matches the app's derivation", async () => {
    expect(await topicFor(SECRET)).toBe(TOPIC);
    expect(await topicFor("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO_-")).toBe(
      "openrc-fBymwA0lTBXElb4ISJn8PeJFiPK6IDd3IUlboxL2K70",
    );
  });

  it("reads secrets only in the app's format", () => {
    expect(parseSecret(`Bearer ${SECRET}`)).toBe(SECRET);
    expect(parseSecret(SECRET)).toBe(SECRET);
    expect(parseSecret(`${SECRET}=`)).toBeNull();
    expect(parseSecret("A".repeat(42))).toBeNull();
    expect(parseSecret("A".repeat(42) + "+")).toBeNull();
  });
});

describe("notification copy", () => {
  it("names each kind of event", () => {
    const title = (event: object) => notificationFor(event)?.title;
    expect(title({ type: "INITIAL_PURCHASE", period_type: "TRIAL", price: 0 })).toBe("🟠 Trial started");
    expect(title({ type: "RENEWAL", is_trial_conversion: true, price: 4.99 })).toBe("🔵 Trial converted · $4.99");
    expect(title({ type: "RENEWAL", price: 4.99 })).toBe("🟢 Renewal · $4.99");
    expect(title({ type: "NON_RENEWING_PURCHASE", price: 19.99 })).toBe("🟣 Purchase · $19.99");
    expect(title({ type: "CANCELLATION", cancel_reason: "CUSTOMER_SUPPORT", price: -4.99 })).toBe(
      "🔴 Refund · -$4.99",
    );
    expect(title({ type: "CANCELLATION", cancel_reason: "UNSUBSCRIBE" })).toBe("🟡 Cancellation");
    expect(title({ type: "CANCELLATION", period_type: "TRIAL" })).toBe("🟡 Trial cancelled");
    expect(title({ type: "UNCANCELLATION" })).toBe("🟢 Resubscribed");
    expect(title({ type: "EXPIRATION" })).toBe("🔴 Expired");
    expect(title({ type: "BILLING_ISSUE" })).toBe("🔴 Billing issue");
    expect(title({ type: "PRODUCT_CHANGE" })).toBe("⚪ Plan change");
    expect(title({ type: "TEMPORARY_ENTITLEMENT_GRANT" })).toBeUndefined();
  });

  it("describes the product, country, store and sandbox", () => {
    expect(
      notificationFor({
        type: "PRODUCT_CHANGE",
        product_id: "pro_monthly",
        new_product_id: "pro_yearly",
        country_code: "us",
        store: "PLAY_STORE",
        environment: "SANDBOX",
        currency: "USD",
        price_in_purchased_currency: 49.99,
      })?.body,
    ).toBe("pro_monthly → pro_yearly · 🇺🇸 United States · Google Play · Sandbox");
    expect(notificationFor({ type: "RENEWAL", store: "SOME_NEW_STORE", country_code: "XYZ" })?.body).toBe(
      "Some new store",
    );
    expect(notificationFor({ type: "RENEWAL" })?.body).toBe("RevenueCat event");
    expect(notificationFor({ type: "RENEWAL", price: 5, currency: "NOPE", price_in_purchased_currency: 5 })).toEqual({
      title: "🟢 Renewal · $5.00",
      body: "RevenueCat event",
    });
  });

  it("confirms RevenueCat's test event", () => {
    expect(notificationFor({ type: "TEST" })).toEqual({
      title: "⚪ Test notification",
      body: "RevenueCat can reach this device.",
    });
  });
});
