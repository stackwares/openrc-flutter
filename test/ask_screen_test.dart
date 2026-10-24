import 'package:dio/dio.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/ask/ask_screen.dart';
import 'package:openrc/models/agent_block.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/services/agent/agent_conversation_runner.dart';
import 'package:openrc/services/agent/agent_llm_client.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/theme/app_theme.dart';
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
    Future<List<AgentBlock>> Function(String prompt)? reply,
  }) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _Runner? runner;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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

  testWidgets('without a key, Ask asks for a provider and key first', (
    tester,
  ) async {
    await pump(tester, hasKey: false);
    expect(find.text('Connect your LLM'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save and start'),
    );
    expect(save.onPressed, isNull, reason: 'no key and no consent yet');
  });

  testWidgets('a suggestion is asked and its answer drawn', (tester) async {
    await pump(tester, hasKey: true);
    expect(find.text('Ask about your revenue'), findsOneWidget);

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
    expect(find.text('Connect your LLM'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}
