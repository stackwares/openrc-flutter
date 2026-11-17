# OpenRC — Support knowledge

> Reference for customer support agents. Answer from this file first; read the code only if it
> doesn't cover the question. Last verified: version 1.0.4+11, commit f6ae6a9, 2026-11-17.

## At a glance
- **What it is:** a free, open-source (MIT) dashboard for a developer's own
  [RevenueCat](https://www.revenuecat.com) account. It shows sales as they happen, this month's
  revenue, upcoming store payouts and RevenueCat's charts. It is an independent project and is
  **not affiliated with RevenueCat, Inc.** (and not the Linux init system of the same name).
- **Platforms:** iPhone, iPad, Android, Mac, and the web at
  [openrc-app.pages.dev](https://openrc-app.pages.dev). Source:
  [github.com/stackwares/openrc-flutter](https://github.com/stackwares/openrc-flutter).
  Store availability is UNVERIFIED: the README lists the App Store, Google Play and Mac App Store as
  "coming soon", while a Google Play listing text exists in the repo.
- **Identifiers:** bundle ID and Android package `com.openrc.app` (iOS widgets
  `com.openrc.app.widgets`); analytics slug `openrc`.
- **Languages:** English, Arabic, German, Spanish (Spain), French, Hindi, Indonesian, Japanese,
  Portuguese (Brazil), Russian, Simplified Chinese. Changed in `Settings → Appearance → Language`
  (`System` follows the device).
- **Requires:** an existing RevenueCat account that signs in with **email and password** (two-factor
  codes supported), and an internet connection. Notifications permission only if the user turns on
  push notifications. There is no OpenRC account and nothing to buy.

## Features

### Home (transactions)
- The first tab, `Home`, lists the day's transactions with app icons, product, country and store,
  a running total against yesterday and a seven-day strip. Step days with the previous/next arrows
  in the header, or tap the title (`Go to a day`) to pick a date.
- Filter by project, store and country; filter by type (new subscriptions, renewals, trials,
  conversions, refunds, cancellations). Tap a transaction for its details (customer, entitlements,
  history).
- **Looking ahead:** today's card shows what the day is on track for, `Due later today` lists
  renewals and conversions still to come, and the day navigation can step up to 30 days into the
  future (projected days).
- **Search** (magnifier on Home): finds *loaded* transactions by store transaction ID (Apple's
  numeric IDs, Google `GPA.` order IDs), customer ID, product ID or name, project, store or country.
  It only searches transactions already loaded in the app. For an older sale, paste the customer ID
  and use `Look up customer`, which asks RevenueCat directly in a chosen project.
- Stores are called **Apple** and **Google** throughout the app (also `Stripe` where RevenueCat
  reports it).

### Revenue
- This month's revenue and breakdowns by store, new vs. renewals, top apps and top countries.
- `Next payouts`: estimated upcoming Apple and Google payouts (Apple's fiscal calendar), plus
  `Payout history` for the last 12 months. Payouts are **estimates** from RevenueCat proceeds after
  store fees and estimated taxes; actual payments can differ (exchange rates, tax withholding,
  payment minimums). Refund timing differs between RevenueCat and the stores, so totals can differ
  slightly.
- `Coming up` card and `Upcoming` screen (next 7 or 30 days): renewals, trials converting or
  ending, subscriptions set to expire, expected charges and revenue at risk. Estimated on the device
  from each subscription's latest transaction; billing failures, refunds and price changes can't be
  seen ahead of time, and stores can charge up to a day early.

### Charts
- MRR, ARR, revenue, proceeds, subscriptions, trials, users, churn and more, from RevenueCat.
  Ranges: `7 days`, `30 days` or `Custom`.

### Ask (optional, bring your own AI key)
- The fourth tab answers questions about the user's RevenueCat numbers with charts and tables.
- Off until the user adds their own API key from an LLM provider: OpenRouter, OpenAI, Anthropic,
  DeepSeek, or `Custom` (own base URL; native apps only, not on the web).
- On iPhone, iPad and Mac, Ask also needs the `Allow Ask` switch (`Settings → Privacy → Allow Ask`,
  or `Allow Ask` on the Ask tab / during first-run setup). Android and web don't show this switch.
- Any usage cost is billed by the user's AI provider, not by OpenRC.

### Product names
- `Settings → Revenue → Product names`: give store product IDs friendly names and group them into
  plans. Names stay on this device and appear everywhere, including notifications. Names are built
  from sales already loaded: if the list is empty (`No products loaded`), open the transactions list
  first.
- `Suggest names`: `Built-in names` reads the billing period from the product ID offline;
  `Suggest with AI` uses the connected Ask model and sends only product IDs and their billing
  periods (no revenue or customer data). Suggestions are shown for review, never applied silently.

### Display currency and store fees
- `Settings → Revenue → Display currency`: about 100 currencies, converted from US dollars at
  current exchange rates.
- `Settings → Revenue → Subtract store fees`: shows revenue after store fees. `Apple fee` and
  `Google fee` are editable (0–100%); first-run setup uses 15% for both.

### Push notifications (optional)
See "Notifications" under Accounts and data for how it works and the privacy details.
- `Settings → Notifications → Push notifications`. Available on iPhone, iPad, Android, Mac and in
  browsers that support web push. Not offered in builds without notification settings, and not on
  Windows or Linux.
- Choose projects, the kinds of event (`Everything` by default; presets `Sales only`,
  `New customers`; or individual kinds such as `Renewals`, `Refunds`, `Billing issues`), per-project
  overrides, `Sandbox purchases` (off by default), and `Send a test notification`.
- Amounts follow the display currency and store fee settings; tapping a notification opens the
  transaction.

### Home screen widgets
- iOS and Android home screen widgets (transactions, revenue, insights). Widget data is cleared on
  `Log out`.

### Desktop and large screens
- Navigation rail on tablets, sidebar on wide windows, side panels. The Mac app has a menu bar with
  shortcuts (⌘1–⌘4 for tabs, ⌘, Settings, ⌘[ / ⌘] previous/next day, ⌘R refresh, ⇧⌘K Ask about the selected day) and a
  Help menu with `OpenRC on GitHub` and `Report an Issue`.
- Phones stay in portrait; tablets rotate and support Split View.
- Coming back to the app after five minutes or more reloads Transactions, Revenue and Charts.

## How to…

### Connect a RevenueCat account (sign in)
1. Open OpenRC. A short first-run setup appears once (`Skip` is available), ending with
   `Sign in with RevenueCat`.
2. Enter the RevenueCat dashboard **email and password**, tap `Sign in`.
3. If the account has two-factor authentication, enter the 6-digit code from the authenticator app
   and tap `Verify`.

Safety points to tell users:
- The password goes **straight to RevenueCat** and is never saved by OpenRC
  (`Your password goes straight to RevenueCat and is never saved.`). Native apps talk to
  RevenueCat directly; the web app passes through OpenRC's stateless relay, which doesn't store or
  log requests, tokens or headers.
- After sign-in, only RevenueCat's **session token** is kept, in the device's secure storage
  (Keychain on Apple devices, Android Keystore on Android; in the web app, the browser's storage for
  the site). The last email used is remembered on the device to prefill the form.
- OpenRC does **not** use RevenueCat project API keys (secret `sk_` keys or public SDK keys). Users
  should never paste RevenueCat API keys into OpenRC or send them to support.
- Single sign-on (SSO) is not supported: the app signs in with email and password only. Users whose
  organization requires SSO must use RevenueCat's website.
- Lost authenticator: the app does not accept recovery codes. `Lost your authenticator? Use a
  recovery code` opens RevenueCat's website, where they sign in with a recovery code.
- Forgot password: `Forgot password?` opens app.revenuecat.com to reset it there; then sign in again
  in OpenRC.

### Switch to a different RevenueCat account
One account at a time. `Settings → Account → Log out`, confirm, then sign in with the other account.

### Turn on push notifications
1. `Settings → Notifications → Push notifications` → `Turn on notifications`.
2. Allow notifications when the system asks.
3. Under `Which projects?`, pick projects and tap `Turn on for N projects`. OpenRC adds a webhook
   for this device to each one. Done shows `You're all set`.
4. Optional: `Send a test notification` checks the whole path from RevenueCat to the device.

New RevenueCat projects show as `On · N new projects to set up`; open the screen to add them.

**iPhone/iPad web app:** Safari can only receive notifications when OpenRC is added to the Home
Screen (`Share → Add to Home Screen`) and opened from there.

### Set up notifications manually (without letting the app edit RevenueCat)
`Settings → Notifications → Push notifications → Set up manually` shows a `Webhook URL` and an
`Authorization header` to copy. In RevenueCat: project → Integrations → Webhooks → add a webhook,
paste both, pick environment and events, save, then use Send test event. The header works like a
password for this device's notifications: paste it only into RevenueCat, never share it (including
with support).

### Turn off notifications / remove webhooks
- `Turn off notifications` removes this device's webhooks from the user's RevenueCat projects.
- To see or delete webhooks in a project, tap the project on the notifications screen →
  `Webhooks`. The header button `All webhooks` can delete every webhook that isn't this device's,
  across all projects. **Warn users:** this also stops other devices, other OpenRC installs and any
  other services (their own servers, integrations) from receiving events, and can't be undone.

### Use Ask
Ask tab → add a provider API key (`Add API key` / `Connect your LLM`) → `Save and start`. On Apple
devices, turn on `Allow Ask` first. Change or remove the key in `Settings → Ask → Provider`
(`Remove key`).

### Turn off anonymous usage stats
`Settings → Privacy → Share anonymous usage` (shown only in builds that include analytics).

### Find the app version
Bottom of Settings: `Version x.y.z (build)`.

### Replay the first-run introduction
`Settings → Help → Watch the introduction`.

## Plans, trial and purchases
- OpenRC is **free**. There are no in-app purchases, subscriptions, Pro tier, trial or ads in the
  app at this commit.
- The purchases and subscriptions shown in OpenRC are the **user's own customers'** transactions
  from RevenueCat. OpenRC cannot change, refund or cancel them; that is done in RevenueCat, App Store
  Connect or Google Play Console.
- Ask uses the user's own AI provider key; that provider bills the user directly.

## Accounts and data
- **Sign-in model:** RevenueCat account (email + password, optional 2FA). No OpenRC account, no
  anonymous account, no Firebase sign-in.
- **Where data lives:** RevenueCat data is fetched from RevenueCat on demand and shown on the device
  (some is cached locally, such as saved payouts). OpenRC has no server that stores it. Settings
  (theme, currency, fees, product names, notification choices) are stored only on this device and do
  **not** sync between devices.
- **Session expiry:** when RevenueCat's session ends, the app returns to sign-in with
  `Your session ended. Sign in again with your RevenueCat account.` Notifications keep working
  through an expired session until the user logs out.
- **Log out** (`Settings → Account → Log out`): removes this device's notification webhooks from
  RevenueCat, signs out of RevenueCat, clears widget data, saved payouts, the Ask conversation and the
  stored session. It does **not** delete Ask provider keys (remove them with `Remove key`).
- **Uninstall / new device:** nothing to lose besides local settings (product names, currency, fee
  rates, notification choices). Sign in again and redo those settings. Before uninstalling, turn off
  notifications or log out so the device's webhooks are removed; otherwise the user can delete them
  later from another install (`Webhooks`) or in RevenueCat.
- **Account deletion:** there is no OpenRC account to delete. RevenueCat account deletion is handled
  by RevenueCat.
- **Distinct ID:** `Settings → Account → Distinct ID` shows the RevenueCat account's ID with a copy
  button. It is not needed for support in normal cases.

### API keys and secrets the app stores
| What | Where it's stored | Removed by |
|---|---|---|
| RevenueCat session token (not the password) | Device secure storage | `Log out`, uninstall, or session expiry |
| Ask provider API key (one per provider) | Device secure storage | `Settings → Ask → Provider → Remove key` (not by Log out) |
| Notification key (random, per device) | Device secure storage; also inside this device's RevenueCat webhook as its authorization header | `Log out` deletes it; `Turn off notifications` removes the webhooks |

### Notifications (how it works)
- Turning notifications on creates a random key on the device. The device subscribes to a
  notification channel named after a hash of that key. OpenRC then uses the RevenueCat session to add
  a webhook to each chosen project, with the key as its authorization header.
- RevenueCat sends each event to OpenRC's notifier (a Cloudflare Worker). The notifier reads the
  event in memory, writes a short notification (event type, price, product, country, store,
  project name) and hands only that text, the store transaction ID and RevenueCat's event ID to
  Firebase Cloud Messaging, which delivers it (through Apple Push Notification service on Apple
  devices). It stores no events, keys or device list, and doesn't log them.
- The device's display currency, fee rates, product names and project icon travel inside its own
  webhook URL in RevenueCat, so the notification matches the app's settings.
- If webhooks can't be removed at the time (offline), OpenRC retries the next time it opens; the
  user can also delete them in RevenueCat.

### Privacy and analytics
- **Usage stats (official builds):** anonymous crash reports, screen names and app events go to
  PostHog. **On by default**; turn off at `Settings → Privacy → Share anonymous usage`. No email,
  RevenueCat account, app names, product names, prices or revenue are sent, and users are never
  identified. Builds from source send nothing unless the builder adds their own PostHog key.
- **Session replay:** on in the native apps (not web), with every piece of text, every image and all
  charts masked before recording, so replays show layout and navigation only. It follows the same
  `Share anonymous usage` switch.
- **Ask:** the question and the RevenueCat data it needs (subscriber IDs redacted) go to the chosen
  AI provider, never the RevenueCat session. On web it passes through the same stateless relay.
- **Other network requests (code-confirmed):** exchange rates come from a free public currency
  data source; app icons are looked up from the public App Store / Google Play listings by bundle ID
  (on web via the relay).
- Privacy policy: [PRIVACY.md](https://github.com/stackwares/openrc-flutter/blob/main/PRIVACY.md);
  privacy contact dev@stackwares.com.

## Troubleshooting
| Symptom | Likely cause | What to tell the user |
|---|---|---|
| `That email and password don't match a RevenueCat account.` | Wrong credentials, or the account normally signs in with Google/SSO | Check the email and password on app.revenuecat.com. Reset via `Forgot password?`. SSO accounts can't sign in to OpenRC. Whether a password can be added to a Google/GitHub-login RevenueCat account is UNVERIFIED; direct them to RevenueCat Support. |
| `That code didn't work. Codes change every 30 seconds, so use the newest one.` | Old or mistyped 2FA code, or device clock drift | Use the newest code; check the phone's automatic time setting. |
| `Too many attempts. Wait a minute, then try again.` | RevenueCat rate-limited sign-in | Wait a minute and retry. |
| Lost authenticator | App doesn't accept recovery codes | Use a recovery code on RevenueCat's website; recovering 2FA is RevenueCat's job. |
| `Your session ended…` / `Your session has expired. Please sign in again.` | RevenueCat session expired or was revoked | Sign in again. |
| `No internet connection. Check your network and try again.` | Offline | Check the connection, then `Try again`. |
| `RevenueCat is taking too long to respond.` / `RevenueCat is having trouble right now.` | RevenueCat slow or down | Retry later; check RevenueCat's status page. |
| `Too many requests. Please wait a moment.` | RevenueCat API rate limit | Wait and retry. |
| `Couldn't load data` | Any failed load | Tap `Try again`. |
| Numbers differ from RevenueCat's dashboard | Display currency conversion, `Subtract store fees` on, own fee rates, local time zone day boundaries | Check `Settings → Revenue`. OpenRC recomputes day totals in the device's time zone and converts from US dollars at current rates. |
| Payout amount differs from what Apple/Google paid | Payouts are estimates | Expected; see the note on the payout screen (taxes, exchange rates, minimums, refund timing). |
| `Payouts by store aren't available` | RevenueCat didn't return revenue by store | Nothing to fix in the app; try later. |
| Search finds nothing for an old sale | Search covers loaded transactions only | Use `Look up customer` with the customer ID. |
| `No products loaded` in Product names | No transactions loaded yet | Open the Home list first, then return. |
| `Blocked in your device's settings` | Notification permission denied | `Open Settings` and allow notifications for OpenRC, then come back. |
| `Not available in this browser` / iPhone web can't enable | Browser lacks web push; Safari on iPhone/iPad outside a Home Screen app | Add OpenRC to the Home Screen from Safari's Share menu and open it from there, or use another browser. |
| `Notifications are blocked for this site.` | Browser site permission denied | Allow notifications in the browser's site settings. |
| `Couldn't turn on notifications.` / `N projects couldn't be set up.` | Network error or RevenueCat refused the webhook change | Check the connection and try again. Their RevenueCat role may lack permission to edit integrations (UNVERIFIED); `Set up manually` is the alternative. |
| `RevenueCat couldn't reach OpenRC's notifier (code).` on test | Notifier or delivery problem | Retry later; if it persists, escalate with the code shown. |
| Test sent but nothing arrives | Focus/Do Not Disturb, battery restrictions, Mac build without push entitlement | Check system notification settings and Focus. Delivery is best effort. |
| Notifications stopped after deleting webhooks | Deleted this device's own webhook (`This device` section) or used `All webhooks` on another install | Turn notifications on again for those projects. |
| Notifications still arrive after uninstalling / on an old device | The old device's webhooks remain in RevenueCat | Delete them in RevenueCat (Integrations → Webhooks) or from `Webhooks` on another install. |
| No notifications for test purchases | `Sandbox purchases` is off | Turn on `Sandbox purchases`. |
| Ask: `That API key was rejected.` | Wrong key or provider | Check the key and the selected provider. |
| Ask: `The provider rate-limited this request.` | Provider quota or billing | Check the account with that AI provider. |
| Ask: `Custom hosts aren't available on the web relay.` | Custom base URL used on web | Use a listed provider on web, or the native app. |
| Ask: `This relay doesn't support Ask yet.` | Web build pointing at a relay without Ask | Use the native app; if on the official web app, escalate. |
| Ask tab shows `Ask is off for now` (Apple devices) | `Allow Ask` is off | Tap `Allow Ask`, or `Settings → Privacy → Allow Ask`. |
| Product names: "Allow AI data use under Settings, Privacy" | The message refers to the `Allow Ask` switch | `Settings → Privacy → Allow Ask`. |

## Known issues and limitations
- Sign-in is email + password only; no SSO, no recovery-code entry in the app.
- One RevenueCat account at a time.
- Search only covers loaded transactions.
- Upcoming and payouts are estimates.
- Settings and product names don't sync across devices.
- Notifications aren't offered on Windows/Linux, in builds without notification settings, or in
  browsers without web push. Product names in notifications are capped in length (long lists fall
  back to product IDs).
- Custom AI hosts work only in the native apps.
- Fixed in unreleased work after 1.0.4 (per CHANGELOG): turning notifications on for a project with
  many named products used to fail.

## Recent changes
The CHANGELOG has a single `[Unreleased]` section and no dated version entries; versions below come
from commit messages.
- Unreleased (after 1.0.4): search by transaction/customer/product ID with customer lookup;
  `Coming up` / `Upcoming` projections and look-ahead days on Home; auto-refresh after five minutes
  away and after a push; notifications in another currency also show the US dollar amount; fix for
  enabling notifications on projects with many named products.
- 1.0.4: broader anonymous analytics with masked session replay; stores named Apple and Google;
  AI product naming in batches; Mac app receives push notifications.
- 1.0.2: Ask provider sheet key reveal fix; one segmented control style.
- 1.0.1: translations for all shipped languages; product names in notifications; see and clear
  project webhooks; first-run setup before sign-in.

## Policies and escalation
- Privacy policy: [PRIVACY.md](https://github.com/stackwares/openrc-flutter/blob/main/PRIVACY.md).
  No terms of service document exists in the repo (UNVERIFIED whether one is published elsewhere).
- Bugs and feature requests: GitHub issues on the repository (Mac: `Help → Report an Issue`).
- Security vulnerabilities: report privately via GitHub's Security → Report a vulnerability, never
  in a public issue.
- Privacy questions: dev@stackwares.com. RevenueCat account, billing or data questions:
  [RevenueCat Support](https://www.revenuecat.com/support/).
- Escalate to the developer when: a suspected leak of a session, API key or notification header,
  security reports, data that looks wrong after checking currency/fee settings, notifier test
  failures that persist, crashes that persist after update/reinstall, anything not covered here.
- Ask the user for: app version (bottom of Settings), platform (iOS/Android/Mac/web and browser),
  device and OS, the exact error text, and a screenshot with amounts hidden if they prefer.

## Never say
- Never ask for the RevenueCat password, 2FA or recovery codes, RevenueCat API keys, AI provider
  keys, or the notification `Authorization header`.
- Never claim OpenRC is made by, endorsed by or affiliated with RevenueCat.
- Never claim OpenRC can refund, cancel or change the user's customers' purchases.
- Don't promise store release dates, upcoming features, or that estimates (payouts, Upcoming) are
  exact.
- Never suggest `All webhooks` deletion without warning that it stops other devices and services.
- Don't share internal details (code, infrastructure endpoints, other users' data).
