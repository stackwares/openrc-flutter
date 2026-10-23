# Architecture

OpenRC is a Flutter app with no backend of its own. It talks to RevenueCat's
developer API with the signed-in user's session and works out everything else
on the device. The only server-side piece is the optional web relay.

```
 iOS / iPadOS / Android / macOS ──────────────► api.revenuecat.com
                                                  /v1/developers/…
 Web (browser) ──► relay (Cloudflare Worker) ──►  /internal/v1/developers/…
                     └─ /icon ──► App Store / Google Play lookups
```

## Layers

| Folder | What lives there |
|---|---|
| `lib/app/` | App root, sign-in gate, the adaptive shell (tab bar, rail, sidebar), macOS menu bar, keyboard shortcuts |
| `lib/features/` | One folder per area: `transactions`, `revenue`, `charts`, `settings`, `sign_in`. Screens, their notifiers and widgets |
| `lib/services/` | RevenueCat API client and auth, local stores (fees, currency, icons, sort), exchange rates, telemetry, the home-screen widget channel |
| `lib/models/` | API response models |
| `lib/core/` | Constants, extensions, formatting and date utilities, motion helpers |
| `lib/theme/` | Design tokens, colors, typography, breakpoints |
| `lib/widgets/` | Shared UI: cards, grouped lists, badges, side panel, logo |
| `ios/RevenueWidgets/`, `android/…/widgets/` | Native home-screen widgets |
| `relay/` | Cloudflare Worker for the web app |

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

## Layouts

`AppBreakpoints` (`lib/theme/app_tokens.dart`) sorts windows into three size
classes:

| Width | Navigation | Content |
|---|---|---|
| < 600 | Floating tab bar | Single column |
| 600–1023 | Navigation rail | Single column, centered |
| ≥ 1024 | Sidebar with shortcuts | Side-by-side columns; details open in a side panel |

Screens decide columns from their own width with `LayoutBuilder`, so they
also work inside split views. Phones are locked to portrait; tablets rotate.

## Web

Browsers can't call RevenueCat's API (it allows only its own dashboard as a
CORS origin), so web builds send API calls to the relay, set by
`OPENRC_RELAY_URL`. See [relay/README.md](../relay/README.md). The app is
otherwise the same code; home-screen widgets are skipped.

## Telemetry

`lib/services/telemetry.dart` wraps PostHog. It does nothing unless the build
has `POSTHOG_PROJECT_TOKEN`. When on, it records anonymous screen views, a
handful of events (signed in, signed out) and uncaught errors, with no person
profiles and no session replay. Users can switch it off in Settings.
