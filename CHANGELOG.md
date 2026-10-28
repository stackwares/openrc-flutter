# Changelog

All notable changes to OpenRC are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Auto-refresh: coming back to the app after five minutes or more reloads
  Transactions, Revenue and Charts, and a sale's push while the app is open
  now reloads Charts too, once per burst of webhooks. Charts refreshes
  quietly, keeping its numbers on screen, and keeps them if the refresh
  fails.

- Optional analytics cover more of the app while staying anonymous: the build
  channel (`production`, `internal`, `development`) travels with every event so
  dashboards and funnels can be filtered by it, screens are reported across the
  app (transactions, payouts, insights, notifications, product names), the web
  app sends a page view per screen, the sign-in, first-load, notification and
  product-naming steps are events a funnel can be built from, and session
  replay is on for the native apps with all text, images and custom-drawn
  charts masked before anything leaves the device.

- First open-source release as **OpenRC**, under the MIT license.
- Web app, with a stateless Cloudflare relay (`relay/`) to reach RevenueCat's
  API from the browser.
- macOS app with a native menu bar, keyboard shortcuts and a resizable window.
- Layouts for every screen size: navigation rail on tablets, sidebar on
  wide windows, transaction details in a side panel.
- On wide windows, Transactions and Revenue read like a dashboard: project,
  store and country filters on top, the cards in rows, and a sortable table
  of transactions underneath (Revenue now lists the month's transactions).
- Tablets rotate and support Split View; phones stay in portrait.
- New brand: the OpenRC cat, with a Pink Sakura accent by default.
- Android themed (monochrome) icon.
- A simpler sign-in, in the style of the system's own account screens.
- Pickers and forms open as bottom sheets on phones and as dialogs on
  larger screens.
- Optional, anonymous crash reports and usage stats through PostHog, with a
  switch in Settings. Off in builds without a PostHog key.
- Push notifications for RevenueCat events (purchases, renewals, trials,
  refunds and more) on iPhone, iPad, Mac, Android and the web, through a stateless
  Cloudflare notifier (`notifier/`) and Firebase Cloud Messaging. Turning them
  on adds a webhook for the device to the RevenueCat projects you pick, and
  turning them off or logging out removes it. Choose which kinds of event
  notify (trials, renewals, refunds…), for all projects or one at a time;
  amounts follow your display currency and store fees; tapping a
  notification opens the transaction. Off in builds without
  Firebase settings.
- Push notifications name the RevenueCat project each event came from and
  label the plan (`Weekly`, `Monthly`, `Annual`, `3 months`) from the store's
  own purchase and expiration dates.
- Pushes show the RevenueCat project's own icon (`icon_url`) on Android and in
  browsers, so a notification reads as that project's; Apple keeps the app's
  own icon, as it always does.
- A trials breakdown: with only the Trials tile picked (or a day of only
  trials), the Breakdown card counts trials by status, store, app, country
  and plan instead of showing an all-zero revenue split. On the Revenue
  tab it shows for the month's trials.
- Notifications use those product names: each device's webhook URL carries
  the names Settings gave (capped in length), so a push reads `Pro · Monthly`
  instead of `com.acme.pro.monthly`, in the device's own language.
- Product names: give store product ids names you recognise, per app, from
  Settings. Names appear in the transactions list, the detail screen, the
  trials breakdown and Ask. Products can also be grouped into one plan, so
  a monthly and an annual product count as the same plan.
- Naming suggestions: the app labels the billing period it finds in the
  product id (Yearly, Monthly, Weekly, Lifetime, 1 Year, 1 Month, 1 Week),
  or asks the connected Ask model for names and plan groupings. Only the
  product ids and that period mapping are sent; suggestions are shown for
  review and never applied silently.
- The Ask model refines that mapping instead of starting from nothing: each
  id travels with the period the app read from it, the model may correct or
  fill a period in (a `12mo` id it knows is yearly) and name the plan, and a
  period it sends back is checked against the words this app can show. A
  product whose sales never renew keeps its term wherever the mapping came
  from, so a one-year pass reads `1 Year`, never `Yearly`.
- Naming with AI fills the list as it goes: ids are asked for in small
  batches and each reply lands on the rows straight away, so names appear
  while the model is still working, and stopping a run keeps what arrived.

### Changed

- The stores are named by their company throughout the app: **Apple** and
  **Google**, instead of App Store and Google Play (including the store
  filters, the store fee settings and what push, payout and notification copy
  calls them). The onboarding rating prompt still says Google Play, because
  that is the page it opens.
- The Transactions tab is now Home.

### Removed

- The old Firebase backend (anonymous sign-in, Firestore, Cloud Functions),
  including the unfinished push-alert backend. Notifications now use Cloud
  Messaging alone.

### Fixed

- On wide windows the tab headers (title, date picker, previous and next,
  filters, refresh) line up with the cards below instead of sitting at the
  window's edges.
- Analytics events queued when the app is closed or backgrounded are now
  flushed, so the events that led to a crash are not lost.
- Push notifications read the product names Settings gave them for projects
  connected after those names were saved; connecting a project used to write a
  webhook without the names, so pushes showed the store's raw product id until
  the notification settings were opened again.
- “Ask about this” now shows what it attached above the Ask composer, with a
  close button to detach it.
- “Ask about this” now opens Ask from transaction and metric details, side
  panels and other pushed screens instead of switching the tab behind them.
- The Ask message field centers its text and hint vertically.
- The provider sheet's eye button now shows and hides the API key reliably,
  including on the web where a stale hidden input could keep the field
  masked.
- Ask works on the web again: the relay's capability check now allows the app
  to read it, so the web app stops reporting that the relay doesn't support
  Ask.
- The loader under a day's transactions no longer spins on and on: it shows
  only while that day is still loading, and scrolling to the end no longer
  pages through your whole history.
