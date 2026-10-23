# Google Play — App content declarations (OpenRC)

Package: `com.openrc.app`

This file is the **Play Console checklist** aligned with the app and
[`app-content.json`](app-content.json). The `gplay` CLI **cannot** submit most
of these forms; complete them in
[Play Console](https://play.google.com/console/) → **App content**, then keep
`app-content.json` in sync for `gplay validate app-content`.

**Privacy policy URL (store listing):**
`https://github.com/stackwares/openrc-flutter/blob/main/PRIVACY.md`

**Support email:** `dev@stackwares.com`

---

## 1. Privacy policy

- Set the store privacy policy URL to the link above (after `PRIVACY.md` is on
  `main` on GitHub).
- Policy text lives in repo root [`PRIVACY.md`](../../PRIVACY.md).

---

## 2. App access

- **Some or all functionality is restricted** (RevenueCat login required).
- Instructions (paste and adjust credentials in Console secure fields):

  > OpenRC requires a RevenueCat dashboard account. Sign in on the first screen
  > with the test email and password provided below. After sign-in, Transactions,
  > Revenue, Charts, and Settings are available. Optional analytics can be turned
  > off in Settings → Privacy → Share anonymous usage.

- Add a **dedicated test RevenueCat account** (no 2FA, or provide backup codes).
  Do not use a production account with real customer data.

---

## 3. Ads

- **No**, the app does not contain ads.

---

## 4. Content rating (IARC questionnaire)

Answer honestly for a **business / developer tools** app:

- No violence, sexual content, drugs, gambling, or user-generated public content.
- Not designed for children; target **18+** / general business audience.
- No unrestricted web browsing (in-app WebView usage is limited; primary UI is
  native).
- **Financial reference:** app **displays** the developer’s own RevenueCat
  metrics; it does **not** process payments, loans, trading, or crypto wallets.

Re-run the questionnaire when adding major features.

---

## 5. Target audience and content

- **Not a kids / Designed for Families** app.
- Target adults (developers / app publishers using RevenueCat).

---

## 6. Data safety

Align with [`PRIVACY.md`](../../PRIVACY.md) and `lib/services/telemetry.dart`.

### Collected or shared (typical answers)

| Data type | Collected? | Shared? | Purpose | Optional? |
|-----------|------------|---------|---------|-----------|
| **App interactions** (screen names) | Yes, if telemetry on | With PostHog | Analytics | Yes (Settings) |
| **Crash logs / Diagnostics** | Yes, if telemetry on | With PostHog | App functionality / analytics | Yes |
| **App info and performance** | Yes, if telemetry on | With PostHog | Analytics | Yes |
| **Email / Account info** | Processed for login via RevenueCat API; **not** sent to OpenRC servers or PostHog | RevenueCat only (their policy) | App functionality | Required to use app |
| **Financial info** (revenue metrics) | Fetched from RevenueCat for display; stored locally on device | Not sold; not sent to PostHog | App functionality | Core feature |
| **Device or other IDs** | PostHog may use installation/anonymous IDs | PostHog | Analytics | Yes (telemetry off / no token in build) |

### Practices

- Data is **encrypted in transit** (HTTPS).
- User can **request deletion** of local data by logging out or uninstalling.
- **No data sold**.
- **No ads**.

### SDK note

PostHog is in release builds when `POSTHOG_PROJECT_TOKEN` is set. Declare SDK
data collection per [Google’s SDK guidance](https://support.google.com/googleplay/android-developer/answer/10787469).

**Advertising ID:** OpenRC does **not** declare `AD_ID`; PostHog runs without
advertising ID access on Android 13+ (acceptable if you do not use the AD ID).

---

## 7. Financial features declaration

OpenRC **does not** provide banking, loans, payments, crypto exchange, or stock
trading. It **visualizes** data from the user’s own RevenueCat account.

- Usually: **does not provide financial products** / not a financial services
  app — confirm exact wording in Console against current Google definitions.

---

## 8. Other declarations

| Declaration | OpenRC |
|-------------|--------|
| Health apps | Not applicable |
| News apps | Not applicable |
| Government apps | No |
| COVID-19 contact tracing | No |
| Data deletion | Local logout / uninstall; no OpenRC cloud account |

---

## 9. Store settings

- **Category:** Business (or Tools → developer tools, if that fits better in UI).
- **Contact email:** `dev@stackwares.com`
- **Website:** `https://github.com/stackwares/openrc-flutter` or
  `https://openrc-app.pages.dev`

---

## 10. Validate locally

```bash
gplay validate app-content --json @metadata/gplay/app-content.json --package com.openrc.app --strict
```

After Console forms match this inventory, production promote/publish can proceed
(see `docs/RELEASING.md` and `gplay promote` / `gplay publish track`).
