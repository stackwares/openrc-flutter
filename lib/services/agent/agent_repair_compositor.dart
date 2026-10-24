import 'package:openrc/models/agent_block.dart';

/// Builds [AgentBlock]s when the model skips the `present` tool.
class AgentRepairCompositor {
  const AgentRepairCompositor();

  /// The model's answer first, then a view per tool it called.
  List<AgentBlock> blocksFromToolResults({
    required Map<String, Map<String, dynamic>> resultsByToolName,
    String? assistantText,
  }) {
    final blocks = <AgentBlock>[];
    final text = assistantText?.trim();
    if (text != null && text.isNotEmpty) {
      blocks.add(
        AgentBlock(
          type: AgentPresentationType.markdown,
          payload: {'markdown': text},
        ),
      );
    }
    const views = {
      'get_overview': AgentPresentationType.metricCards,
      'get_chart': AgentPresentationType.lineChart,
      'get_transactions': AgentPresentationType.transactionList,
      'get_transaction': AgentPresentationType.transactionList,
      'get_payout_context': AgentPresentationType.barChart,
    };
    for (final MapEntry(key: tool, value: type) in views.entries) {
      final result = resultsByToolName[tool];
      if (result == null) continue;
      blocks.add(
        AgentBlock(type: type, payload: Map<String, dynamic>.from(result)),
      );
    }
    if (blocks.isEmpty) {
      blocks.add(
        const AgentBlock(
          type: AgentPresentationType.markdown,
          payload: {'markdown': ''},
        ),
      );
    }
    return blocks;
  }

  AgentBlock? blockFromPresent(
    Map<String, dynamic> args,
    Map<String, dynamic>? fromResult,
  ) {
    final typeRaw = args['type'];
    if (typeRaw is! String) return null;
    final type = AgentPresentationType.fromWireName(typeRaw);
    final title = args['title'] is String ? args['title'] as String : null;
    if (type == AgentPresentationType.markdown) {
      final markdown = args['markdown'] is String ? args['markdown'] as String : '';
      if (markdown.trim().isEmpty) return null;
      return AgentBlock(
        type: type,
        title: title,
        payload: {'markdown': markdown},
      );
    }
    return AgentBlock(
      type: type,
      title: title,
      payload: fromResult ?? Map<String, dynamic>.from(args),
    );
  }
}
