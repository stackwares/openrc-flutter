# Contributing to OpenRC

Thanks for helping. Bug reports, ideas, docs fixes and code are all welcome.

## Before you start

- **Bugs:** [open an issue](https://github.com/stackwares/openrc/issues/new/choose)
  with steps to reproduce, your platform, and the app version (Settings →
  bottom of the page). Leave out revenue figures, emails and tokens.
- **Features:** open an issue first so we can agree on the shape before you
  spend time on it.
- **Security issues:** report privately; see [SECURITY.md](SECURITY.md).

## Set up

You need:

- [Flutter](https://docs.flutter.dev/get-started/install) 3.47 or later
- Xcode (iOS, macOS) and/or Android Studio (Android)
- Node.js 20 or later, only if you work on the web relay or the notifier

```bash
git clone https://github.com/stackwares/openrc.git
cd openrc
flutter pub get
flutter run
```

For the web app, run the [relay](relay/README.md) locally and point the app
at it with `--dart-define=OPENRC_RELAY_URL=http://127.0.0.1:8787`.

A RevenueCat account with at least one project is enough to see real data.
Builds from source send no telemetry and have no push notifications. To work
on notifications, add your own Firebase project
(`dart_defines/firebase.example.json`) and run the
[notifier](notifier/README.md). The iOS app has the Push Notifications
capability, which free (personal) Apple teams can't sign; remove
`aps-environment` from `ios/Runner/Runner.entitlements` locally if you use
one.

## Make a change

1. Fork the repo and create a branch from `main`.
2. Keep the change focused: one fix or feature per pull request, no
   unrelated reformatting.
3. Add or update tests for behavior you change. Widget tests live in
   `test/`, relay tests in `relay/test/`, notifier tests in
   `notifier/test/`.
4. Run the checks:

   ```bash
   flutter analyze
   flutter test
   # if you touched relay/ or notifier/
   cd relay && npm run typecheck && npm test
   cd notifier && npm run typecheck && npm test
   ```

5. Open a pull request and fill in the template. Screenshots or a short
   recording help a lot for UI changes; show phone and wide layouts if both
   are affected.

## Conventions

- **State:** Riverpod providers live next to the feature or in
  `lib/services/`. Keep widgets free of API calls.
- **Design system:** use the tokens in `lib/theme/` (`AppSpace`,
  `AppRadius`, `AppText`, `context.appColors`) and the shared widgets in
  `lib/widgets/` before adding new styles.
- **Layouts:** check phone (< 600 wide), tablet (600–1023) and wide
  (≥ 1024) windows. `context.windowSize` and `AppBreakpoints` decide which
  layout a screen uses.
- **Motion:** use `AppMotion.of(context, …)` so animations respect the
  system's reduced-motion setting.
- **Accessibility:** give icon-only buttons a tooltip or semantics label,
  and keep text readable at large font sizes.
- **Privacy:** never send user data to telemetry, and keep the relay and
  the notifier stateless. See the privacy rules in [AGENTS.md](AGENTS.md).
- **Commits:** short, imperative, [Conventional Commits](https://www.conventionalcommits.org)
  style, for example `fix(revenue): count refunds in the month total`.

## Using AI coding agents

Agents should follow [AGENTS.md](AGENTS.md). You are responsible for every
line you submit, so read and test it like your own.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
