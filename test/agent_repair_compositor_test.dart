import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/models/agent_block.dart';
import 'package:openrc/services/agent/agent_repair_compositor.dart';

void main() {
  const repair = AgentRepairCompositor();

  test('get_chart without present still builds a line chart', () {
    final blocks = repair.blocksFromToolResults(
      resultsByToolName: {
        'get_chart': {
          'metric': 'mrr',
          'chart': {
            'values': [
              {'value': 1.0},
              {'value': 2.0},
            ],
          },
        },
      },
      assistantText: 'Here is your MRR.',
    );
    expect(blocks.any((b) => b.type == AgentPresentationType.lineChart), isTrue);
    expect(blocks.any((b) => b.type == AgentPresentationType.markdown), isTrue);
  });
}
