import 'dart:convert';

import 'package:openrc/models/agent_block.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefKey = 'agent_last_thread_v1';

/// Error shown on a turn that was still running when it was saved or stopped.
const kAgentStoppedKey = 'agent.errors.stopped';

class AskThreadStore {
  const AskThreadStore();

  Future<List<AgentTurn>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in list)
          if (item is Map<String, dynamic>) _turnFromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<AgentTurn> turns) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefKey,
        jsonEncode(turns.map(_turnToJson).toList(growable: false)),
      );
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {}
  }

  // A run can't outlive the app, so a turn saved mid-run comes back stopped
  // instead of "Thinking…" forever.
  static Map<String, dynamic> _turnToJson(AgentTurn t) => {
        'id': t.id,
        'userPrompt': t.userPrompt,
        'errorKey': t.isRunning ? kAgentStoppedKey : t.errorKey,
        'blocks': t.blocks.map((b) => b.toJson()).toList(),
      };

  static AgentTurn _turnFromJson(Map<String, dynamic> json) => AgentTurn(
        id: json['id'] as String?,
        userPrompt: json['userPrompt'] as String? ?? '',
        errorKey: json['statusLine'] != null
            ? kAgentStoppedKey
            : json['errorKey'] as String?,
        blocks: [
          for (final b in json['blocks'] as List? ?? const [])
            if (b is Map<String, dynamic>) AgentBlock.fromJson(b),
        ],
      );
}
