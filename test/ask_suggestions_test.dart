import 'package:dio/dio.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/ask/ask_screen.dart';
import 'package:openrc/models/agent_block.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/services/agent/agent_conversation_runner.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/services/onboarding_prefs_store.dart';
import 'package:openrc/theme/app_theme.dart';
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

class _Runner extends AgentConversationRunner {
  _Runner(super.ref);

  final prompts = <String>[];

  @override
  Future<List<AgentBlock>> runTurn({
    required String userPrompt,
    required void Function(String status) onStatus,
    required CancelToken cancelToken,
    List<AgentHistoryTurn> history = const [],
  }) async {
    prompts.add(userPrompt);
    return const [
      AgentBlock(
        type: AgentPresentationType.markdown,
        payload: {'markdown': 'Answer.'},
      ),
    ];
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(
    WidgetTester tester, {
    void Function(_Runner runner)? onRunner,
  }) async {
    tester.view.physicalSize = const Size(430, 1200);
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
          agentConversationRunnerProvider.overrideWith((ref) {
            final created = _Runner(ref);
            onRunner?.call(created);
            return created;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(FlexScheme.indigoM3),
          home: const Scaffold(body: AskScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every starter question carries its own emoji', (tester) async {
    await pump(tester);

    const expected = {
      '🗓️': 'How was today vs yesterday?',
      '📈': 'What is my MRR trend?',
      '🌍': 'Top countries this month?',
      '💸': 'When do I get paid?',
    };
    for (final entry in expected.entries) {
      expect(find.text(entry.key), findsOneWidget, reason: entry.value);
      expect(find.text(entry.value), findsOneWidget);
      // The emoji is its own decoration, left of the sentence it belongs to.
      final emoji = tester.getRect(find.text(entry.key));
      final label = tester.getRect(find.text(entry.value));
      expect(emoji.center.dx, lessThan(label.left), reason: entry.value);
      expect(emoji.center.dy, moreOrLessEquals(label.center.dy, epsilon: 1.5));
    }
  });

  testWidgets('asking a suggestion sends the sentence without its emoji', (
    tester,
  ) async {
    _Runner? runner;
    await pump(tester, onRunner: (created) => runner = created);

    await tester.tap(find.text('When do I get paid?'));
    await tester.pumpAndSettle();

    expect(runner, isNotNull, reason: 'the turn ran');
    expect(runner!.prompts, ['When do I get paid?']);
    expect(find.text('Answer.'), findsOneWidget);
  });
}
