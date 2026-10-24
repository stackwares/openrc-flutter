import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:openrc/models/agent_block.dart';
import 'package:openrc/models/agent_block_payload.dart';
import 'package:openrc/services/agent/agent_llm_client.dart';
import 'package:openrc/services/agent/agent_repair_compositor.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/services/agent/agent_tool_executor.dart';

final agentLlmClientProvider = Provider<AgentLlmClient>((ref) => AgentLlmClient());

/// Most tool rounds one question may take before the app shows what it has.
const kAgentMaxSteps = 8;

String agentSystemPrompt({
  required String locale,
  required Map<String, dynamic> snapshot,
}) =>
    '''
You are OpenRC's revenue analyst inside a mobile app. Use tools to fetch live RevenueCat data before answering numeric questions.
If the snapshot has focus_store_transaction_id or the question is about one sale, call get_transaction.
After fetching data, call the present tool to choose metric_cards, line_chart, bar_chart, data_table, transaction_list, or markdown, and pass from_tool with the data tool's call id.
Then answer in one or two short plain sentences with the key number and how it changed. No headings, no tables, no filler.
Never invent numbers. If the data can't answer the question, say so briefly.
Reply in this locale: $locale.
Amounts in tool results are already in the user's display currency and fee setting. Do not convert them again.
Dates are yyyy-MM-dd. `today` below is the user's current day; resolve "today", "yesterday" and "this month" from it.
Earlier questions in this thread come before the current one; use them for follow-ups like "this" or "the same for last month".

Already-loaded app context (do not treat as complete; fetch when unsure):
${jsonEncode(snapshot)}
''';

/// An earlier question and a short note of what it showed.
class AgentHistoryTurn {
  const AgentHistoryTurn({required this.prompt, required this.summary});

  final String prompt;
  final String summary;
}

/// What a finished turn showed, compact enough to send with the next one.
String agentBlocksSummary(List<AgentBlock> blocks) {
  final parts = <String>[];
  for (final block in blocks) {
    final payload = AgentBlockPayload(block.payload);
    if (block.type == AgentPresentationType.markdown) {
      final text = payload.markdown?.trim() ?? '';
      if (text.isNotEmpty) {
        parts.add(text.length > 600 ? '${text.substring(0, 600)}…' : text);
      }
      continue;
    }
    final details = [
      block.type.wireName,
      if (block.title != null && block.title!.isNotEmpty) '"${block.title}"',
      if (payload.metricName != null) 'metric ${payload.metricName}',
      if (block.payload['range_start'] != null)
        '${block.payload['range_start']} to ${block.payload['range_end']}',
      if (block.payload['last_display'] != null)
        'last ${block.payload['last_display']}',
      if (block.payload['last_value'] != null)
        'last ${block.payload['last_value']}',
      if (payload.transactions.isNotEmpty)
        '${payload.transactions.length} transactions',
    ];
    parts.add('[showed ${details.join(', ')}]');
  }
  return parts.isEmpty ? '[showed nothing]' : parts.join('\n');
}

class AgentConversationRunner {
  AgentConversationRunner(this._ref);

  final Ref _ref;
  final _repair = const AgentRepairCompositor();

  /// The data tool each view reads when the model names no `from_tool`.
  static const _toolForView = {
    AgentPresentationType.metricCards: 'get_overview',
    AgentPresentationType.lineChart: 'get_chart',
    AgentPresentationType.barChart: 'get_payout_context',
    AgentPresentationType.transactionList: 'get_transactions',
  };

  Future<List<AgentBlock>> runTurn({
    required String userPrompt,
    required void Function(String status) onStatus,
    required CancelToken cancelToken,
    List<AgentHistoryTurn> history = const [],
  }) async {
    final settings = await _ref.read(agentSettingsProvider.future);
    final apiKey = await _ref
        .read(agentSettingsProvider.notifier)
        .readApiKey(settings.providerId);
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw AgentLlmException('agent.errors.noKey');
    }

    final client = _ref.read(agentLlmClientProvider);
    final executor = _ref.read(agentToolExecutorProvider);
    final locale = Intl.getCurrentLocale();
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': agentSystemPrompt(
          locale: locale,
          snapshot: executor.snapshot(),
        ),
      },
      for (final turn in history) ...[
        {'role': 'user', 'content': turn.prompt},
        {'role': 'assistant', 'content': turn.summary},
      ],
      {'role': 'user', 'content': userPrompt},
    ];

    final resultsByToolName = <String, Map<String, dynamic>>{};
    final resultsById = <String, Map<String, dynamic>>{};
    final presentBlocks = <AgentBlock>[];
    String? finalText;
    String? presentText;

    for (var step = 0; step < kAgentMaxSteps; step++) {
      onStatus(step == 0 ? 'agent.status.thinking' : 'agent.status.tools');
      final response = await client.chat(
        settings: settings,
        apiKey: apiKey.trim(),
        messages: messages,
        cancelToken: cancelToken,
      );
      if (response.toolCalls.isEmpty) {
        finalText = response.assistantText;
        break;
      }
      // Text next to a `present` call is often the answer itself; text next
      // to data calls is usually "let me check".
      if (response.toolCalls.any((c) => c.name == 'present')) {
        presentText = response.assistantText ?? presentText;
      }

      messages.add({
        'role': 'assistant',
        'content': response.assistantText,
        'tool_calls': [
          for (final c in response.toolCalls)
            {
              'id': c.id,
              'type': 'function',
              'function': {'name': c.name, 'arguments': c.argumentsJson},
            },
        ],
      });

      for (final call in response.toolCalls) {
        Map<String, dynamic> args;
        try {
          final decoded = jsonDecode(call.argumentsJson);
          args = decoded is Map<String, dynamic> ? decoded : {};
        } catch (_) {
          args = <String, dynamic>{};
        }
        onStatus(
          kAgentToolNames.contains(call.name)
              ? 'agent.status.tool.${call.name}'
              : 'agent.status.tools',
        );
        Map<String, dynamic> result;
        try {
          result = await executor.run(call.name, args);
        } catch (_) {
          // The model can retry or explain; one failed fetch shouldn't end
          // the whole answer.
          result = {'error': 'tool_failed', 'tool': call.name};
        }
        if (cancelToken.isCancelled) {
          throw AgentLlmException('agent.errors.stopped');
        }
        if (call.name == 'present') {
          final block = _repair.blockFromPresent(
            args,
            _dataFor(args, resultsById, resultsByToolName),
          );
          if (block != null) presentBlocks.add(block);
        } else if (result['error'] == null) {
          resultsByToolName[call.name] = result;
          if (call.id.isNotEmpty) resultsById[call.id] = result;
        }
        messages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': jsonEncode(result),
        });
      }
    }

    final text = (finalText ?? presentText)?.trim();
    if (presentBlocks.isNotEmpty) {
      final repeatsText = presentBlocks.any(
        (b) =>
            b.type == AgentPresentationType.markdown &&
            b.payload['markdown'] == text,
      );
      return [
        if (text != null && text.isNotEmpty && !repeatsText)
          AgentBlock(
            type: AgentPresentationType.markdown,
            payload: {'markdown': text},
          ),
        ...presentBlocks,
      ];
    }
    return _repair.blocksFromToolResults(
      resultsByToolName: resultsByToolName,
      assistantText: text,
    );
  }

  /// The tool result a `present` call shows: the one it names, else the
  /// latest result of the tool that view reads, else the latest of any.
  static Map<String, dynamic>? _dataFor(
    Map<String, dynamic> args,
    Map<String, Map<String, dynamic>> resultsById,
    Map<String, Map<String, dynamic>> resultsByToolName,
  ) {
    final fromId = args['from_tool'];
    if (fromId is String && resultsById[fromId] != null) {
      return resultsById[fromId];
    }
    final view = AgentPresentationType.fromWireName(args['type'] as String?);
    return resultsByToolName[_toolForView[view]] ??
        resultsById.values.lastOrNull ??
        resultsByToolName.values.lastOrNull;
  }
}

final agentConversationRunnerProvider = Provider<AgentConversationRunner>(
  (ref) => AgentConversationRunner(ref),
);
