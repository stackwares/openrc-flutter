# RevenueCat webhooks and Firebase push (Kedi-style)

This app registers **per-project RevenueCat webhooks** (internal dashboard API, same as [Kedi](https://github.com/sereisoglu/Kedi)) that point at a **Cloud Function relay**. The relay verifies the request, reads your Firebase anonymous user id from the query string, and sends an **FCM** notification to tokens stored in Firestore.

## Prerequisites

1. **Firebase project** (already wired via `GoogleService-Info.plist` / `google-services.json`).
2. **Blaze (pay-as-you-go)** if you use Cloud Functions in production (Spark has tight limits).
3. **Firestore** enabled in the Firebase console (Native mode).
4. **Authentication → Sign-in method → Anonymous** enabled (used as the stable “notification user id”).

## 1. Deploy Firestore rules

From the repo root:

```bash
firebase deploy --only firestore:rules
```

Rules deny direct client access to `pushUsers` and `webhookDedupe`; only Cloud Functions write there.

## 2. Configure the relay secret (production)

The HTTP function `revenueCatWebhook` optionally requires an `Authorization` header so random callers cannot trigger pushes.

Create `functions/.env` (see `functions/.env.example`):

```bash
RC_WEBHOOK_BEARER=your-long-random-secret
```

For Firebase **params**, this file is loaded when you deploy from the `functions` directory. Use the **same** value in the RevenueCat dashboard when you set the webhook’s **Authorization** header (e.g. `Bearer your-long-random-secret`).

If `RC_WEBHOOK_BEARER` is empty, the function **rejects every request**. The RevenueCat v2 API cannot set that Authorization header; it has to be pasted in the webhook’s dashboard settings.

## 3. Deploy Cloud Functions

```bash
cd functions && npm install && npm run build && cd ..
firebase deploy --only functions
```

Note the HTTPS URL for `revenueCatWebhook`, for example:

`https://us-central1-YOUR_PROJECT.cloudfunctions.net/revenueCatWebhook`

## 4. Build the Flutter app with the relay URL

Pass the function URL **without** a query string (the app adds `?userId=<firebaseAnonymousUid>`):

```bash
flutter run \
  --dart-define=RC_WEBHOOK_RELAY_URL=https://us-central1-YOUR_PROJECT.cloudfunctions.net/revenueCatWebhook
```

Optional (if not using `us-central1`):

```bash
--dart-define=FIREBASE_FUNCTIONS_REGION=europe-west1
```

The **callable** `registerFcmToken` must be deployed in the same region as `FIREBASE_FUNCTIONS_REGION`.

The app registers a Firebase **installation id** (`FirebaseMessaging.register` / `onRegistered`), not the deprecated FCM registration token. The relay sends to that id with the Admin SDK `token` field. Installations saved before this change keep working until a send fails and the stale id is removed.

`lookupAppIcon` is a public HTTPS function the **web** app uses for App Store and Play icons. Phone builds still look the stores up directly.

## 5. RevenueCat dashboard: Authorization header

After the app creates a webhook (Settings → Purchase alerts → RevenueCat webhooks), open the webhook in **RevenueCat → Project → Integrations → Webhooks** and set **Authorization** to match your relay:

- `Bearer <RC_WEBHOOK_BEARER>` **or**
- the raw secret, if you configured RevenueCat that way

Until this matches, the relay returns `401` and no push is sent.

## 6. iOS deployment target

The app’s iOS deployment target is **15.0** (required by `cloud_functions` / current Firebase iOS SDKs).

## 7. Apple Push Notification service (APNs) for FCM

1. In **Apple Developer**, create an **APNs Auth Key** (or certificate).
2. In **Firebase Console → Project settings → Cloud Messaging → Apple app configuration**, upload the key and set Team ID / Key ID / Bundle ID.
3. In Xcode, for the **Runner** target, enable **Signing & Capabilities → Push Notifications** (the app already lists `remote-notification` under **Background Modes** in `Info.plist`).

## 8. Android

- `POST_NOTIFICATIONS` is declared in `AndroidManifest.xml` (Android 13+).
- On first launch, the OS prompts for notification permission.

## 9. Flow checklist

| Step | Action |
|------|--------|
| 1 | Anonymous auth enabled in Firebase |
| 2 | Firestore created + rules deployed |
| 3 | Functions deployed; `RC_WEBHOOK_BEARER` set for production |
| 4 | App built with `RC_WEBHOOK_RELAY_URL` |
| 5 | APNs configured (iOS) |
| 6 | In app: enable webhook per project; set RC Authorization header |
| 7 | Use **Send test notification** or a real purchase to verify |

## Troubleshooting

- **No push after webhook**: Check Cloud Function logs, FCM token registration (`registerFcmToken` logs), and that the webhook URL in RevenueCat exactly matches what the app shows (including `userId` query).
- **401 from relay**: Mismatch between RevenueCat Authorization header and `RC_WEBHOOK_BEARER`.
- **Callable permission denied**: Ensure the user is signed in anonymously (app calls `signInAnonymously` on startup) and the callable is deployed in the region set by `FIREBASE_FUNCTIONS_REGION`.
