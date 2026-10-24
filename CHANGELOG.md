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
- Layouts for every screen size: navigation rail on tablets, sidebar and
  side-by-side columns on wide windows, transaction details in a side panel.
- Tablets rotate and support Split View; phones stay in portrait.
- New brand: the OpenRC cat, with a Pink Sakura accent by default.
- Android themed (monochrome) icon.
- A simpler sign-in, in the style of the system's own account screens.
- Pickers and forms open as bottom sheets on phones and as dialogs on
  larger screens.
- Optional, anonymous crash reports and usage stats through PostHog, with a
  switch in Settings. Off in builds without a PostHog key.
- Push notifications for RevenueCat events (purchases, renewals, trials,
  refunds and more) on iPhone, iPad and Android, through a stateless
  Cloudflare notifier (`notifier/`) and Firebase Cloud Messaging. Turning them
  on adds a webhook for the device to the RevenueCat projects you pick, and
  turning them off or logging out removes it. Choose which kinds of event
  notify (trials, renewals, refunds…), for all projects or one at a time;
  tapping a notification opens the transaction. Off in builds without
  Firebase settings.

### Removed

- The old Firebase backend (anonymous sign-in, Firestore, Cloud Functions),
  including the unfinished push-alert backend. Notifications now use Cloud
  Messaging alone.
