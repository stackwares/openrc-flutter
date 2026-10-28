import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/onboarding/onboarding_pages.dart';
import 'package:openrc/features/onboarding/onboarding_screen.dart';
import 'package:openrc/features/onboarding/onboarding_steps.dart';
import 'package:openrc/services/onboarding_prefs_store.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingPrefsProvider.overrideWith(
            (ref) => OnboardingPrefsNotifier.loaded(const OnboardingPrefs()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(FlexScheme.indigoM3),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const OnboardingScreen(trackAnalytics: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double topOfWelcome(WidgetTester tester) =>
      tester.getTopLeft(find.text('OpenRC')).dy;

  testWidgets('a phone fills the screen', (tester) async {
    await pump(tester, const Size(430, 1100));
    expect(tester.takeException(), isNull);

    // One gutter either side of the screen; the column is capped, but a phone
    // is narrower than the cap.
    final scroll = tester.getRect(find.byType(SingleChildScrollView));
    expect(scroll.width, 430 - 40);
    expect(scroll.left, 20);
  });

  testWidgets('a wide window keeps a column, not the whole width', (
    tester,
  ) async {
    await pump(tester, const Size(1440, 960));
    expect(tester.takeException(), isNull);

    final scroll = tester.getRect(find.byType(SingleChildScrollView));
    expect(scroll.width, kOnboardingWideColumnWidth);
    // Centered: the same empty space either side.
    expect(scroll.left, (1440 - kOnboardingWideColumnWidth) / 2);
  });

  testWidgets('a tall window caps the band and centers it', (tester) async {
    await pump(tester, const Size(1440, 960));
    final short = topOfWelcome(tester);

    await pump(tester, const Size(1440, 1200));
    final tall = topOfWelcome(tester);

    // 240 pixels more window, 120 more above the band: it grew to its cap and
    // then centered, instead of leaving the call to action at the bottom edge.
    expect(tall - short, 120);
  });

  testWidgets('the last page repeats the answers it was given', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OnboardingReadyPage(
              role: OnboardingAnswers.roleStudio,
              focus: OnboardingAnswers.focusRevenue,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Small studio'), findsOneWidget);
    expect(find.text('Revenue and payouts'), findsOneWidget);
  });

  testWidgets('a short window tightens the header and still shows the button', (
    tester,
  ) async {
    await pump(tester, const Size(900, 420));
    expect(tester.takeException(), isNull);

    final cta = tester.getRect(find.byType(FilledButton));
    expect(cta.bottom, lessThanOrEqualTo(420));
    expect(find.text('Continue'), findsOneWidget);
  });
}
