import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/features/ask/ask_thread_store.dart';
import 'package:openrc/models/agent_block.dart';
import 'package:openrc/models/agent_block_payload.dart';
import 'package:openrc/services/agent/agent_conversation_runner.dart';
import 'package:openrc/services/agent/agent_llm_client.dart';

final askNotifierProvider =
    NotifierProvider<AskNotifier, List<AgentTurn>>(AskNotifier.new);

/// Earlier answered turns sent with each question, so follow-ups like
/// "show this for the last 30 days" know what "this" is.
const kAskHistoryTurns = 4;

class AskNotifier extends Notifier<List<AgentTurn>> {
  CancelToken? _cancelToken;
  String? _runningTurnId;
  final _store = const AskThreadStore();

  /// Bumped on clear, so a slow load can't bring a cleared thread back.
  var _generation = 0;

  @override
  List<AgentTurn> build() {
    ref.onDispose(() => _cancelToken?.cancel('disposed'));
    _loadPersisted(_generation);
    return const [];
  }

  Future<void> _loadPersisted(int generation) async {
    final turns = await _store.load();
    if (!ref.mounted || generation != _generation || turns.isEmpty) return;
    state = [...turns, ...state];
  }

  bool get isRunning => _cancelToken != null;

  /// Stops the running turn now; its late reply, if any, is dropped.
  void cancel() {
    final token = _cancelToken;
    if (token == null) return;
    token.cancel('user');
    _cancelToken = null;
    final id = _runningTurnId;
    _runningTurnId = null;
    if (id != null) {
      _update(
        id,
        (t) => t.copyWith(errorKey: kAgentStoppedKey, clearStatus: true),
      );
      _store.save(state);
    }
  }

  Future<void> clearThread() async {
    cancel();
    _generation++;
    state = const [];
    await _store.clear();
  }

  Future<void> retryLast() async {
    if (state.isEmpty || isRunning) return;
    final prompt = state.last.userPrompt;
    state = state.sublist(0, state.length - 1);
    await submit(prompt);
  }

  /// Adds a table of the last turn's chart under it.
  void presentLastChartAsTable() {
    if (state.isEmpty) return;
    final last = state.last;
    final chart = last.blocks
        .where(
          (b) =>
              b.type == AgentPresentationType.lineChart &&
              AgentBlockPayload(b.payload).chartPoints().isNotEmpty,
        )
        .firstOrNull;
    if (chart == null) return;
    if (last.blocks.any(
      (b) =>
          b.type == AgentPresentationType.dataTable &&
          identical(b.payload, chart.payload),
    )) {
      return;
    }
    _update(
      last.id,
      (t) => t.copyWith(
        blocks: [
          ...t.blocks,
          AgentBlock(
            type: AgentPresentationType.dataTable,
            title: chart.title,
            payload: chart.payload,
          ),
        ],
      ),
    );
    _store.save(state);
  }

  Future<void> submit(String prompt) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty || isRunning) return;
    final history = _historyFor(state);
    final token = CancelToken();
    _cancelToken = token;
    final turn = AgentTurn(
      userPrompt: trimmed,
      statusLine: 'agent.status.thinking',
    );
    _runningTurnId = turn.id;
    state = [...state, turn];

    // False once the turn was stopped, the thread cleared or the provider
    // disposed: whatever comes back then belongs to nobody.
    bool active() => ref.mounted && identical(_cancelToken, token);

    try {
      final runner = ref.read(agentConversationRunnerProvider);
      final blocks = await runner.runTurn(
        userPrompt: trimmed,
        history: history,
        cancelToken: token,
        onStatus: (key) {
          if (!active()) return;
          _update(turn.id, (t) => t.copyWith(statusLine: key));
        },
      );
      if (!active()) return;
      _update(
        turn.id,
        (t) => t.copyWith(blocks: blocks, clearStatus: true, clearError: true),
      );
    } on AgentLlmException catch (e) {
      if (!active()) return;
      _update(
        turn.id,
        (t) => t.copyWith(errorKey: e.messageKey, clearStatus: true),
      );
    } catch (_) {
      if (!active()) return;
      _update(
        turn.id,
        (t) => t.copyWith(errorKey: 'agent.errors.generic', clearStatus: true),
      );
    } finally {
      if (identical(_cancelToken, token)) {
        _cancelToken = null;
        _runningTurnId = null;
      }
    }
    if (ref.mounted) await _store.save(state);
  }

  void _update(String id, AgentTurn Function(AgentTurn turn) change) {
    if (!ref.mounted) return;
    final index = state.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final copy = [...state];
    copy[index] = change(copy[index]);
    state = copy;
  }

  static List<AgentHistoryTurn> _historyFor(List<AgentTurn> turns) {
    final answered = [
      for (final t in turns)
        if (t.isAnswered) t,
    ];
    final recent = answered.length > kAskHistoryTurns
        ? answered.sublist(answered.length - kAskHistoryTurns)
        : answered;
    return [
      for (final t in recent)
        AgentHistoryTurn(
          prompt: t.userPrompt,
          summary: agentBlocksSummary(t.blocks),
        ),
    ];
  }
}
