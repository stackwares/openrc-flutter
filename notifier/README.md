# OpenRC notifier

Turns RevenueCat webhooks into push notifications for the OpenRC app, through
Firebase Cloud Messaging (FCM). FCM reaches Android directly and iPhone, iPad
and Mac through APNs.

It is deliberately small and stateless:

- **No device list.** Turning on notifications in OpenRC makes a random
  secret on the device. The device subscribes to an FCM topic named after a
  hash of that secret (`openrc-<base64url(SHA-256("openrc-topic:" + secret))>`),
  and RevenueCat sends the secret as the webhook's `Authorization` header.
  The notifier hashes the header and sends to that topic, so it never needs
  to know which devices exist.
- **Nothing is stored or logged.** Each event is read in memory to write the
  notification (type, price, product, country, store) and then dropped. The
  push also carries the store's transaction id, so tapping it opens that
  transaction in the app.
  Bodies, secrets and topics never reach the logs, and Cloudflare's
  invocation logs, which would record headers, are off. Failed calls to
  Google are logged by stage and HTTP status only.
- `POST /revenuecat` (or `/revenuecat/<tag>`: each device's webhook has its
  own URL, since RevenueCat allows one webhook per URL in a project, and the
  tag is ignored) takes RevenueCat's webhook. An optional
  `?notify=trial,new,…` lists the kinds that device wants (see `KINDS` in
  `src/copy.ts`); other events get `200` without a notification. RevenueCat's
  own filter can't do this, since a trial and a new subscription are the same
  RevenueCat event. RevenueCat's test event always gets through.
  `&currency=EUR&fees=15,30&rate=0.92` shows the amount the way the app's
  Settings do: in that currency and after App Store / Google Play fees. Rates
  come from the same free source the app uses, cached in memory; when that's
  down it uses the last rates it fetched, then the app's saved `rate`, then
  US dollars. Wrong or missing secrets get
  `401`. Events that aren't about a purchase (aliases, experiments, virtual
  currency, invoices) get `200` without a notification. A failed delivery
  gets `502`, so RevenueCat retries it; retried events replace their
  notification instead of adding another.
- `POST /subscribe` and `POST /unsubscribe` put a browser on its device's
  topic, or take it off, with `{"registration": "<installation id or token>"}`
  and the secret as `Authorization`. Phones subscribe themselves; browsers
  can't, so the web app asks here. They answer any origin, since the secret,
  not a cookie, is the authorization.
- `GET /` is a health check.

Notification text is English for now.

## Develop

```bash
npm install
cp .dev.vars.example .dev.vars   # then paste a service account key
npm run dev                      # http://127.0.0.1:8787
```

Try it with RevenueCat's test event:

```bash
curl -X POST http://127.0.0.1:8787/revenuecat \
  -H "Authorization: Bearer <secret from the app>" \
  -H "Content-Type: application/json" \
  -d '{"api_version":"1.0","event":{"type":"TEST"}}'
```

## Test

```bash
npm run typecheck
npm test
```

## Deploy your own

1. In the Firebase project your app builds use, create a service account key
   that can send messages (the **Firebase Cloud Messaging API Admin** role is
   enough) and upload your APNs key under **Project settings → Cloud
   Messaging**.
2. `npx wrangler login`, then
   `npx wrangler secret put FCM_SERVICE_ACCOUNT` and paste the key's JSON.
3. `npm run deploy`.
4. Build the app with `--dart-define=OPENRC_NOTIFIER_URL=https://<your-worker>.workers.dev`
   and your Firebase defines (see the main README).

Run `npm run types` after changing `wrangler.jsonc`.
