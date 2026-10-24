# Releasing

How official OpenRC builds get to testers and the web. Forks can follow the
same steps with their own accounts.

| Target | Channel |
|---|---|
| Android | Firebase App Distribution (APK) |
| iPhone and iPad | Firebase App Distribution (ad-hoc IPA) |
| Web | Cloudflare Pages, with the relay on Cloudflare Workers |

The app's only Firebase SDK is Cloud Messaging, for push notifications. App
Distribution receives the finished builds through the `firebase` CLI.

## One-time setup

### Firebase App Distribution

1. In a Firebase project, add an **Android app** with package
   `com.openrc.app` and an **iOS app** with bundle ID `com.openrc.app`. You
   don't need the config files they offer; only the **App IDs**
   (`1:…:android:…` and `1:…:ios:…`).
2. In App Distribution, create a tester group, for example `testers`.
3. Keep the IDs out of the repo, for example in your shell profile:

   ```bash
   export OPENRC_FIREBASE_ANDROID_APP_ID=1:…:android:…
   export OPENRC_FIREBASE_IOS_APP_ID=1:…:ios:…
   ```

### Android signing

Testers can only update in place if every build is signed with the same key.
Release builds currently fall back to the debug key, which differs per
machine. Before the first build that testers keep, create an upload keystore
and sign release builds with it (never commit the keystore or its passwords).

### Apple

1. Register the identifiers (Xcode's automatic signing can do this on the
   first archive): app `com.openrc.app` and widgets `com.openrc.app.widgets`,
   both with the **App Groups** capability, and the App Group
   `group.com.openrc.app.widgets`.
2. Register each tester's iPhone or iPad in the Apple Developer account. Ad-hoc
   builds only install on registered devices.

### Push notifications (optional)

1. In the Firebase project, register the Android app (`com.openrc.app`) and
   the Apple app (`com.openrc.app`) if App Distribution hasn't already, and
   copy their API keys and app IDs into `dart_defines/firebase.json` (from
   `dart_defines/firebase.example.json`). It is gitignored. Without it,
   builds have no notifications.
2. Upload an APNs authentication key under **Project settings → Cloud
   Messaging**, and give the app ID `com.openrc.app` the **Push
   Notifications** capability (Xcode's automatic signing can do this).
3. Deploy the notifier (`notifier/README.md`) with a service account key from
   the same project.
4. For the web app, register a web app in the same Firebase project and
   generate a web push key under **Project settings → Cloud Messaging → Web
   Push certificates**, then add `FIREBASE_WEB_API_KEY`,
   `FIREBASE_WEB_APP_ID` and `FIREBASE_VAPID_KEY` to `firebase.json`.

### Telemetry (optional)

Create `dart_defines/posthog.json` from `dart_defines/posthog.example.json`
with the OpenRC PostHog project token. It is gitignored. Without it, builds
send nothing.

### Web

1. Deploy the relay once (`relay/README.md`). Its `ALLOWED_ORIGINS` must list
   the Pages domain.
2. The first `wrangler pages deploy` creates the `openrc-app` Pages project. If
   Cloudflare gives it a different `*.pages.dev` name, update
   `ALLOWED_ORIGINS` in `relay/wrangler.jsonc` and the `og:image` URL in
   `web/index.html`.

## Each release

Bump `version` in `pubspec.yaml` (for example `1.0.1+2`) and add the changes
to `CHANGELOG.md` first. Release builds use production settings: never pass
debug-only defines.

### Android

```bash
flutter build apk --release --dart-define-from-file=dart_defines/posthog.json \
  --dart-define-from-file=dart_defines/firebase.json
firebase appdistribution:distribute build/app/outputs/flutter-apk/app-release.apk \
  --app "$OPENRC_FIREBASE_ANDROID_APP_ID" \
  --groups testers \
  --release-notes "See CHANGELOG.md"
```

### iPhone and iPad

```bash
flutter build ipa --release --export-method ad-hoc --dart-define-from-file=dart_defines/posthog.json \
  --dart-define-from-file=dart_defines/firebase.json
firebase appdistribution:distribute build/ios/ipa/*.ipa \
  --app "$OPENRC_FIREBASE_IOS_APP_ID" \
  --groups testers \
  --release-notes "See CHANGELOG.md"
```

### Web

```bash
(cd relay && npm ci && npm run deploy)      # only when relay/ changed
(cd notifier && npm ci && npm run deploy)   # only when notifier/ changed
flutter build web --release --dart-define-from-file=dart_defines/posthog.json \
  --dart-define-from-file=dart_defines/firebase.json
npx wrangler pages deploy build/web --project-name openrc-app --branch main
```

`web/_headers` ships with the build and sets the security headers.

## Before the stores

App Store and Google Play releases need more than test builds: every
supported language translated (see `AGENTS.md`), store listings, a privacy
policy URL, and store-signed builds.
