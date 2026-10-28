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
| `lib/services/` | RevenueCat API client and auth, local stores (fees, currency, icons, sort, product names), exchange rates, telemetry, the home-screen widget channel, optional Ask LLM client and tools |
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
7. **Product names**: `product_labels_store.dart` keeps per-app labels for
   store product ids on the device only, and `plan_display.dart` reads them
   wherever a product is shown. Names never touch amounts or filters. They
   reach notifications through this device's own webhook URL only
   (`push_names.dart`), so each device's pushes read its names and nothing
   naming-specific reaches any server of ours. The naming screen can suggest
   labels with the connected Ask model, sending product ids only.
8. **Widgets**: after loading, a summary is handed to the native widgets
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
   store fees (when subtracted), the app's last saved exchange rate
   (`push_display.dart`), the product names Settings gave (`push_names.dart`)
   and the project's name, so the notifier shows amounts as Settings does,
   calls a product what the app calls it, and names the project the event
   came from; the shell keeps the webhooks in step when those settings
   change. Names ride along as `?names=<id>%0A<name>%09…`, capped so the URL
   stays short, and are the one thing here that is the developer's own text:
   they sit in that device's webhook inside their RevenueCat project.
   The project's icon (`RcProject.iconUrl`, RevenueCat's `icon_url`) travels
   the same way as `?icon=<https url>` and becomes the push's picture on
   Android and its icon in browsers; Apple shows the app's own icon, so
   neither iOS nor macOS gets a picture.
   Copying the URL and header by hand (`push_setup_sheet.dart`) remains as a
   fallback.
3. For each event, the notifier hashes the header to find the topic, writes
   the notification (`notifier/src/copy.ts`) — the product's name from the
   URL or the store's id, the plan's length (`Weekly`, `Monthly`, `Annual`,
   `3 months`) read from the store's own purchase and expiration dates, and
   neither repeated when the name already says it — and sends it through
   FCM's HTTP v1 API with a service account. It keeps no record of devices
   or events.
4. A notification that arrives while the app is open reloads the
   transactions. Tapping one opens that transaction's details, found by the
   store transaction id the push carries (`main_shell.dart`).

Turning notifications off removes the device's webhooks; logging out does
too, before the session ends, and deletes the secret. Webhooks that can't be
removed (offline, say) are retried on a later launch. An expired session
keeps everything, since the same person is likely to sign back in.

RevenueCat caps the webhooks a project can hold, and a reinstall adds one the
old secret can no longer find. Each project's sheet therefore opens its
webhook list (`project_webhooks_sheet.dart`), marking this device's own from
other OpenRC ones and from other services by URL shape, so stale entries can
be deleted there: one by one, or all of OpenRC's at once, never this device's
by accident. The Notifications screen's webhook action sweeps all projects at
once (`webhook_sweep_sheet.dart`), deleting every webhook the device didn't
make, so a project RevenueCat is full for can be cleared before this device
has a webhook of its own in it.

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

`lib/services/telemetry.dart` is OpenRC's vocabulary over the shared
`core_analytics_flutter` package, which owns the PostHog client for every
Stackwares app. It does nothing unless the build has `POSTHOG_PROJECT_TOKEN`.
When on, it records anonymous screen views (and, on the web, a `$pageview` per
screen with a made-up path such as `/revenue`, which is what PostHog's web
analytics counts), crashes from Flutter, the platform dispatcher and native
code, and the events the funnels need: `onboarding_*`, `sign_in_started` /
`sign_in_failed` / `signed_in`, `data_loaded`, `notifications_enabled`,
`product_named`, `ask_message_sent`, `preference_changed`. Properties are
categorical only; amounts, app names, product ids, emails and questions never
go with them.

Two super properties identify a build rather than a person. `app` (`openrc`)
separates this app from the rest of the portfolio inside one PostHog project,
and `environment` (`production`, `internal`, `development`, from
`--dart-define=POSTHOG_ENVIRONMENT`) separates channels, so every dashboard
and funnel can be filtered to one. `app_version` and `app_build` come from the
package.

Session replay is on for the native apps and masked by the SDK before a frame
leaves the device: `maskAllTexts` and `maskAllImages` are on, and
`maskCustomPaint` masks every `CustomPaint` bound, so the charts (drawn with
`fl_chart`, whose axis labels are not Text widgets) are covered too. A replay
therefore shows layout, navigation and masked blocks, never a project name, a
product, or an amount. Capture needs the plugin's root widget mounted around
the app (`PostHogWidget`, in `app.dart`), after the SDK's setup has finished:
without it the native SDK has no Flutter frames to record. Flutter web draws into a canvas, where replay needs
`session_recording.canvasCapture` and a `PostHogMaskWidget` around the app;
until that is wired the browser build sends no snapshots. No person profiles
are created, `identify` is never called, and the queue is flushed when the app
goes to the background. A fresh install in a debug build starts opted out, so
a developer's own runs do not land in the same charts as shipped ones. Users
can switch all of it off in Settings.
