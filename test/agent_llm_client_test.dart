import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/services/agent/agent_llm_client.dart';

void main() {
  test('OpenAI tool loop becomes Anthropic tool_use / tool_result', () {
    final out = AgentLlmClient.anthropicMessagesFromOpenAi([
      {'role': 'system', 'content': 'sys'},
      {'role': 'user', 'content': 'How was today?'},
      {
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          {
            'id': 'c1',
            'function': {'name': 'get_overview', 'arguments': '{}'},
          },
        ],
      },
      {
        'role': 'tool',
        'tool_call_id': 'c1',
        'content': '{"mrr":1}',
      },
    ]);
    expect(out, hasLength(3));
    expect(out[0]['role'], 'user');
    expect(out[1]['role'], 'assistant');
    final uses = out[1]['content'] as List;
    expect(uses.single['type'], 'tool_use');
    expect(uses.single['name'], 'get_overview');
    expect(out[2]['role'], 'user');
    final results = out[2]['content'] as List;
    expect(results.single['type'], 'tool_result');
    expect(results.single['tool_use_id'], 'c1');
  });
}
