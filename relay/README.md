# OpenRC relay

RevenueCat's API answers browsers only from RevenueCat's own dashboard, so the
OpenRC web app can't call it directly. This Cloudflare Worker sits in between.

It is deliberately small and stateless:

- Forwards only RevenueCat's developer API: `/v1/developers/*` and
  `/internal/v1/developers/*`, to `https://api.revenuecat.com`.
- Answers only pages from `ALLOWED_ORIGINS`; anything else, including requests
  with no `Origin`, gets `403`. It is not an open proxy.
- Sends RevenueCat only the headers it needs (`Authorization`,
  `Content-Type`, `X-Requested-With`, `Accept`, `Accept-Language`,
  `User-Agent`). Cookies are dropped in both directions.
- Streams request and response bodies straight through. Nothing is stored,
  and bodies, tokens and headers are never logged. Query strings are redacted
  from Cloudflare's logs and traces.
- `GET /icon?bundleId=…&hint=apple|google` looks up an app's App Store or
  Google Play icon, which browsers can't fetch either.
- `GET /` is a health check.

## Develop

```bash
npm install
cp .dev.vars.example .dev.vars   # allows http://localhost:* origins
npm run dev                      # http://127.0.0.1:8787
```

Point a local web build at it:

```bash
flutter run -d chrome --dart-define=OPENRC_RELAY_URL=http://127.0.0.1:8787
```

## Test

```bash
npm run typecheck
npm test
```

Tests run inside `workerd`, the Workers runtime, through
`@cloudflare/vitest-plugin`.

## Deploy your own

1. Set `ALLOWED_ORIGINS` in `wrangler.jsonc` to the origin(s) your web app is
   served from.
2. `npx wrangler login`, then `npm run deploy`.
3. Build the web app with
   `--dart-define=OPENRC_RELAY_URL=https://<your-worker>.workers.dev`.

Run `npm run types` after changing `wrangler.jsonc`.
