import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/ask/ask_screen.dart';
import 'package:openrc/features/ask/widgets/ask_composer.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/services/onboarding_prefs_store.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:openrc/widgets/app_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends AgentSettingsNotifier {
  @override
  Future<AgentSettings> build() async => const AgentSettings(
    providerId: AgentProviderId.openrouter,
    model: '',
    customBaseUrl: '',
    customStyle: AgentApiStyle.openAi,
    useFasterModel: false,
    hasKey: true,
  );

  @override
  Future<Set<AgentProviderId>> providersWithKeys() async => {};
}

Future<void> _pumpAsk(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        onboardingPrefsProvider.overrideWith(
          (ref) => OnboardingPrefsNotifier.loaded(
            const OnboardingPrefs(aiConsentGranted: true),
          ),
        ),
        agentSettingsProvider.overrideWith(_Settings.new),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(FlexScheme.indigoM3),
        home: const Scaffold(body: AskScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the empty thread centers the mascot above its words', (
    tester,
  ) async {
    await _pumpAsk(tester, const Size(430, 900));

    expect(find.byType(AppLogo), findsOneWidget, reason: 'the mascot is out');
    final logo = tester.getRect(find.byType(AppLogo));
    final title = tester.getRect(find.text('Nothing asked yet'));
    final subtitle = tester.getRect(
      find.text('Ask about today, MRR, countries, or when you get paid.'),
    );
    final firstSuggestion = tester.getRect(
      find.text('How was today vs yesterday?'),
    );
    final composer = tester.getRect(find.byType(AskComposer));

    // Horizontally centered on the screen.
    expect(logo.center.dx, moreOrLessEquals(430 / 2, epsilon: 1));
    expect(title.center.dx, moreOrLessEquals(430 / 2, epsilon: 1));
    expect(subtitle.center.dx, moreOrLessEquals(430 / 2, epsilon: 1));

    // Mascot, words, then the starter questions by the composer.
    expect(logo.bottom, lessThan(title.top));
    expect(title.bottom, lessThanOrEqualTo(subtitle.top));
    expect(subtitle.bottom, lessThan(firstSuggestion.top));
    expect(firstSuggestion.bottom, lessThan(composer.top));

    // The mascot is the focal point: mid-way in the free space above the
    // suggestions, not glued to either edge.
    final header = tester.getRect(find.byType(AskScreen));
    expect(logo.top - header.top, greaterThan(40));
    expect(logo.size.width, greaterThanOrEqualTo(96));
  });

  testWidgets('a short window scrolls instead of overflowing', (tester) async {
    // Roughly a phone with the keyboard up.
    await _pumpAsk(tester, const Size(430, 380));

    expect(tester.takeException(), isNull);
    expect(find.byType(AppLogo), findsOneWidget);

    // The suggestions stay reachable by scrolling.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('How was today vs yesterday?'), findsOneWidget);
  });

  testWidgets('a tall window keeps the mascot centered, not top-hugging', (
    tester,
  ) async {
    await _pumpAsk(tester, const Size(430, 1400));
    final logo = tester.getRect(find.byType(AppLogo));
    final firstSuggestion = tester.getRect(
      find.text('How was today vs yesterday?'),
    );
    final spaceAbove = logo.top;
    final spaceBelow = firstSuggestion.top - logo.bottom;
    expect(
      spaceAbove,
      greaterThan(60),
      reason: 'the mascot sits inside the free space, not on the header',
    );
    expect(spaceBelow, greaterThan(0));
  });
}
