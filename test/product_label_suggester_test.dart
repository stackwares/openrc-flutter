import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/services/agent/agent_conversation_runner.dart';
import 'package:openrc/services/agent/agent_llm_client.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/services/agent/product_label_suggester.dart';

class _FakeSettings extends AgentSettingsNotifier {
  _FakeSettings({this.key = 'sk-test'});

  final String? key;

  @override
  Future<AgentSettings> build() async => AgentSettings(
    providerId: AgentProviderId.openrouter,
    model: 'openai/gpt-4o',
    customBaseUrl: '',
    customStyle: AgentApiStyle.openAi,
    useFasterModel: false,
    hasKey: key != null,
  );

  @override
  Future<String?> readApiKey(AgentProviderId providerId) async => key;
}

class _FakeClient extends AgentLlmClient {
  _FakeClient(this.answer);

  /// The answer for a chunk of ids; the ids sent are recorded too.
  final String Function(List<String> ids) answer;
  final calls = <List<String>>[];
  final payloads = <Map<String, dynamic>>[];

  @override
  Future<AgentLlmResponse> complete({
    required AgentSettings settings,
    required String apiKey,
    required List<Map<String, dynamic>> messages,
    required CancelToken cancelToken,
  }) async {
    final payload =
        jsonDecode(messages.last['content'] as String) as Map<String, dynamic>;
    payloads.add(payload);
    final ids = (payload['products'] as List).cast<String>();
    calls.add(ids);
    return AgentLlmResponse(assistantText: answer(ids));
  }
}

({ProviderContainer container, _FakeClient client}) _harness({
  String Function(List<String> ids)? answer,
  String? key = 'sk-test',
}) {
  final client = _FakeClient(
    answer ??
        (ids) => jsonEncode({
          'labels': [
            for (final id in ids) {'id': id, 'name': 'Pro', 'plan': 'Pro'},
          ],
        }),
  );
  final container = ProviderContainer(
    overrides: [
      agentSettingsProvider.overrideWith(() => _FakeSettings(key: key)),
      agentLlmClientProvider.overrideWithValue(client),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, client: client);
}

void main() {
  test('model names win and carry a plan', () async {
    final h = _harness(
      answer: (_) => jsonEncode({
        'labels': [
          {'id': 'com.acme.pro_monthly', 'name': 'Pro', 'plan': 'Pro'},
        ],
      }),
    );
    final out = await h.container
        .read(productLabelSuggesterProvider)
        .suggest(
          productIds: ['com.acme.pro_monthly'],
          cancelToken: CancelToken(),
        );
    expect(out.single.name, 'Pro');
    expect(out.single.plan, 'Pro');
    expect(out.single.fromAi, isTrue);
  });

  test('only product ids leave the device', () async {
    final h = _harness();
    await h.container
        .read(productLabelSuggesterProvider)
        .suggest(productIds: ['pro_monthly'], cancelToken: CancelToken());
    expect(h.client.payloads.single.keys, ['products']);
    expect(h.client.payloads.single['products'], ['pro_monthly']);
  });

  test('ids are chunked and progress is reported', () async {
    final h = _harness();
    final ids = [for (var i = 0; i < 45; i++) 'product_$i'];
    final progress = <(int, int)>[];
    final out = await h.container
        .read(productLabelSuggesterProvider)
        .suggest(
          productIds: ids,
          cancelToken: CancelToken(),
          onProgress: (done, total) => progress.add((done, total)),
        );

    expect(h.client.calls.map((c) => c.length), [40, 5]);
    expect(out, hasLength(45));
    expect(progress.last, (45, 45));
  });

  test('duplicate ids are asked once', () async {
    final h = _harness();
    await h.container
        .read(productLabelSuggesterProvider)
        .suggest(productIds: ['pro', 'pro', ' '], cancelToken: CancelToken());
    expect(h.client.calls.single, ['pro']);
  });

  test('ids the model invents are ignored', () async {
    final h = _harness(
      answer: (_) => jsonEncode({
        'labels': [
          {'id': 'made_up', 'name': 'Ghost'},
        ],
      }),
    );
    final out = await h.container
        .read(productLabelSuggesterProvider)
        .suggest(
          productIds: ['com.acme.pro_monthly'],
          cancelToken: CancelToken(),
        );
    expect(out.single.productId, 'com.acme.pro_monthly');
    expect(out.single.name, 'Monthly');
    expect(out.single.fromAi, isFalse);
  });

  test('an unusable answer falls back to the parser', () async {
    final h = _harness(answer: (_) => 'Sure! Here are some names...');
    final out = await h.container
        .read(productLabelSuggesterProvider)
        .suggest(
          productIds: ['com.acme.pro_monthly'],
          cancelToken: CancelToken(),
        );
    expect(out.single.name, 'Monthly');
    expect(out.single.fromAi, isFalse);
  });

  test('without a key it asks for one instead of calling the model', () async {
    final h = _harness(key: null);
    await expectLater(
      h.container
          .read(productLabelSuggesterProvider)
          .suggest(productIds: ['pro_monthly'], cancelToken: CancelToken()),
      throwsA(
        isA<AgentLlmException>().having(
          (e) => e.messageKey,
          'messageKey',
          'agent.errors.noKey',
        ),
      ),
    );
    expect(h.client.calls, isEmpty);
  });

  test('a cancelled run stops before calling the model', () async {
    final h = _harness();
    final cancel = CancelToken()..cancel();
    await expectLater(
      h.container
          .read(productLabelSuggesterProvider)
          .suggest(productIds: ['pro_monthly'], cancelToken: cancel),
      throwsA(
        isA<AgentLlmException>().having(
          (e) => e.messageKey,
          'messageKey',
          'agent.errors.stopped',
        ),
      ),
    );
    expect(h.client.calls, isEmpty);
  });

  test('local names are the period the id names', () {
    final out = ProductLabelSuggester.local([
      'com.acme.pro_yearly',
      'com.acme.pro_monthly',
      'com.acme.pro_1week',
      'com.acme.lifetime',
      'com.acme.pro',
    ]);
    expect(out.map((s) => s.name), [
      'Yearly',
      'Monthly',
      '1 Week',
      'Lifetime',
      null,
    ]);
    expect(out.every((s) => !s.fromAi), isTrue);
    // The period is also the plan family, so variants merge in the breakdown.
    expect(out.first.plan, 'Yearly');
  });
}
