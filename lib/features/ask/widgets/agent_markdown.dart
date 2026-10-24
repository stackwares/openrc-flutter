import 'package:flutter/material.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/theme/app_tokens.dart';

/// One piece of a parsed answer.
sealed class AgentMarkdownNode {
  const AgentMarkdownNode();
}

class AgentMarkdownHeading extends AgentMarkdownNode {
  const AgentMarkdownHeading(this.level, this.text);

  final int level;
  final String text;
}

class AgentMarkdownParagraph extends AgentMarkdownNode {
  const AgentMarkdownParagraph(this.text);

  final String text;
}

class AgentMarkdownListItem {
  const AgentMarkdownListItem({
    required this.text,
    required this.depth,
    this.number,
  });

  final String text;
  final int depth;

  /// Set for numbered items (`1.` / `1)`).
  final String? number;
}

class AgentMarkdownList extends AgentMarkdownNode {
  const AgentMarkdownList(this.items);

  final List<AgentMarkdownListItem> items;
}

class AgentMarkdownTable extends AgentMarkdownNode {
  const AgentMarkdownTable(this.rows);

  /// First row is the header.
  final List<List<String>> rows;
}

class AgentMarkdownCode extends AgentMarkdownNode {
  const AgentMarkdownCode(this.text);

  final String text;
}

class AgentMarkdownRule extends AgentMarkdownNode {
  const AgentMarkdownRule();
}

final _heading = RegExp(r'^(#{1,6})\s+(.*?)\s*#*$');
final _listItem = RegExp(r'^(\s*)([-*+•]|\d{1,3}[.)])\s+(.*)$');
final _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
final _tableDivider = RegExp(r'^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$');

/// Splits the Markdown models write into blocks: headings, paragraphs,
/// lists, pipe tables, fenced code and rules.
List<AgentMarkdownNode> parseAgentMarkdown(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final nodes = <AgentMarkdownNode>[];
  final paragraph = <String>[];
  final list = <AgentMarkdownListItem>[];
  final table = <List<String>>[];

  void flush() {
    if (paragraph.isNotEmpty) {
      nodes.add(AgentMarkdownParagraph(paragraph.join('\n')));
      paragraph.clear();
    }
    if (list.isNotEmpty) {
      nodes.add(AgentMarkdownList([...list]));
      list.clear();
    }
    if (table.isNotEmpty) {
      nodes.add(AgentMarkdownTable([...table]));
      table.clear();
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.startsWith('```')) {
      flush();
      final code = <String>[];
      for (i++; i < lines.length && !lines[i].trim().startsWith('```'); i++) {
        code.add(lines[i]);
      }
      nodes.add(AgentMarkdownCode(code.join('\n')));
      continue;
    }
    if (trimmed.isEmpty) {
      flush();
      continue;
    }
    if (trimmed.startsWith('|')) {
      if (table.isEmpty) flush();
      if (!_tableDivider.hasMatch(trimmed)) table.add(_cells(trimmed));
      continue;
    }
    final heading = _heading.firstMatch(trimmed);
    if (heading != null) {
      flush();
      nodes.add(AgentMarkdownHeading(heading[1]!.length, heading[2]!));
      continue;
    }
    if (_rule.hasMatch(trimmed)) {
      flush();
      nodes.add(const AgentMarkdownRule());
      continue;
    }
    final item = _listItem.firstMatch(line);
    if (item != null) {
      if (list.isEmpty) flush();
      final marker = item[2]!;
      list.add(
        AgentMarkdownListItem(
          text: item[3]!,
          depth: (item[1]!.replaceAll('\t', '  ').length ~/ 2).clamp(0, 3),
          number: RegExp(r'^\d').hasMatch(marker)
              ? marker.substring(0, marker.length - 1)
              : null,
        ),
      );
      continue;
    }
    if (list.isNotEmpty && line.startsWith('  ')) {
      // A wrapped list item continues on an indented line.
      final last = list.removeLast();
      list.add(
        AgentMarkdownListItem(
          text: '${last.text} $trimmed',
          depth: last.depth,
          number: last.number,
        ),
      );
      continue;
    }
    if (list.isNotEmpty || table.isNotEmpty) flush();
    paragraph.add(trimmed);
  }
  flush();
  return nodes;
}

List<String> _cells(String row) {
  var body = row.trim();
  if (body.startsWith('|')) body = body.substring(1);
  if (body.endsWith('|')) body = body.substring(0, body.length - 1);
  return [for (final cell in body.split('|')) cell.trim()];
}

final _inline = RegExp(
  r'(\*\*|__)(.+?)\1'
  r'|`([^`]+)`'
  r'|(?<![\w*])\*(?![\s*])(.+?)(?<!\s)\*(?![\w*])'
  r'|(?<![\w_])_(?![\s_])(.+?)(?<!\s)_(?![\w_])'
  r'|\[([^\]]+)\]\([^)\s]+\)',
);

/// `**bold**`, `*italic*`, `` `code` `` and `[links](…)` (as their text).
List<InlineSpan> agentInlineSpans(String text, TextStyle base, Color codeFill) {
  final spans = <InlineSpan>[];
  var start = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > start) {
      spans.add(TextSpan(text: text.substring(start, m.start)));
    }
    if (m[2] != null) {
      final bold = base.copyWith(fontWeight: FontWeight.w700);
      spans.add(
        TextSpan(style: bold, children: agentInlineSpans(m[2]!, bold, codeFill)),
      );
    } else if (m[3] != null) {
      spans.add(
        TextSpan(
          text: m[3],
          style: base.copyWith(
            fontFamily: 'monospace',
            fontFamilyFallback: const ['Menlo', 'Courier'],
            fontSize: (base.fontSize ?? 14) * 0.92,
            backgroundColor: codeFill,
          ),
        ),
      );
    } else if (m[4] != null || m[5] != null) {
      spans.add(
        TextSpan(
          text: m[4] ?? m[5],
          style: base.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    } else if (m[6] != null) {
      spans.add(TextSpan(text: m[6]));
    }
    start = m.end;
  }
  if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
  return spans;
}

/// A short answer from the model, with the Markdown it tends to use drawn
/// instead of shown as symbols. Selectable so numbers can be copied.
class AgentMarkdown extends StatelessWidget {
  const AgentMarkdown(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    final nodes = parseAgentMarkdown(data);
    final scheme = context.colorScheme;
    final base = (context.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      color: scheme.onSurface,
      height: 1.45,
    );
    final codeFill = scheme.onSurface.withValues(alpha: 0.07);

    Widget rich(String text, TextStyle style) => Text.rich(
          TextSpan(style: style, children: agentInlineSpans(text, style, codeFill)),
        );

    Widget node(AgentMarkdownNode n) => switch (n) {
          AgentMarkdownHeading(:final level, :final text) => rich(
              text,
              (level <= 2
                      ? context.textTheme.titleMedium
                      : context.textTheme.titleSmall)!
                  .copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
            ),
          AgentMarkdownParagraph(:final text) => rich(text, base),
          AgentMarkdownList(:final items) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in items)
                  Padding(
                    padding: EdgeInsets.only(
                      left: item.depth * 18.0,
                      bottom: AppSpace.xxs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: item.number == null ? 18 : 26,
                          child: Text(
                            item.number == null ? '•' : '${item.number}.',
                            style: base.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFeatures: AppText.tabular,
                            ),
                          ),
                        ),
                        Expanded(child: rich(item.text, base)),
                      ],
                    ),
                  ),
              ],
            ),
          AgentMarkdownTable(:final rows) => _MarkdownTable(
              rows: rows,
              base: base,
              codeFill: codeFill,
            ),
          AgentMarkdownCode(:final text) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: codeFill,
                borderRadius: BorderRadius.circular(AppRadius.icon),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  text,
                  style: base.copyWith(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Menlo', 'Courier'],
                    fontSize: (base.fontSize ?? 14) * 0.88,
                  ),
                ),
              ),
            ),
          AgentMarkdownRule() => Divider(color: context.appColors.hairline),
        };

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < nodes.length; i++)
            Padding(
              padding: EdgeInsets.only(
                top: i == 0
                    ? 0
                    : nodes[i] is AgentMarkdownHeading
                    ? AppSpace.md
                    : AppSpace.xs,
              ),
              child: node(nodes[i]),
            ),
        ],
      ),
    );
  }
}

class _MarkdownTable extends StatelessWidget {
  const _MarkdownTable({
    required this.rows,
    required this.base,
    required this.codeFill,
  });

  final List<List<String>> rows;
  final TextStyle base;
  final Color codeFill;

  @override
  Widget build(BuildContext context) {
    final columns = rows.fold<int>(0, (n, r) => r.length > n ? r.length : n);
    final hairline = context.appColors.hairline;
    final cellStyle = base.copyWith(
      fontSize: (base.fontSize ?? 14) * 0.9,
      fontFeatures: AppText.tabular,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(horizontalInside: BorderSide(color: hairline)),
        children: [
          for (var r = 0; r < rows.length; r++)
            TableRow(
              children: [
                for (var c = 0; c < columns; c++)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 6, AppSpace.md, 6),
                    child: Text.rich(
                      TextSpan(
                        style: r == 0
                            ? cellStyle.copyWith(fontWeight: FontWeight.w700)
                            : cellStyle,
                        children: agentInlineSpans(
                          c < rows[r].length ? rows[r][c] : '',
                          r == 0
                              ? cellStyle.copyWith(fontWeight: FontWeight.w700)
                              : cellStyle,
                          codeFill,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
