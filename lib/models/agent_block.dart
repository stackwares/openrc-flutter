/// Presentation chosen by the model (or repair compositor).
enum AgentPresentationType {
  metricCards('metric_cards'),
  lineChart('line_chart'),
  barChart('bar_chart'),
  dataTable('data_table'),
  transactionList('transaction_list'),
  markdown('markdown');

  const AgentPresentationType(this.wireName);

  /// Name the model uses in the `present` tool.
  final String wireName;

  static AgentPresentationType fromWireName(String? name) =>
      AgentPresentationType.values.firstWhere(
        (t) => t.wireName == name,
        orElse: () => AgentPresentationType.markdown,
      );
}

class AgentBlock {
  const AgentBlock({
    required this.type,
    this.title,
    required this.payload,
  });

  final AgentPresentationType type;
  final String? title;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (title != null) 'title': title,
        'payload': payload,
      };

  factory AgentBlock.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'markdown';
    final type = AgentPresentationType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => AgentPresentationType.markdown,
    );
    return AgentBlock(
      type: type,
      title: json['title'] as String?,
      payload: Map<String, dynamic>.from(
        json['payload'] as Map? ?? const {},
      ),
    );
  }
}

class AgentTurn {
  AgentTurn({
    String? id,
    required this.userPrompt,
    this.statusLine,
    this.blocks = const [],
    this.errorKey,
  }) : id = id ?? _nextId();

  /// Stable across [copyWith], so a late reply never lands on another turn.
  final String id;
  final String userPrompt;
  final String? statusLine;
  final List<AgentBlock> blocks;
  final String? errorKey;

  /// Waiting on the model or a tool.
  bool get isRunning => statusLine != null;

  /// Finished with something to show.
  bool get isAnswered => !isRunning && errorKey == null && blocks.isNotEmpty;

  static var _seq = 0;
  static String _nextId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  AgentTurn copyWith({
    String? userPrompt,
    String? statusLine,
    List<AgentBlock>? blocks,
    String? errorKey,
    bool clearError = false,
    bool clearStatus = false,
  }) =>
      AgentTurn(
        id: id,
        userPrompt: userPrompt ?? this.userPrompt,
        statusLine: clearStatus ? null : (statusLine ?? this.statusLine),
        blocks: blocks ?? this.blocks,
        errorKey: clearError ? null : (errorKey ?? this.errorKey),
      );
}
