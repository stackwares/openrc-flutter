# Architecture

OpenRC is a Flutter app with no backend of its own. It talks to RevenueCat's
developer API with the signed-in user's session and works out everything else
on the device. The only server-side pieces are the optional web relay and the
optional notifier, and neither stores anything.

```
 iOS / iPadOS / Android / macOS ──────────────► api.revenuecat.com
                                                  /v1/developers/…
 Web (browser) ──► relay (Cloudflare Worker) ──►  /internal/v1/developers/…
                     └─ /icon ──► App Store / Google Play lookups

 RevenueCat webhook ──► notifier (Cloudflare Worker) ──► Firebase Cloud
                                                         Messaging ──► devices
```

## Layers

| Folder | What lives there |
|---|---|
| `lib/app/` | App root, sign-in gate, the adaptive shell (tab bar, rail, sidebar), macOS menu bar, keyboard shortcuts |
| `lib/features/` | One folder per area: `transactions`, `revenue`, `charts`, `ask`, `settings`, `sign_in`. Screens, their notifiers and widgets |
| `lib/services/` | RevenueCat API client and auth, local stores (fees, currency, icons, sort), exchange rates, telemetry, the home-screen widget channel, optional Ask LLM client and tools |
| `lib/models/` | API response models |
| `lib/core/` | Constants, extensions, formatting and date utilities, motion helpers |
| `lib/theme/` | Design tokens, colors, typography, breakpoints |
| `lib/widgets/` | Shared UI: cards, grouped lists, badges, side panel, logo |
| `ios/RevenueWidgets/`, `android/…/widgets/` | Native home-screen widgets |
| `relay/` | Cloudflare Worker for the web app |
| `notifier/` | Cloudflare Worker that turns RevenueCat webhooks into push notifications |

State is managed with Riverpod. Notifiers own loading, paging and errors;
widgets only read providers and call notifier methods.

## Data flow

1. **Sign-in** (`rc_auth_service.dart`): `POST /login`, with a second call
   carrying the two-factor code when RevenueCat asks for one. The session
   token goes to secure storage (Keychain on Apple platforms). A 401 anywhere
   signs out and explains why on the sign-in screen.
2. **Transactions** (`transactions_screen.dart`): `GET /me/transactions` is
   paged backwards in time and deduplicated, then grouped by local calendar
   day. Each day's totals, type counts, insights and the seven-day strip are
   computed from those rows.
3. **Revenue**: the same rows, for the month so far, plus payout estimates.
   App Store payouts follow Apple's fiscal calendar
   (`store_payday_schedule.dart`); Google Play pays the previous month's
   earnings around the 15th.
4. **Charts**: `GET /me/charts_v2/overview` for the summary and
   `charts_v2/<metric>` for each series.
5. **Adjustments**: store fees (`commission_settings_store.dart`) and the
   display currency (`display_currency_store.dart`, rates from a public
   exchange-rate API) are applied when amounts are shown.
6. **App icons**: looked up from the App Store or Google Play by bundle id,
   cached locally, and overridable per app.
7. **Widgets**: after loading, a summary is handed to the native widgets
   through the `com.openrc.app/widgets` method channel (an App Group on iOS,
   shared preferences on Android).

## Ask

The fourth tab answers RevenueCat questions with OpenRC cards. The model
does not invent widget trees: tools return typed JSON, `present` chooses a
card type, and a repair compositor builds the same cards if `present` is
skipped.

Keys stay in secure storage (`agent_key_<provider>`). Prefs keep the
provider and model. Native apps call the provider directly. Web calls
`{OPENRC_RELAY_URL}/llm/{preset}/…`. Custom unknown hosts are native-only.
The RevenueCat session never goes to the LLM; subscriber ids are masked the
same way as the table.

Other tabs jump into this same thread with a prefilled question (the selected
day, a chart range, the next payout, or one sale). Web also honors `?ask=`
and a notification “Ask about this” action. `get_transaction` loads that
sale and its masked subscriber history.

## Push notifications

Off unless the build has Firebase settings (`lib/services/push/push_config.dart`)
and the user turns them on in Settings. iPhone, iPad, Android and the web;
macOS builds are signed ad hoc, which can't carry the push entitlement.

Browsers can't join FCM topics themselves. The web app registers its own
push service worker (`web/push/sw.js`, scoped away from Flutter's) with the
project's web push key, then sends the browser's registration id and the
device's secret to the notifier's `/subscribe`, which adds it to the topic
through FCM's topic subscription API. The service worker shows each push and,
on a click, focuses an open tab (which opens the transaction) or opens
`/?transaction=<id>`.

1. Turning them on (`push_notifications.dart`) asks for permission and makes a
   random secret, kept in secure storage. The device subscribes to the FCM
   topic `openrc-<base64url(SHA-256("openrc-topic:" + secret))>`
   (`push_channel.dart`), and subscribes again on every launch, so a changed
   FCM registration never breaks delivery.
2. The device then adds its own webhook to each project the user picks
   (`push_webhooks.dart`, `push_projects_sheet.dart`), through the dashboard
   API under `/internal/v1/developers/me/projects/{id}/integrations/webhooks`
   that RevenueCat's dashboard and Kedi use. The webhook points at the
   notifier's `/revenuecat/<tag>` URL with `Bearer <secret>` as its authorization
   header, sends production events by default (sandbox is a switch), and only
   the event types that notify. RevenueCat masks the header when a webhook is
   read back, so devices can't share one, and allows one webhook per URL in
   a project: each device adds its own, with a URL ending in a tag from a
   hash of the secret (also in its name, `OpenRC · <platform> · <tag>`), so
   the device can find its webhooks again. RevenueCat's
   `test_webhook` call then proves the path end to end. Which kinds of
   event notify (`push_kinds.dart`: new subscriptions, trials, conversions,
   renewals, refunds…) is a choice for all projects, which each project can
   replace with its own. It travels in the webhook URL as `?notify=…`, with
   the webhook's RevenueCat event types narrowed to match, and the notifier
   drops events of other kinds. The URL also carries the display currency,
   store fees (when subtracted) and the app's last saved exchange rate
   (`push_display.dart`), so the notifier shows amounts as Settings does; the
   shell keeps the webhooks in step when those settings change. Copying the URL and
   header by hand (`push_setup_sheet.dart`) remains as a fallback.
3. For each event, the notifier hashes the header to find the topic, writes
   the notification (`notifier/src/copy.ts`) and sends it through FCM's HTTP
   v1 API with a service account. It keeps no record of devices or events.
4. A notification that arrives while the app is open reloads the
   transactions. Tapping one opens that transaction's details, found by the
   store transaction id the push carries (`main_shell.dart`).

Turning notifications off removes the device's webhooks; logging out does
too, before the session ends, and deletes the secret. Webhooks that can't be
removed (offline, say) are retried on a later launch. An expired session
keeps everything, since the same person is likely to sign back in.

## Layouts

`AppBreakpoints` (`lib/theme/app_tokens.dart`) sorts windows into three size
classes:

| Width | Navigation | Content |
|---|---|---|
| < 600 | Floating tab bar | Single column |
| 600–1023 | Navigation rail | Single column, centered |
| ≥ 1024 | Sidebar with shortcuts | Transactions and Revenue become a dashboard; details open in a side panel |

The dashboard starts at 900 pt of content width (`AppBreakpoints.dashboard`):
one column with a filter bar (projects, stores, countries), the cards in
rows, and a sortable transactions table underneath.

Screens decide columns from their own width with `LayoutBuilder`, so they
also work inside split views. Phones are locked to portrait; tablets rotate.

## Web

Browsers can't call RevenueCat's API (it allows only its own dashboard as a
CORS origin), so web builds send API calls to the relay, set by
`OPENRC_RELAY_URL`. Ask on web uses the same relay's allowlisted `/llm/*`
paths. See [relay/README.md](../relay/README.md). The app is otherwise the
same code; home-screen widgets are skipped.

## Telemetry

`lib/services/telemetry.dart` wraps PostHog. It does nothing unless the build
has `POSTHOG_PROJECT_TOKEN`. When on, it records anonymous screen views, a
handful of events (signed in, signed out) and uncaught errors, with no person
profiles and no session replay. Users can switch it off in Settings.
