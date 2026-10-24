import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/ask/widgets/agent_markdown.dart';

void main() {
  test('splits headings, lists, tables and paragraphs', () {
    final nodes = parseAgentMarkdown('''
## MRR this month
Up **12%** since September.

- App Store: \$8K
- Google Play: \$2K
  across 3 apps

1. pro_monthly
2. pro_yearly

| Country | Revenue |
| --- | ---: |
| US | \$5K |
| DE | \$1K |
''');
    expect(nodes, hasLength(5));
    expect((nodes[0] as AgentMarkdownHeading).text, 'MRR this month');
    expect(
      (nodes[1] as AgentMarkdownParagraph).text,
      'Up **12%** since September.',
    );
    final bullets = nodes[2] as AgentMarkdownList;
    expect(bullets.items.map((i) => i.text), [
      r'App Store: $8K',
      r'Google Play: $2K across 3 apps',
    ]);
    final numbered = nodes[3] as AgentMarkdownList;
    expect(numbered.items.map((i) => i.number), ['1', '2']);
    final table = nodes[4] as AgentMarkdownTable;
    expect(table.rows, [
      ['Country', 'Revenue'],
      ['US', r'$5K'],
      ['DE', r'$1K'],
    ]);
  });

  test('inline bold, italic and code, but not snake_case ids', () {
    final spans = agentInlineSpans(
      'Top plan **pro_monthly** is *up*, see `get_chart` and pro_yearly_v2',
      const TextStyle(),
      const Color(0x00000000),
    );
    final text = spans.map((s) => s.toPlainText()).join();
    expect(
      text,
      'Top plan pro_monthly is up, see get_chart and pro_yearly_v2',
    );
    final bold = spans.whereType<TextSpan>().firstWhere(
          (s) => s.style?.fontWeight == FontWeight.w700,
        );
    expect(bold.toPlainText(), 'pro_monthly');
  });
}
