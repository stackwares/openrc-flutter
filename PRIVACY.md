# Privacy Policy

**Last updated: October 24, 2026**

## 1. Introduction

OpenRC ("we", "our", or "us") is an open-source client for your
[RevenueCat](https://www.revenuecat.com) account. This policy explains what
information the app processes, what leaves your device, and what choices you
have.

OpenRC is not affiliated with RevenueCat, Inc. RevenueCat's own policies
apply to their service.

## 2. Summary

- Your **RevenueCat password** is sent **only to RevenueCat** for sign-in. OpenRC
  does not store your password.
- **Sales, revenue, and payout data** are fetched from RevenueCat for **your**
  account and shown on your device. OpenRC does not operate a backend that
  stores this data on native apps.
- **Optional analytics** (official builds only): anonymous crash reports and
  screen names via [PostHog](https://posthog.com). No RevenueCat account
  details, app names, product names, or revenue amounts are sent. You can turn
  this off in **Settings**.
- Builds from source without a PostHog token send **no** analytics.
- **Optional push notifications**: if you turn them on, RevenueCat sends
  events from your projects to the OpenRC notifier, which writes a short
  notification and delivers it through Firebase Cloud Messaging. The notifier
  stores nothing and keeps no list of devices.

## 3. Information you provide

- **RevenueCat credentials** — Email and password (and two-factor codes when
  required) are transmitted directly to RevenueCat's API to authenticate you.
  The session token is stored in the device's secure storage (Android Keystore /
  iOS Keychain).
- **Settings** — Display currency, store fee assumptions, and telemetry
  preference are stored locally on your device.

## 4. Information processed for app functionality

When you are signed in, the app requests data from RevenueCat on your behalf,
including transaction events, revenue metrics, charts, project and app metadata,
and payout information. This data is displayed in the app and cached locally for
performance. OpenRC does not sell this information.

On **web**, requests go through a small **relay** that forwards traffic to
RevenueCat without storing or logging request or response bodies, tokens, or
headers. You may self-host this relay.

## 5. Optional push notifications

Notifications are off until you turn them on in **Settings → Notifications**.
Then:

- **On your device**, OpenRC creates a random key, kept in the device's secure
  storage. Firebase Cloud Messaging gives the install a registration token,
  and the device subscribes to a channel named after a hash of the key.
- **In your RevenueCat projects**, OpenRC uses your RevenueCat session to add a
  webhook for this device to each project you pick, with the key as its
  authorization header. You can also add the webhook yourself instead.
- **RevenueCat** sends each event you chose (for example a purchase, renewal
  or refund) to the OpenRC notifier, as it would to any webhook.
- **The notifier** (a Cloudflare Worker) reads the event in memory and writes
  the notification from its type, price, product identifier, country, store
  and environment. It sends only that text, plus the store's transaction id
  so a tap can open the transaction, to Firebase Cloud Messaging, which
  delivers it to Android devices directly and to Apple devices through Apple
  Push Notification service. The notifier does not store events, keys or
  devices, and does not log them.
- **Turning notifications off** unsubscribes the device and removes its
  webhooks from your projects. **Log out** does the same and deletes the key.
  If a webhook can't be removed at that moment (offline, for example), OpenRC
  tries again the next time it opens, and you can always delete it in
  RevenueCat.

Builds without Firebase settings have no notifications. You may self-host
the notifier.

## 6. Optional analytics and diagnostics

When enabled (and when the build includes a PostHog project token), the app may
send to PostHog:

- Screen or route names (for example Transactions, Revenue, Settings)
- Anonymous product analytics events defined by the app
- Crash and error reports (Flutter, platform, and native exception metadata)
- Application lifecycle events

We configure PostHog **not** to create person profiles and we do **not** call
`identify` with your email or RevenueCat account. You can disable sharing in
**Settings → Share anonymous usage**.

PostHog's policy: [posthog.com/privacy](https://posthog.com/privacy).

## 7. What we do not collect for analytics

We do not send to PostHog (or other analytics in this app):

- RevenueCat passwords or session tokens
- Your email address or RevenueCat distinct ID (for analytics)
- App names, product names, prices, MRR, revenue amounts, or transaction details

## 8. Third-party services

| Service | Purpose | Privacy policy |
|--------|---------|----------------|
| **RevenueCat** | Authentication and dashboard API | [revenuecat.com/privacy](https://www.revenuecat.com/privacy) |
| **PostHog** (optional) | Anonymous usage and crash reporting | [posthog.com/privacy](https://posthog.com/privacy) |
| **Cloudflare** (web relay, notifier, hosting) | Stateless relay and notifier, static web hosting | [cloudflare.com/privacypolicy](https://www.cloudflare.com/privacypolicy/) |
| **Google Firebase Cloud Messaging** (optional) | Delivering notifications you turn on | [firebase.google.com/support/privacy](https://firebase.google.com/support/privacy) |
| **Apple Push Notification service** (optional) | Delivering notifications to iPhone and iPad | [apple.com/legal/privacy](https://www.apple.com/legal/privacy/) |

## 9. Data retention and deletion

- **Local app data** — Removed when you uninstall the app or use **Log out**
  (session cleared from secure storage).
- **PostHog** — Retained according to PostHog's policies; opt out in Settings
  stops new collection from that install.
- **Notifications** — The notifier keeps nothing. Turning notifications off
  or logging out removes the device's webhooks from RevenueCat, and log out
  removes its notification key.
- **RevenueCat** — Governed by RevenueCat's retention and your account settings.

## 10. Security

We use HTTPS for network traffic and platform secure storage for session tokens.
Report security issues privately: see [SECURITY.md](SECURITY.md).

## 11. Children

OpenRC is a business tool for developers and is not directed at children under
13.

## 12. Changes

We may update this policy. The "Last updated" date at the top will change when
we do. Continued use after changes means you accept the updated policy.

## 13. Contact

For privacy questions about OpenRC: **dev@stackwares.com**.

For RevenueCat account or billing data: [RevenueCat Support](https://www.revenuecat.com/support/).
