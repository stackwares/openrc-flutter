import * as crypto from "crypto";
import * as admin from "firebase-admin";
import {onCall, HttpsError, onRequest} from "firebase-functions/v2/https";
import {defineString} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {buildNotificationCopy, type RCWebhookEvent} from "./notificationCopy";

admin.initializeApp();
const db = admin.firestore();

/** Set in `functions/.env` (see docs) or Firebase console → Functions → environment. */
const rcWebhookBearer = defineString("RC_WEBHOOK_BEARER", {default: ""});

function tokenDocId(fcmToken: string): string {
  return crypto.createHash("sha256").update(fcmToken).digest("hex").slice(0, 40);
}

function verifyWebhookAuth(
  req: {header: (name: string) => string | undefined},
  secret: string,
): boolean {
  if (!secret) {
    logger.warn(
      "RC_WEBHOOK_BEARER secret empty; webhook auth skipped (set secret for production)",
    );
    return true;
  }
  const auth = req.header("Authorization") ?? req.header("authorization") ?? "";
  return auth === `Bearer ${secret}` || auth === secret;
}

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

    const userId =
      (req.query.userId as string | undefined) ??
      (req.query.id as string | undefined);
    if (!userId || typeof userId !== "string") {
      res.status(400).send("Missing userId query parameter");
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

    const eventId = event.id;
    if (eventId) {
      const dedupeRef = db.collection("webhookDedupe").doc(eventId);
      const got = await db.runTransaction(async (tx) => {
        const snap = await tx.get(dedupeRef);
        if (snap.exists) return false;
        tx.set(dedupeRef, {at: admin.firestore.FieldValue.serverTimestamp()});
        return true;
      });
      if (!got) {
        res.status(200).send("Duplicate");
        return;
      }
    }

    const {title, body: notifBody} = buildNotificationCopy(event);

    const tokensSnap = await db
      .collection("pushUsers")
      .doc(userId)
      .collection("tokens")
      .get();

    const tokens = tokensSnap.docs
      .map((d) => d.data().token as string)
      .filter(Boolean);

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

    const batch = tokens.map((token) =>
      admin.messaging().send({
        ...messageBase,
        token,
        apns: {payload: {aps: {"thread-id": eventId ?? "revenuecat"}}},
        android: {priority: "high" as const},
      }),
    );

    const results = await Promise.allSettled(batch);
    const failures = results.filter((r) => r.status === "rejected").length;
    if (failures > 0) {
      logger.warn("Some FCM sends failed", {failures, total: tokens.length});
    }

    res.status(200).send("OK");
  },
);

interface RegisterTokenData {
  token?: string;
  platform?: string;
}

/**
 * Requires Firebase Auth (anonymous is fine). Stores FCM token under pushUsers/{uid}.
 */
export const registerFcmToken = onCall(
  {region: "us-central1"},
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const uid = request.auth.uid;
    const data = request.data as RegisterTokenData;
    const token = data.token?.trim();
    if (!token) {
      throw new HttpsError("invalid-argument", "token is required");
    }
    const platform = data.platform ?? "unknown";

    await db
      .collection("pushUsers")
      .doc(uid)
      .collection("tokens")
      .doc(tokenDocId(token))
      .set({
        token,
        platform,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    return {ok: true};
  },
);
