import * as crypto from "crypto";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {onCall, HttpsError, onRequest} from "firebase-functions/v2/https";
import {defineString} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {buildNotificationCopy, type RCWebhookEvent} from "./notificationCopy";

initializeApp();
const db = getFirestore();

/** Set in `functions/.env` (see docs) or Firebase console → Functions → environment. */
const rcWebhookBearer = defineString("RC_WEBHOOK_BEARER", {default: ""});

function tokenDocId(fcmToken: string): string {
  return crypto.createHash("sha256").update(fcmToken).digest("hex").slice(0, 40);
}

function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  return ab.length === bb.length && crypto.timingSafeEqual(ab, bb);
}

/** Fails closed: with no secret configured every request is rejected. */
function verifyWebhookAuth(
  req: {header: (name: string) => string | undefined},
  secret: string,
): boolean {
  if (!secret) {
    logger.error("RC_WEBHOOK_BEARER is not set; rejecting webhook");
    return false;
  }
  const auth = req.header("Authorization") ?? "";
  return safeEqual(auth, `Bearer ${secret}`) || safeEqual(auth, secret);
}

/** Firebase uids are <=128 chars and never contain "/". */
function isValidUid(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

const STALE_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

interface WebhookBody {
  event?: RCWebhookEvent;
  api_version?: string;
}

/**
 * RevenueCat → this URL (GET params: userId = Firebase anonymous uid).
 * Configure the same bearer value in RevenueCat’s webhook Authorization header.
 */
export const revenueCatWebhook = onRequest(
  {
    region: "us-central1",
    cors: false,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const secret = rcWebhookBearer.value();
    if (!verifyWebhookAuth(req, secret)) {
      res.status(401).send("Unauthorized");
      return;
    }

    const userId = req.query.userId ?? req.query.id;
    if (!isValidUid(userId)) {
      res.status(400).send("Missing or invalid userId query parameter");
      return;
    }

    let body: WebhookBody;
    try {
      body =
        typeof req.body === "string"
          ? (JSON.parse(req.body) as WebhookBody)
          : (req.body as WebhookBody);
    } catch (e) {
      logger.error("Invalid JSON body", e);
      res.status(400).send("Invalid JSON");
      return;
    }

    const event = body.event;
    if (!event) {
      logger.warn("No event in webhook payload");
      res.status(200).send("OK");
      return;
    }

    let claimedDedupe: FirebaseFirestore.DocumentReference | undefined;
    try {
      const eventId = typeof event.id === "string" && event.id.length <= 200 &&
        !event.id.includes("/") ? event.id : undefined;
      if (eventId) {
        const dedupeRef = db.collection("webhookDedupe").doc(eventId);
        const got = await db.runTransaction(async (tx) => {
          const snap = await tx.get(dedupeRef);
          if (snap.exists) return false;
          tx.set(dedupeRef, {at: FieldValue.serverTimestamp()});
          return true;
        });
        if (!got) {
          res.status(200).send("Duplicate");
          return;
        }
        claimedDedupe = dedupeRef;
      }

      const {title, body: notifBody} = buildNotificationCopy(event);

      const tokensSnap = await db
        .collection("pushUsers")
        .doc(userId)
        .collection("tokens")
        .get();

      const tokenDocs = tokensSnap.docs.filter(
        (d) => typeof d.data().token === "string" && d.data().token,
      );
      const tokens = tokenDocs.map((d) => d.data().token as string);

      if (tokens.length === 0) {
        logger.info("No FCM tokens for user", {userId});
        res.status(200).send("OK");
        return;
      }

      const messageBase = {
        notification: {title, body: notifBody},
        data: {
          eventId: eventId ?? "",
          eventType: event.type ?? "",
          url: `https://app.revenuecat.com/projects/${event.app_id ?? ""}`,
        },
      };

      // `token` is an installation id from register()/onRegistered.
      // Older FCM registration tokens stored before that migration still send
      // through the same field until a failed delivery removes them.
      const batch = tokens.map((token) =>
        getMessaging().send({
          ...messageBase,
          token,
          apns: {payload: {aps: {"thread-id": eventId ?? "revenuecat"}}},
          android: {priority: "high" as const},
        }),
      );

      const results = await Promise.allSettled(batch);
      const stale: Promise<unknown>[] = [];
      let failures = 0;
      results.forEach((r, i) => {
        if (r.status !== "rejected") return;
        failures++;
        const code = (r.reason as {code?: string} | undefined)?.code ?? "";
        if (STALE_TOKEN_CODES.has(code)) stale.push(tokenDocs[i].ref.delete());
      });
      if (failures > 0) {
        logger.warn("Some FCM sends failed", {
          failures,
          removedStale: stale.length,
          total: tokens.length,
        });
        await Promise.allSettled(stale);
      }
    } catch (e) {
      logger.error("Webhook processing failed", e);
      // Release the dedupe claim so RevenueCat's retry is not dropped.
      await claimedDedupe?.delete().catch(() => undefined);
      res.status(500).send("Internal error");
      return;
    }
    res.status(200).send("OK");
  },
);

interface RegisterTokenData {
  token?: string;
  platform?: string;
  /** When true, delete this installation id instead of storing it. */
  remove?: boolean;
}

/**
 * Requires Firebase Auth (anonymous is fine).
 * Stores the FCM installation id under pushUsers/{uid}, or deletes it when
 * `remove` is true (onUnregistered).
 */
export const registerFcmToken = onCall(
  {region: "us-central1"},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const uid = request.auth.uid;
    const data = (request.data ?? {}) as RegisterTokenData;
    const token = typeof data.token === "string" ? data.token.trim() : "";
    if (!token || token.length > 4096) {
      throw new HttpsError("invalid-argument", "token is required");
    }
    const ref = db
      .collection("pushUsers")
      .doc(uid)
      .collection("tokens")
      .doc(tokenDocId(token));

    if (data.remove === true) {
      await ref.delete();
      return {ok: true};
    }

    const platform = ["android", "iOS", "macOS"].includes(data.platform ?? "") ?
      (data.platform as string) : "unknown";

    await ref.set({
      token,
      platform,
      kind: "fid",
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {ok: true};
  },
);

export {lookupAppIcon} from "./appIconLookup";
