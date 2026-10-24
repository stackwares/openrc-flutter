import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/models/agent_block.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/services/agent/agent_conversation_runner.dart';
import 'package:openrc/services/agent/agent_llm_client.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/services/agent/agent_tool_executor.dart';

class _FakeSettings extends AgentSettingsNotifier {
  @override
  Future<AgentSettings> build() async => const AgentSettings(
        providerId: AgentProviderId.openrouter,
        model: 'openai/gpt-4o',
        customBaseUrl: '',
        customStyle: AgentApiStyle.openAi,
        useFasterModel: false,
        hasKey: true,
      );

  @override
  Future<String?> readApiKey(AgentProviderId providerId) async => 'sk-or-test';
}

class _FakeExecutor extends AgentToolExecutor {
  _FakeExecutor(super.ref);

  @override
  Map<String, dynamic> snapshot() => {'currency': 'USD', 'fees_applied': false};

  @override
  Future<Map<String, dynamic>> run(
    String name,
    Map<String, dynamic> args,
  ) async {
    if (name == 'get_overview') {
      return {
        'overview': {'mrr': 10},
        'overview_usd': {'mrr': 10},
      };
    }
    return args;
  }
}

class _FakeLlm extends AgentLlmClient {
  var calls = 0;

  @override
  Future<AgentLlmResponse> chat({
    required AgentSettings settings,
    required String apiKey,
    required List<Map<String, dynamic>> messages,
    required CancelToken cancelToken,
  }) async {
    calls += 1;
    if (calls == 1) {
      return const AgentLlmResponse(
        toolCalls: [
          AgentToolCall(id: 't1', name: 'get_overview', argumentsJson: '{}'),
        ],
      );
    }
    if (calls == 2) {
      return const AgentLlmResponse(
        toolCalls: [
          AgentToolCall(
            id: 't2',
            name: 'present',
            argumentsJson: '{"type":"metric_cards","from_tool":"t1"}',
          ),
        ],
      );
    }
    return const AgentLlmResponse(assistantText: 'done');
  }
}

void main() {
  test('tool plus present becomes metric cards', () async {
    final llm = _FakeLlm();
    final container = ProviderContainer(
      overrides: [
        agentSettingsProvider.overrideWith(_FakeSettings.new),
        agentLlmClientProvider.overrideWithValue(llm),
        agentToolExecutorProvider.overrideWith((ref) => _FakeExecutor(ref)),
      ],
    );
    addTearDown(container.dispose);
    final blocks = await container.read(agentConversationRunnerProvider).runTurn(
          userPrompt: 'How is MRR?',
          cancelToken: CancelToken(),
          onStatus: (_) {},
        );
    expect(blocks.any((b) => b.type == AgentPresentationType.metricCards), isTrue);
    expect(llm.calls, 3);
  });

  ProviderContainer containerWith(AgentLlmClient llm, {bool chartFails = false}) {
    final container = ProviderContainer(
      overrides: [
        agentSettingsProvider.overrideWith(_FakeSettings.new),
        agentLlmClientProvider.overrideWithValue(llm),
        agentToolExecutorProvider.overrideWith(
          (ref) => chartFails ? _FailingChartExecutor(ref) : _FakeExecutor(ref),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<List<AgentBlock>> run(
    ProviderContainer container, {
    List<AgentHistoryTurn> history = const [],
  }) =>
      container.read(agentConversationRunnerProvider).runTurn(
            userPrompt: 'Show this for the last 30 days.',
            history: history,
            cancelToken: CancelToken(),
            onStatus: (_) {},
          );

  test('earlier turns go before the question', () async {
    final llm = _ScriptedLlm([const AgentLlmResponse(assistantText: 'Sure.')]);
    await run(
      containerWith(llm),
      history: const [
        AgentHistoryTurn(prompt: 'What is my MRR?', summary: '[showed metric_cards]'),
      ],
    );
    final roles = [for (final m in llm.sent.single) m['role']];
    expect(roles, ['system', 'user', 'assistant', 'user']);
    expect(llm.sent.single[1]['content'], 'What is my MRR?');
    expect(llm.sent.single[2]['content'], '[showed metric_cards]');
  });

  test('present without from_tool shows the data its view reads', () async {
    final llm = _ScriptedLlm([
      const AgentLlmResponse(
        toolCalls: [
          AgentToolCall(id: 'o1', name: 'get_overview', argumentsJson: '{}'),
          AgentToolCall(
            id: 'c1',
            name: 'get_chart',
            argumentsJson: '{"metric":"mrr"}',
          ),
        ],
      ),
      const AgentLlmResponse(
        toolCalls: [
          AgentToolCall(
            id: 'p1',
            name: 'present',
            argumentsJson: '{"type":"metric_cards"}',
          ),
        ],
      ),
      const AgentLlmResponse(assistantText: r'MRR is $10.'),
    ]);
    final blocks = await run(containerWith(llm));
    expect(blocks.first.type, AgentPresentationType.markdown);
    expect(blocks.first.payload['markdown'], r'MRR is $10.');
    final cards = blocks.firstWhere(
      (b) => b.type == AgentPresentationType.metricCards,
    );
    expect(cards.payload['overview'], isNotNull);
  });

  test('a failing tool is reported to the model instead of ending the turn', () async {
    final llm = _ScriptedLlm([
      const AgentLlmResponse(
        toolCalls: [
          AgentToolCall(id: 'c1', name: 'get_chart', argumentsJson: '{}'),
        ],
      ),
      const AgentLlmResponse(assistantText: "I couldn't load that chart."),
    ]);
    final blocks = await run(containerWith(llm, chartFails: true));
    final toolMessage = llm.sent.last.lastWhere((m) => m['role'] == 'tool');
    expect(toolMessage['content'], contains('tool_failed'));
    expect(blocks.single.payload['markdown'], "I couldn't load that chart.");
  });
}

class _FailingChartExecutor extends _FakeExecutor {
  _FailingChartExecutor(super.ref);

  @override
  Future<Map<String, dynamic>> run(
    String name,
    Map<String, dynamic> args,
  ) async {
    if (name == 'get_chart') throw StateError('RevenueCat is down');
    return super.run(name, args);
  }
}

/// Replies in order and keeps what each request sent.
class _ScriptedLlm extends AgentLlmClient {
  _ScriptedLlm(this.replies);

  final List<AgentLlmResponse> replies;
  final sent = <List<Map<String, dynamic>>>[];

  @override
  Future<AgentLlmResponse> chat({
    required AgentSettings settings,
    required String apiKey,
    required List<Map<String, dynamic>> messages,
    required CancelToken cancelToken,
  }) async {
    sent.add([...messages]);
    return replies.removeAt(0);
  }
}
