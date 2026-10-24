import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:openrc/core/utils/store_payday_schedule.dart';
import 'package:openrc/core/utils/subscriber_id_mask.dart';
import 'package:openrc/features/charts/home_notifier.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/features/revenue/payout_history_provider.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/models/overview_metric_type.dart';
import 'package:openrc/models/rc_chart_response.dart';
import 'package:openrc/models/rc_overview_response.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/agent/agent_display_money.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/services/rc_api_service.dart';

const kAgentToolResultMaxChars = 12000;
const kAgentTransactionLimit = 50;

/// Tools the model may call; each has an `agent.status.tool.<name>` line.
const kAgentToolNames = {
  'list_projects',
  'get_overview',
  'get_chart',
  'get_transactions',
  'get_payout_context',
  'present',
};

final agentToolExecutorProvider = Provider<AgentToolExecutor>(
  (ref) => AgentToolExecutor(ref),
);

class AgentToolExecutor {
  AgentToolExecutor(this._ref);

  final Ref _ref;

  Future<Map<String, dynamic>> run(
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (name) {
      case 'list_projects':
        return _cap(await _listProjects());
      case 'get_overview':
        return _cap(await _getOverview());
      case 'get_chart':
        return _cap(await _getChart(args));
      case 'get_transactions':
        return _cap(await _getTransactions(args, allowRefetch: true));
      case 'get_payout_context':
        return _cap(await _getPayoutContext());
      case 'present':
        return args;
      default:
        return {'error': 'unknown_tool', 'name': name};
    }
  }

  /// Compact, already-loaded context for the system prompt. Never includes
  /// the RevenueCat session or a transaction dump.
  Map<String, dynamic> snapshot() {
    final money = AgentDisplayMoney.fromRef(_ref);
    final home = _ref.read(homeProvider);
    final projects = _ref.read(rcAccountProjectsProvider).asData?.value;
    return {
      ...money.meta(),
      'today': _fmtDate(DateTime.now()),
      'locale': Intl.getCurrentLocale(),
      'selected_day': _ref.read(transactionsProvider).selectedDayKey,
      'chart_range': {
        'start': _fmtDate(home.chartRangeStart),
        'end': _fmtDate(home.chartRangeEnd),
      },
      if (projects != null)
        'projects': [
          for (final p in projects.take(12)) p.name,
        ],
      if (home.overview != null)
        'overview': _overviewMaps(home.overview!, money)['overview'],
    };
  }

  Map<String, dynamic> _cap(Map<String, dynamic> map) {
    final encoded = jsonEncode(map);
    if (encoded.length <= kAgentToolResultMaxChars) return map;
    return {
      'truncated': true,
      'preview': encoded.substring(0, kAgentToolResultMaxChars),
    };
  }

  Future<Map<String, dynamic>> _listProjects() async {
    final cached = _ref.read(rcAccountProjectsProvider).asData?.value;
    final projects = cached ?? await _ref.read(rcApiServiceProvider).projects();
    return {
      'projects': projects
          .map((p) => {'id': p.id, 'name': p.name})
          .toList(growable: false),
    };
  }

  Future<Map<String, dynamic>> _getOverview() async {
    final money = AgentDisplayMoney.fromRef(_ref);
    final home = _ref.read(homeProvider);
    if (home.overview != null) {
      return _overviewMaps(home.overview!, money);
    }
    final overview = await _ref.read(rcApiServiceProvider).overview();
    return _overviewMaps(overview, money);
  }

  Map<String, dynamic> _overviewMaps(
    RcOverviewResponse o,
    AgentDisplayMoney money,
  ) {
    // Charts shows these before store fees, so the answer matches its cards.
    double? moneyValue(num? usd) =>
        usd == null ? null : money.convert(usd.toDouble());
    return {
      ...money.meta(fees: false),
      'overview': {
        'mrr': moneyValue(o.mrr),
        'subscriptions': o.subscriptions,
        'trials': o.trials,
        'revenue': moneyValue(o.revenue),
        'users': o.users,
        'new_users': o.newUsers,
      },
      'overview_usd': {
        'mrr': o.mrr,
        'subscriptions': o.subscriptions,
        'trials': o.trials,
        'revenue': o.revenue,
        'users': o.users,
        'new_users': o.newUsers,
      },
    };
  }

  Map<String, dynamic> _chartMap(RcChartResponse c) => {
        'values': c.values
            ?.map(
              (p) => {
                'cohort': p.cohort,
                'measure': p.measure,
                'value': p.value,
              },
            )
            .toList(),
        'summary': c.summary,
      };

  Future<Map<String, dynamic>> _getChart(Map<String, dynamic> args) async {
    final money = AgentDisplayMoney.fromRef(_ref);
    final metricName = _string(args['metric']) ?? 'mrr';
    final metric = OverviewMetricType.values.firstWhere(
      (m) => m.chartName == metricName || m.name == metricName,
      orElse: () => OverviewMetricType.mrr,
    );
    final home = _ref.read(homeProvider);
    final start = _string(args['start_date']) ?? _fmtDate(home.chartRangeStart);
    final end = _string(args['end_date']) ?? _fmtDate(home.chartRangeEnd);
    final cached = home.charts[metric];
    final RcChartResponse chart;
    if (cached != null &&
        start == _fmtDate(home.chartRangeStart) &&
        end == _fmtDate(home.chartRangeEnd)) {
      chart = cached;
    } else {
      chart = await _ref.read(rcApiServiceProvider).charts(
            name: metric.chartName,
            startDate: start,
            endDate: end,
            resolution: (args['resolution'] as num?)?.toInt() ?? 0,
          );
    }
    final lastUsd = chart.values
        ?.map((p) => p.value)
        .whereType<double>()
        .lastOrNull;
    return {
      ...money.meta(fees: false),
      'metric': metric.chartName,
      'chart': _chartMap(chart),
      'range_start': start,
      'range_end': end,
      if (lastUsd != null && metric.isCurrency)
        'last_display': money.convert(lastUsd),
      if (lastUsd != null && !metric.isCurrency) 'last_value': lastUsd,
    };
  }

  Future<Map<String, dynamic>> _getTransactions(
    Map<String, dynamic> args, {
    required bool allowRefetch,
  }) async {
    final limit =
        (args['limit'] as num?)?.toInt().clamp(1, kAgentTransactionLimit) ??
            kAgentTransactionLimit;
    final day = _string(args['day']);
    final startDate = _string(args['start_date']);
    final endDate = _string(args['end_date']);
    final money = AgentDisplayMoney.fromRef(_ref);
    final state = _ref.read(transactionsProvider);
    final rows = <Map<String, dynamic>>[];
    for (final dayRows in [...state.grouped.values, ...state.jumpedDays.values]) {
      for (final tx in dayRows) {
        if (!_transactionInRange(tx, day: day, start: startDate, end: endDate)) {
          continue;
        }
        rows.add(_transactionRow(tx, money));
        if (rows.length >= limit) break;
      }
      if (rows.length >= limit) break;
    }
    if (rows.isEmpty && allowRefetch && !state.isLoading) {
      await _ref.read(transactionsProvider.notifier).fetchInitial();
      return _getTransactions(args, allowRefetch: false);
    }
    return {
      ...money.meta(),
      'transactions': rows,
    };
  }

  bool _transactionInRange(
    RcTransaction tx, {
    String? day,
    String? start,
    String? end,
  }) {
    final purchased = tx.purchaseDate;
    if (purchased == null) return day == null && start == null && end == null;
    final key = purchased.length >= 10 ? purchased.substring(0, 10) : purchased;
    if (day != null && day.isNotEmpty) return key == day;
    if (start != null && key.compareTo(start) < 0) return false;
    if (end != null && key.compareTo(end) > 0) return false;
    return true;
  }

  Map<String, dynamic> _transactionRow(
    RcTransaction tx,
    AgentDisplayMoney money,
  ) {
    final usd = tx.revenue;
    final sub = tx.subscriberId;
    return {
      'product': tx.productIdentifier,
      'app': tx.app?.name,
      'store': tx.store,
      'country': tx.subscriberCountryCode,
      'revenue_usd': ?usd,
      if (usd != null) 'revenue': money.toDisplay(usd, store: tx.store),
      'purchase_date': tx.purchaseDate,
      'subscriber_id': sub == null ? null : maskSubscriberId(sub),
      'store_transaction_id': tx.storeTransactionIdentifier,
    };
  }

  Future<Map<String, dynamic>> _getPayoutContext() async {
    final money = AgentDisplayMoney.fromRef(_ref);
    await _ref.read(payoutHistoryProvider.notifier).load();
    final amounts = _ref.read(payoutHistoryProvider).amounts;
    final now = DateTime.now();
    // Newest first, so the 12 kept are the latest from both stores.
    final paid = [
      for (final store in PayoutStore.values) ...paidPayouts(store, now),
    ]..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    final apple = AppStorePayday.upcomingOn(now);
    final google = GooglePlayPayday.upcoming;
    // Payouts are proceeds: the stores already took their fees.
    return {
      ...money.meta(fees: false),
      'next_paydays': [
        if (apple != null)
          _payday(
            PayoutStore.apple,
            apple.paymentDate,
            apple.startDate,
            apple.endDate,
          ),
        if (google != null)
          _payday(
            PayoutStore.google,
            google.paymentDate,
            google.earningsStart,
            google.earningsEnd,
          ),
      ],
      'payouts': paid
          .take(12)
          .map(
            (p) {
              final usd = amounts[p.id];
              return {
                'id': p.id,
                'store': p.store.label,
                'payment_date': _fmtDate(p.paymentDate),
                'earnings_start': _fmtDate(p.earningsStart),
                'earnings_end': _fmtDate(p.earningsEnd),
                'amount_usd': ?usd,
                if (usd != null) 'amount': money.convert(usd),
              };
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, dynamic> _payday(
    PayoutStore store,
    DateTime paymentDate,
    DateTime earningsStart,
    DateTime earningsEnd,
  ) =>
      {
        'store': store.label,
        'payment_date': _fmtDate(paymentDate),
        'earnings_start': _fmtDate(earningsStart),
        'earnings_end': _fmtDate(earningsEnd),
      };

  /// Models sometimes send numbers or nulls where a string belongs.
  static String? _string(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
}

/// OpenAI-style tool definitions for the LLM.
List<Map<String, dynamic>> agentToolDefinitions() => [
      {
        'type': 'function',
        'function': {
          'name': 'list_projects',
          'description': 'List RevenueCat projects for this account.',
          'parameters': {'type': 'object', 'properties': {}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'get_overview',
          'description': 'Fetch dashboard overview KPIs (MRR, revenue, etc.).',
          'parameters': {'type': 'object', 'properties': {}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'get_chart',
          'description': 'Fetch a chart series for a metric over a date range.',
          'parameters': {
            'type': 'object',
            'properties': {
              'metric': {
                'type': 'string',
                'description':
                    'Metric api name, e.g. mrr, revenue, active_subscriptions',
              },
              'start_date': {'type': 'string', 'description': 'yyyy-MM-dd'},
              'end_date': {'type': 'string', 'description': 'yyyy-MM-dd'},
            },
            'required': ['metric'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'get_transactions',
          'description':
              'Transactions already loaded in the app, optionally for a day or range.',
          'parameters': {
            'type': 'object',
            'properties': {
              'limit': {'type': 'integer', 'maximum': kAgentTransactionLimit},
              'day': {
                'type': 'string',
                'description': 'Calendar day yyyy-MM-dd',
              },
              'start_date': {'type': 'string', 'description': 'yyyy-MM-dd'},
              'end_date': {'type': 'string', 'description': 'yyyy-MM-dd'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'get_payout_context',
          'description':
              'Next payday per store (next_paydays) and the last 12 '
              'months of paid payouts, newest first.',
          'parameters': {'type': 'object', 'properties': {}},
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'present',
          'description':
              'Choose how to show data to the user. Call after fetching data.',
          'parameters': {
            'type': 'object',
            'properties': {
              'type': {
                'type': 'string',
                'enum': [
                  'metric_cards',
                  'line_chart',
                  'bar_chart',
                  'data_table',
                  'transaction_list',
                  'markdown',
                ],
              },
              'title': {'type': 'string'},
              'from_tool': {
                'type': 'string',
                'description': 'tool_call_id of the data tool',
              },
              'markdown': {'type': 'string'},
            },
            'required': ['type'],
          },
        },
      },
    ];
