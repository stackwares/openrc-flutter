import 'package:dio/dio.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/ask/ask_screen.dart';
import 'package:openrc/features/ask/widgets/ask_composer.dart';
import 'package:openrc/models/agent_block.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/services/agent/agent_conversation_runner.dart';
import 'package:openrc/services/agent/agent_llm_client.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/services/onboarding_prefs_store.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:openrc/widgets/app_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends AgentSettingsNotifier {
  _Settings({required this.hasKey});

  final bool hasKey;

  @override
  Future<AgentSettings> build() async => AgentSettings(
    providerId: AgentProviderId.openrouter,
    model: '',
    customBaseUrl: '',
    customStyle: AgentApiStyle.openAi,
    useFasterModel: false,
    hasKey: hasKey,
  );

  @override
  Future<Set<AgentProviderId>> providersWithKeys() async => {};
}

class _Runner extends AgentConversationRunner {
  _Runner(super.ref, this.reply);

  final Future<List<AgentBlock>> Function(String prompt) reply;
  final prompts = <String>[];

  @override
  Future<List<AgentBlock>> runTurn({
    required String userPrompt,
    required void Function(String status) onStatus,
    required CancelToken cancelToken,
    List<AgentHistoryTurn> history = const [],
  }) {
    prompts.add(userPrompt);
    return reply(userPrompt);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Runner?> pump(
    WidgetTester tester, {
    required bool hasKey,
    bool aiConsentGranted = true,
    Future<List<AgentBlock>> Function(String prompt)? reply,
  }) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _Runner? runner;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingPrefsProvider.overrideWith(
            (ref) => OnboardingPrefsNotifier.loaded(
              OnboardingPrefs(aiConsentGranted: aiConsentGranted),
            ),
          ),
          agentSettingsProvider.overrideWith(() => _Settings(hasKey: hasKey)),
          agentConversationRunnerProvider.overrideWith(
            (ref) => runner = _Runner(
              ref,
              reply ??
                  (_) async => const [
                    AgentBlock(
                      type: AgentPresentationType.markdown,
                      payload: {'markdown': r'MRR is **$10K**, up 12%.'},
                    ),
                  ],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(FlexScheme.indigoM3),
          home: const Scaffold(body: AskScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return runner;
  }

  testWidgets(
    'without a key, Ask shows centered setup with app icon and hides composer',
    (tester) async {
      await pump(tester, hasKey: false);
      expect(find.byType(AppLogo), findsOneWidget);
      expect(find.text('Connect a model'), findsOneWidget);
      expect(
        find.text(
          'Add a provider API key to ask about revenue, charts, and payouts.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.text('Connect a model')).textAlign,
        TextAlign.center,
      );
      expect(
        tester
            .widget<Text>(
              find.text(
                'Add a provider API key to ask about revenue, charts, and payouts.',
              ),
            )
            .textAlign,
        TextAlign.center,
      );
      expect(find.text('Add API key'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.byType(AskComposer), findsNothing);
      expect(find.text('Add a key to ask'), findsNothing);
      expect(find.text('What is my MRR trend?'), findsNothing);
      expect(find.text('Save and start'), findsNothing);

      await tester.tap(find.text('Add API key'));
      await tester.pumpAndSettle();

      expect(find.text('Connect your LLM'), findsOneWidget);
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save and start'),
      );
      expect(save.onPressed, isNull, reason: 'no key and no consent yet');
    },
  );

  testWidgets('a suggestion is asked and its answer drawn', (tester) async {
    await pump(tester, hasKey: true);
    expect(find.text('Nothing asked yet'), findsOneWidget);
    expect(
      find.text('Ask about today, MRR, countries, or when you get paid.'),
      findsOneWidget,
    );

    await tester.tap(find.text('What is my MRR trend?'));
    await tester.pumpAndSettle();

    expect(find.text('What is my MRR trend?'), findsOneWidget);
    expect(
      find.text(r'MRR is $10K, up 12%.', findRichText: true),
      findsOneWidget,
    );
    expect(find.byTooltip('Copy'), findsOneWidget);
  });

  testWidgets('a rejected key offers to edit it', (tester) async {
    await pump(
      tester,
      hasKey: true,
      reply: (_) async => throw AgentLlmException('agent.errors.badKey'),
    );
    await tester.tap(find.text('When do I get paid?'));
    await tester.pumpAndSettle();

    expect(
      find.text('That API key was rejected. Check the key and try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Edit key'));
    await tester.pumpAndSettle();
    expect(find.text('Save and start'), findsOneWidget);
    expect(find.text('Remove key'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('the composer keeps its text and hint vertically centered', (
    tester,
  ) async {
    await pump(tester, hasKey: true);

    final field = tester.getRect(find.byType(TextField));
    final editable = tester.getRect(find.byType(EditableText));
    expect(
      editable.center.dy,
      moreOrLessEquals(field.center.dy, epsilon: 0.5),
      reason: 'the empty field centers its hint',
    );

    await tester.enterText(find.byType(TextField), 'What is my MRR?');
    await tester.pumpAndSettle();

    final typedField = tester.getRect(find.byType(TextField));
    final typed = tester.getRect(find.byType(EditableText));
    expect(
      typed.center.dy,
      moreOrLessEquals(typedField.center.dy, epsilon: 0.5),
      reason: 'a one-line question centers in its field',
    );
  });
}
