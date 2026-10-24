import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/onboarding/onboarding_screen.dart';
import 'package:openrc/services/onboarding_prefs_store.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(
    WidgetTester tester, {
    bool trackAnalytics = true,
    OnboardingPrefs prefs = const OnboardingPrefs(),
  }) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingPrefsProvider.overrideWith(
            (ref) => OnboardingPrefsNotifier.loaded(prefs),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(
            FlexScheme.indigoM3,
          ).copyWith(splashFactory: InkRipple.splashFactory),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: OnboardingScreen(trackAnalytics: trackAnalytics),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FilledButton cta(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('role and focus keep Continue disabled until a choice', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('What describes you best?'), findsOneWidget);
    expect(cta(tester).onPressed, isNull);

    await tester.tap(find.text('Indie'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Continue as an indie'), findsOneWidget);
    expect(cta(tester).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue as an indie'));
    await tester.pumpAndSettle();

    expect(find.text('Where do you want to start?'), findsOneWidget);
    expect(cta(tester).onPressed, isNull);

    await tester.tap(find.text('Charts').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Continue to charts'), findsOneWidget);
    expect(cta(tester).onPressed, isNotNull);
  });

  testWidgets('preview does not write last-step or complete', (tester) async {
    await pump(tester, trackAnalytics: false);
    expect(find.text('OpenRC'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(OnboardingPrefsNotifier.lastStepKey), isNull);
    expect(prefs.getBool(OnboardingPrefsNotifier.completedKey), isNot(true));

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(prefs.getBool(OnboardingPrefsNotifier.completedKey), isNot(true));
    expect(prefs.getString(OnboardingPrefsNotifier.lastStepKey), isNull);
  });

  testWidgets('first-launch records the welcome step', (tester) async {
    await pump(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(OnboardingPrefsNotifier.lastStepKey), 'welcome');
    expect(prefs.getInt(OnboardingPrefsNotifier.lastStepIndexKey), 0);
  });
}
