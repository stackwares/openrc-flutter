/**
 * Firebase Cloud Messaging (HTTP v1), authorized with a service account.
 * FCM delivers to Android directly and to iOS and macOS through APNs.
 */

import { base64Url } from "./topic";

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

export interface TopicMessage {
  topic: string;
  title: string;
  body: string;
  /** Lets a retried webhook replace its notification instead of adding one. */
  collapseId?: string;
  /** The store's transaction id, for opening the transaction on tap. */
  transactionId?: string;
  /**
   * A public https picture (the project's icon), shown large in the push.
   * Android and web only: Apple always shows the app's own icon, and a large
   * one needs a Notification Service Extension the app doesn't ship.
   */
  imageUrl?: string;
}

/** The service account from the FCM_SERVICE_ACCOUNT secret, if usable. */
export function parseServiceAccount(raw: string | undefined): ServiceAccount | null {
  if (!raw) return null;
  try {
    const json = JSON.parse(raw) as Partial<ServiceAccount>;
    const { project_id, client_email, private_key } = json;
    if (typeof project_id !== "string" || typeof client_email !== "string") return null;
    if (typeof private_key !== "string" || !private_key.includes("PRIVATE KEY")) return null;
    return { project_id, client_email, private_key };
  } catch {
    return null;
  }
}

/** An access token lives an hour; reuse it while this isolate does. */
let cachedToken: { email: string; token: string; expiresAt: number } | null = null;

export function forgetAccessToken(): void {
  cachedToken = null;
}

async function signJwt(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const encode = (value: object) => base64Url(new TextEncoder().encode(JSON.stringify(value)));
  const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({
    iss: account.client_email,
    scope: SCOPE,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  })}`;
  const pem = account.private_key.replace(/-----[^-]+-----|\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${base64Url(new Uint8Array(signature))}`;
}

async function accessToken(account: ServiceAccount): Promise<string> {
  if (
    cachedToken?.email === account.client_email &&
    cachedToken.expiresAt > Date.now() + 60_000
  ) {
    return cachedToken.token;
  }
  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: await signJwt(account),
    }),
  });
  if (!response.ok) throw new FcmError("token", response.status);
  const json = await response.json<{ access_token?: string; expires_in?: number }>();
  if (!json.access_token) throw new FcmError("token", response.status);
  cachedToken = {
    email: account.client_email,
    token: json.access_token,
    expiresAt: Date.now() + (json.expires_in ?? 3600) * 1000,
  };
  return json.access_token;
}

/** A failed call to Google, by stage and HTTP status only. */
export class FcmError extends Error {
  constructor(
    readonly stage: "token" | "send" | "subscription",
    readonly status: number,
  ) {
    super(`FCM ${stage} failed with ${status}`);
  }
}

/**
 * Adds [registration] (a browser's Firebase installation id or FCM token)
 * to [topic], or with [subscribe] false removes it, through FCM's topic
 * subscription API. Browsers can't do this themselves.
 */
export async function setTopicSubscription(
  account: ServiceAccount,
  registration: string,
  topic: string,
  subscribe: boolean,
): Promise<void> {
  const token = await accessToken(account);
  const base =
    `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}` +
    `/registrations/${encodeURIComponent(registration)}/topicSubscriptions`;
  const response = await fetch(
    subscribe ? `${base}?topic_name=${encodeURIComponent(topic)}` : `${base}/${encodeURIComponent(topic)}`,
    {
      method: subscribe ? "POST" : "DELETE",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: "{}",
    },
  );
  if (response.status === 401) forgetAccessToken();
  // Already subscribed, or already gone: the outcome asked for.
  const settled = subscribe ? response.status === 409 : response.status === 404;
  if (!response.ok && !settled) throw new FcmError("subscription", response.status);
}

export async function sendToTopic(account: ServiceAccount, message: TopicMessage): Promise<void> {
  const token = await accessToken(account);
  const collapse = message.collapseId;
  const image = message.imageUrl;
  // Both optional: an empty notification object would still be a change in
  // the payload, so it's only sent when it says something.
  const android = {
    ...(collapse ? { tag: collapse } : {}),
    ...(image ? { image } : {}),
  };
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          topic: message.topic,
          notification: { title: message.title, body: message.body },
          data: {
            source: "revenuecat",
            ...(message.transactionId ? { transaction_id: message.transactionId } : {}),
            // Lets a browser replace a retried event's notification.
            ...(collapse ? { event_id: collapse } : {}),
          },
          android: {
            priority: "HIGH",
            ...(Object.keys(android).length ? { notification: android } : {}),
          },
          webpush: {
            headers: { Urgency: "high" },
            ...(image ? { notification: { image } } : {}),
          },
          apns: {
            headers: {
              "apns-priority": "10",
              ...(collapse ? { "apns-collapse-id": collapse } : {}),
            },
            payload: { aps: { sound: "default", "thread-id": "revenuecat" } },
          },
        },
      }),
    },
  );
  // A token Google stopped accepting gets one fresh try on the next webhook.
  if (response.status === 401) forgetAccessToken();
  if (!response.ok) throw new FcmError("send", response.status);
}
