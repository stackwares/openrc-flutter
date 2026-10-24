/**
 * Each device has a random secret, which RevenueCat sends as the webhook's
 * Authorization header. Notifications go to an FCM topic named after a hash
 * of that secret, so the notifier needs no record of devices. The app
 * derives the same name in
 * `lib/services/push/push_channel.dart`; keep the two in step.
 */

/** 32 random bytes, base64url without padding. */
const SECRET = /^[A-Za-z0-9_-]{43}$/;

/** The secret from an Authorization header, with or without "Bearer ". */
export function parseSecret(header: string | null): string | null {
  if (!header) return null;
  const value = header.trim().replace(/^Bearer\s+/i, "");
  return SECRET.test(value) ? value : null;
}

export async function topicFor(secret: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`openrc-topic:${secret}`),
  );
  return `openrc-${base64Url(new Uint8Array(digest))}`;
}

export function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
