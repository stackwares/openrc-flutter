import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/ask/ask_notifier.dart';
import 'package:openrc/features/ask/ask_thread_store.dart';
import 'package:openrc/models/agent_block.dart';
import 'package:openrc/services/agent/agent_conversation_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _Call = ({
  String prompt,
  List<AgentHistoryTurn> history,
  CancelToken token,
  Completer<List<AgentBlock>> reply,
});

/// Answers only when the test completes the call's [_Call.reply].
class _FakeRunner extends AgentConversationRunner {
  _FakeRunner(super.ref);

  final calls = <_Call>[];

  @override
  Future<List<AgentBlock>> runTurn({
    required String userPrompt,
    required void Function(String status) onStatus,
    required CancelToken cancelToken,
    List<AgentHistoryTurn> history = const [],
  }) {
    final reply = Completer<List<AgentBlock>>();
    calls.add((
      prompt: userPrompt,
      history: history,
      token: cancelToken,
      reply: reply,
    ));
    return reply.future;
  }
}

List<AgentBlock> _answer(String text) => [
      AgentBlock(
        type: AgentPresentationType.markdown,
        payload: {'markdown': text},
      ),
    ];

void main() {
  late ProviderContainer container;
  late _FakeRunner runner;

  AskNotifier notifier() => container.read(askNotifierProvider.notifier);
  List<AgentTurn> turns() => container.read(askNotifierProvider);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [
        agentConversationRunnerProvider.overrideWith(
          (ref) => runner = _FakeRunner(ref),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(askNotifierProvider);
    container.read(agentConversationRunnerProvider);
    await pumpEventQueue();
  });

  test('a follow-up carries the earlier answers', () async {
    final first = notifier().submit('What is my MRR?');
    runner.calls.single.reply.complete(_answer(r'MRR is $10K.'));
    await first;

    final second = notifier().submit('Show this for the last 30 days.');
    final call = runner.calls.last;
    expect(call.history.single.prompt, 'What is my MRR?');
    expect(call.history.single.summary, contains(r'MRR is $10K.'));
    call.reply.complete(_answer('Done.'));
    await second;

    expect(turns().map((t) => t.isAnswered), [true, true]);
  });

  test('stop marks the turn at once and drops the late reply', () async {
    final pending = notifier().submit('How was today?');
    expect(turns().single.isRunning, isTrue);

    notifier().cancel();
    expect(turns().single.errorKey, kAgentStoppedKey);
    expect(turns().single.isRunning, isFalse);
    expect(runner.calls.single.token.isCancelled, isTrue);

    runner.calls.single.reply.complete(_answer('Too late.'));
    await pending;
    expect(turns().single.errorKey, kAgentStoppedKey);
    expect(turns().single.blocks, isEmpty);
  });

  test("an old reply can't land on the next thread's question", () async {
    final old = notifier().submit('First question');
    await notifier().clearThread();
    final next = notifier().submit('Second question');

    runner.calls.first.reply.complete(_answer('Old answer'));
    await old;
    expect(turns().single.userPrompt, 'Second question');
    expect(turns().single.isRunning, isTrue);

    runner.calls.last.reply.complete(_answer('New answer'));
    await next;
    expect(turns().single.isAnswered, isTrue);
  });

  test('a second question waits for the first', () async {
    final first = notifier().submit('One');
    await notifier().submit('Two');
    expect(runner.calls, hasLength(1));
    expect(turns(), hasLength(1));
    runner.calls.single.reply.complete(_answer('Answer'));
    await first;
  });

  test('a turn saved mid-run comes back stopped', () async {
    const store = AskThreadStore();
    await store.save([
      AgentTurn(userPrompt: 'Q', statusLine: 'agent.status.thinking'),
    ]);
    final loaded = await store.load();
    expect(loaded.single.isRunning, isFalse);
    expect(loaded.single.errorKey, kAgentStoppedKey);
  });
}
