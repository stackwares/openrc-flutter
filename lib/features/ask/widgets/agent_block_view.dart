import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/region_display_name.dart';
import 'package:openrc/core/utils/store_payday_schedule.dart';
import 'package:openrc/features/ask/widgets/agent_markdown.dart';
import 'package:openrc/features/charts/overview_metric_detail_screen.dart';
import 'package:openrc/features/charts/widgets/overview_detail_line_chart.dart';
import 'package:openrc/features/charts/widgets/overview_item_card.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/features/transactions/transaction_detail_screen.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/features/transactions/widgets/transaction_item.dart';
import 'package:openrc/models/agent_block.dart';
import 'package:openrc/models/agent_block_payload.dart';
import 'package:openrc/models/overview_metric_type.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/dual_currency_text.dart';
import 'package:openrc/widgets/side_panel.dart';

/// Most rows a list or table in an answer shows.
const _maxRows = 12;
const _maxTableRows = 60;

class AgentBlockView extends StatelessWidget {
  const AgentBlockView({super.key, required this.block});

  final AgentBlock block;

  @override
  Widget build(BuildContext context) {
    final payload = AgentBlockPayload(block.payload);
    return switch (payload.resolveView(block.type)) {
      AgentPresentationType.markdown => _MarkdownBlock(
          title: block.title,
          markdown: payload.markdown ?? '',
        ),
      AgentPresentationType.metricCards => _MetricCards(
          title: block.title,
          payload: payload,
        ),
      AgentPresentationType.lineChart => _LineChartBlock(
          title: block.title,
          payload: payload,
        ),
      AgentPresentationType.barChart => _PayoutList(
          title: block.title,
          payload: payload,
        ),
      AgentPresentationType.dataTable => _DataTableBlock(
          title: block.title,
          payload: payload,
        ),
      AgentPresentationType.transactionList => _TransactionList(
          title: block.title,
          payload: payload,
        ),
    };
  }
}

class _Title extends StatelessWidget {
  const _Title(this.title);

  final String? title;

  @override
  Widget build(BuildContext context) {
    final text = title?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Text(
        text,
        style: context.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(title),
        Text(
          'agent.emptyData'.tr(),
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MarkdownBlock extends StatelessWidget {
  const _MarkdownBlock({required this.title, required this.markdown});

  final String? title;
  final String markdown;

  @override
  Widget build(BuildContext context) {
    final text = markdown.trim();
    if (text.isEmpty) return _Empty(title: title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(title),
        AgentMarkdown(text),
      ],
    );
  }
}

class _MetricCards extends StatelessWidget {
  const _MetricCards({required this.title, required this.payload});

  final String? title;
  final AgentBlockPayload payload;

  @override
  Widget build(BuildContext context) {
    final usd = payload.overviewUsd;
    final overview = payload.overview;
    final entries = <(OverviewMetricType, num)>[];
    for (final e in AgentBlockPayload.overviewMetricKeys.entries) {
      final raw = usd[e.key] ?? overview[e.key];
      if (raw is num) entries.add((e.value, raw));
    }
    if (entries.isEmpty) return _Empty(title: title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(title),
        LayoutBuilder(
          builder: (context, constraints) => GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            // Same card height as the Charts tab, so values never clip.
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: constraints.maxWidth >= 560 ? 3 : 2,
              mainAxisExtent: 128,
              mainAxisSpacing: AppSpace.xs,
              crossAxisSpacing: AppSpace.xs,
            ),
            itemBuilder: (context, i) {
              final (metric, value) = entries[i];
              return OverviewItemCard(
                metric: metric,
                value: value,
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        OverviewMetricDetailScreen(metric: metric),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

String _rangeLabel(DateTime start, DateTime end) {
  final from = (start.year == end.year ? DateFormat.MMMd() : DateFormat.yMMMd())
      .format(start);
  return '$from – ${DateFormat.yMMMd().format(end)}';
}

class _LineChartBlock extends StatefulWidget {
  const _LineChartBlock({required this.title, required this.payload});

  final String? title;
  final AgentBlockPayload payload;

  @override
  State<_LineChartBlock> createState() => _LineChartBlockState();
}

class _LineChartBlockState extends State<_LineChartBlock> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final points = widget.payload.chartPoints();
    if (points.isEmpty) return _Empty(title: widget.title);
    final metric = widget.payload.metricType();
    final days = widget.payload.chartPointDays();
    final index = (_selected ?? points.length - 1).clamp(0, points.length - 1);
    final value = points[index].value;
    final scheme = context.colorScheme;
    final valueStyle = AppText.amount(context, size: 24);
    final valueText = metric.isCurrency && value != null
        ? DualCurrencyCompactText(amount: value, style: valueStyle)
        : Text(metric.formatValue(value), style: valueStyle);
    final summary = 'agent.chartSummary'.tr(
      namedArgs: {
        'metric': metric.label,
        'count': '${points.length}',
        'last': metric.formatValue(points.last.value),
      },
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (widget.title?.trim().isNotEmpty ?? false)
                ? widget.title!
                : metric.label,
            style: context.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpace.xxs),
          valueText,
          const SizedBox(height: 2),
          Text(
            _selected == null
                ? _rangeLabel(days.first, days.last)
                : DateFormat.yMMMEd().format(days[index]),
            style: context.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Semantics(
            label: summary,
            child: OverviewDetailLineChart(
              dataPoints: points,
              lineColor: metric.color(scheme),
              metric: metric,
              rangeStart: widget.payload.rangeStart(),
              selectedIndex: index,
              onIndexChanged: (i) => setState(() => _selected = i),
            ),
          ),
        ],
      ),
    );
  }
}

/// Payouts are proceeds, so their amounts skip the fee setting.
class _PayoutList extends StatelessWidget {
  const _PayoutList({required this.title, required this.payload});

  final String? title;
  final AgentBlockPayload payload;

  @override
  Widget build(BuildContext context) {
    final next = [
      for (final p in payload.nextPaydays)
        if (p is Map) p,
    ];
    final paid = [
      for (final p in payload.payouts)
        if (p is Map) p,
    ];
    if (next.isEmpty && paid.isEmpty) return _Empty(title: title);
    final now = DateTime.now();
    final rows = <Widget>[
      for (final p in next)
        _PayoutRow(
          store: _storeLabel(p['store']),
          title: _storeLabel(p['store']),
          subtitle: [
            if (_day(p['payment_date']) case final day?) ...[
              DateFormat.yMMMd().format(day),
              paydayRelativeLine(day, now),
            ],
          ].join(' · '),
          upcoming: true,
        ),
      for (final p in paid.take(_maxRows))
        _PayoutRow(
          store: _storeLabel(p['store']),
          title: _storeLabel(p['store']),
          subtitle: switch (_day(p['payment_date'])) {
            final day? => DateFormat.yMMMd().format(day),
            null => '',
          },
          amountUsd: (p['amount_usd'] as num?)?.toDouble(),
        ),
    ];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.md,
        AppSpace.md,
        AppSpace.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title(title),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.appColors.hairline),
            rows[i],
          ],
        ],
      ),
    );
  }

  /// Older answers saved the enum name (`apple`); newer ones the label.
  static String _storeLabel(Object? store) {
    final name = '${store ?? ''}';
    for (final s in PayoutStore.values) {
      if (s.name == name) return s.label;
    }
    return name;
  }

  static DateTime? _day(Object? raw) {
    final parsed = DateTime.tryParse('${raw ?? ''}');
    return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({
    required this.store,
    required this.title,
    required this.subtitle,
    this.amountUsd,
    this.upcoming = false,
  });

  final String store;
  final String title;
  final String subtitle;
  final double? amountUsd;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final accent = upcoming ? scheme.primary : scheme.onSurfaceVariant;
    final amount = amountUsd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.icon),
            ),
            child: Icon(
              upcoming
                  ? Icons.event_available_rounded
                  : store == PayoutStore.apple.label
                  ? Icons.apple
                  : store == PayoutStore.google.label
                  ? Icons.android
                  : Icons.account_balance_outlined,
              size: 18,
              color: accent,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: upcoming ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (amount != null)
            DualCurrencyCompactText(
              amount: amount,
              textAlign: TextAlign.end,
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: AppText.tabular,
              ),
            ),
        ],
      ),
    );
  }
}

class _DataTableBlock extends StatelessWidget {
  const _DataTableBlock({required this.title, required this.payload});

  final String? title;
  final AgentBlockPayload payload;

  @override
  Widget build(BuildContext context) {
    final points = payload.chartPoints();
    if (points.isNotEmpty) return _chartTable(context);

    var columns = payload.columns;
    final rows = [
      for (final row in payload.rows)
        if (row is Map) row,
    ];
    if (rows.isEmpty) return _Empty(title: title);
    if (columns.isEmpty) {
      columns = rows.first.keys.map((k) => '$k').toList();
    }
    return _table(
      context,
      headers: [for (final c in columns) _humanize(c)],
      numeric: [
        for (final c in columns) rows.every((r) => r[c] == null || r[c] is num),
      ],
      cells: [
        for (final row in rows.take(_maxTableRows))
          [for (final c in columns) Text(_cell(row[c]))],
      ],
    );
  }

  /// A chart as rows of day and value, formatted like the chart.
  Widget _chartTable(BuildContext context) {
    final metric = payload.metricType();
    final days = payload.chartPointDays();
    final chartPoints = payload.chartPoints();
    final start = chartPoints.length > _maxTableRows
        ? chartPoints.length - _maxTableRows
        : 0;
    return _table(
      context,
      title: title ?? metric.label,
      headers: ['agent.date'.tr(), metric.label],
      numeric: const [false, true],
      cells: [
        // Newest first: the latest day is usually what was asked about.
        for (var i = chartPoints.length - 1; i >= start; i--)
          [
            Text(DateFormat.yMMMd().format(days[i])),
            if (metric.isCurrency && chartPoints[i].value != null)
              DualCurrencyCompactText(amount: chartPoints[i].value!)
            else
              Text(metric.formatValue(chartPoints[i].value)),
          ],
      ],
    );
  }

  Widget _table(
    BuildContext context, {
    String? title,
    required List<String> headers,
    required List<bool> numeric,
    required List<List<Widget>> cells,
  }) {
    final scheme = context.colorScheme;
    final cellStyle = context.textTheme.bodyMedium?.copyWith(
      fontFeatures: AppText.tabular,
    );
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: _Title(title ?? this.title),
          ),
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DefaultTextStyle.merge(
                  style: cellStyle,
                  child: DataTable(
                    horizontalMargin: AppSpace.md,
                    columnSpacing: AppSpace.lg,
                    headingRowHeight: 36,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 44,
                    dividerThickness: 0.5,
                    headingTextStyle: context.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    columns: [
                      for (var c = 0; c < headers.length; c++)
                        DataColumn(
                          label: Text(headers[c]),
                          numeric: c < numeric.length && numeric[c],
                        ),
                    ],
                    rows: [
                      for (final row in cells)
                        DataRow(cells: [for (final cell in row) DataCell(cell)]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// `payment_date` → `Payment date`.
  static String _humanize(String key) {
    final words = key.replaceAll('_', ' ').trim();
    if (words.isEmpty) return key;
    return words[0].toUpperCase() + words.substring(1);
  }

  static String _cell(Object? value) {
    return switch (value) {
      null => '—',
      num v => NumberFormat.decimalPattern().format(
          v is double ? double.parse(v.toStringAsFixed(2)) : v,
        ),
      String s when s.trim().isEmpty || s == 'null' => '—',
      String s => switch (DateTime.tryParse(s)) {
          final d? when RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s) =>
            DateFormat.yMMMd().format(d),
          _ => s,
        },
      Map() || List() => jsonEncode(value),
      _ => '$value',
    };
  }
}

class _TransactionList extends ConsumerWidget {
  const _TransactionList({required this.title, required this.payload});

  final String? title;
  final AgentBlockPayload payload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = [
      for (final t in payload.transactions)
        if (t is Map) t,
    ];
    if (rows.isEmpty) return _Empty(title: title);
    // Rows still loaded in the app open like they do on Transactions.
    final state = ref.watch(transactionsProvider);
    final loaded = <String, RcTransaction>{
      for (final day in [...state.grouped.values, ...state.jumpedDays.values])
        for (final tx in day) ?tx.storeTransactionIdentifier: tx,
    };
    final shown = rows.take(_maxRows).toList();
    return AppCard(
      padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: _Title(title),
          ),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Divider(indent: kTransactionRowDividerIndent),
            switch (loaded[shown[i]['store_transaction_id']]) {
              final tx? => TransactionItem(
                  transaction: tx,
                  onTap: () => openDetail(
                    context,
                    (context) => TransactionDetailScreen(transaction: tx),
                  ),
                ),
              null => _TransactionSummaryRow(row: shown[i]),
            },
          ],
        ],
      ),
    );
  }
}

/// A transaction the app no longer has loaded: what the answer recorded.
class _TransactionSummaryRow extends StatelessWidget {
  const _TransactionSummaryRow({required this.row});

  final Map row;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final store = row['store'] as String?;
    final country = row['country'] as String?;
    final purchased = DateTime.tryParse('${row['purchase_date'] ?? ''}');
    final subtitle = [
      ?store,
      if (country != null && country.isNotEmpty)
        '${countryFlagEmoji(country)} ${regionDisplayNameEnglish(country)}',
      if (purchased != null)
        DateFormat.MMMd().add_jm().format(purchased.toLocal()),
    ].join(' · ');
    final usd = row['revenue_usd'];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: 10,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.icon),
            ),
            child: Icon(
              transactionStoreIcon(store) ?? Icons.receipt_long_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['app'] ?? row['product'] ?? '—'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (usd is num)
            DualCurrencyCompactText(
              amount: usd.toDouble(),
              commissionStore: store,
              textAlign: TextAlign.end,
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: AppText.tabular,
              ),
            ),
        ],
      ),
    );
  }
}
