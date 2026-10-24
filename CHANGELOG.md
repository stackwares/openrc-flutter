# Changelog

All notable changes to OpenRC are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

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
  refunds and more) on iPhone, iPad, Android and the web, through a stateless
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
- A trials breakdown: with only the Trials tile picked (or a day of only
  trials), the Breakdown card counts trials by status, store, app, country
  and plan instead of showing an all-zero revenue split. On the Revenue
  tab it shows for the month's trials.

### Changed

- The Transactions tab is now Home.

### Removed

- The old Firebase backend (anonymous sign-in, Firestore, Cloud Functions),
  including the unfinished push-alert backend. Notifications now use Cloud
  Messaging alone.

### Fixed

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
