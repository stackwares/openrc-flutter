import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/features/transactions/transactions_revenue_insights_compute.dart';
import 'package:revenuecat/features/transactions/transactions_screen.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/commission_settings_store.dart';

/// Pushes serialized transaction/revenue data to the native iOS side for
/// WidgetKit rendering via App Group UserDefaults.
class WidgetDataChannel {
  static const _channel = MethodChannel('com.revenuecat.client/widgets');

  WidgetDataChannel._();

  /// Clears all widget data from the native side.
  static Future<void> clearWidgetData() async {
    try {
      await _channel.invokeMethod('clearWidgetData');
    } on PlatformException catch (e) {
      print('WidgetDataChannel clear PlatformException: $e');
    } catch (e) {
      print('WidgetDataChannel clear error: $e');
    }
  }

  /// Computes all widget data from the current [state] and [commission] and
  /// pushes it to the native side.
  static Future<void> pushWidgetData(
    TransactionsState state,
    CommissionSettings commission,
    String displayCurrency,
    Map<String, double> exchangeRates,
  ) async {
    if (state.grouped.isEmpty) return;

    try {
      final payload = _sanitize(_buildPayload(state, commission, displayCurrency, exchangeRates));
      await _channel.invokeMethod('updateWidgetData', payload);
    } on PlatformException catch (e) {
      // Widget extension may not be installed — silently ignore.
      print('WidgetDataChannel PlatformException: $e');
    } catch (e) {
      // Non-critical: don't let widget sync break the app.
      print('WidgetDataChannel error: $e');
    }
  }

  static String _effectiveCurrency(String displayCurrency, Map<String, double> rates) {
    final c = displayCurrency.toUpperCase();
    if (c == 'USD') return 'USD';
    return rates.containsKey(c.toLowerCase()) ? c : 'USD';
  }

  static double _convert(double usd, String effectiveCurrency, Map<String, double> rates) {
    if (effectiveCurrency == 'USD') return usd;
    return usd * (rates[effectiveCurrency.toLowerCase()] ?? 1.0);
  }

  /// Sanitizes a value for JSON serialization. Replaces NaN and Infinity with 0.0
  /// and strips nulls from nested maps.
  static dynamic _sanitize(dynamic value) {
    if (value is double) {
      if (value.isNaN || value.isInfinite) return 0.0;
      return value;
    }
    if (value is Map<String, dynamic>) {
      return value.map((k, v) => MapEntry(k, _sanitize(v)));
    }
    if (value is List) {
      return value.map(_sanitize).toList();
    }
    return value;
  }

  static Map<String, dynamic> _buildPayload(
    TransactionsState state,
    CommissionSettings commission,
    String displayCurrency,
    Map<String, double> exchangeRates,
  ) {
    final currency = _effectiveCurrency(displayCurrency, exchangeRates);
    final todayKey = localTodayDayKey();
    final todayTxs = state.grouped[todayKey] ?? [];
    final yesterdayKey = _yesterdayDayKey();
    final yesterdayTxs = state.grouped[yesterdayKey] ?? [];

    // Month-to-date transactions
    final mtdTxs = collectTransactionsInCurrentLocalMonth(state.grouped);

    // Transaction summary: today's transactions for the Transactions Widget
    final summary = _buildTransactionsSummary(todayTxs, yesterdayTxs, commission, currency, exchangeRates);

    // Revenue insights: computed from MTD transactions
    final insights = _buildRevenueInsights(mtdTxs, commission, currency, exchangeRates);

    // Revenue tab: multiple time periods
    final revenueTab = _buildRevenueTab(state, commission, mtdTxs, currency, exchangeRates);

    return {
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
      'transactionsSummary': summary,
      'revenueInsights': insights,
      'revenueTab': revenueTab,
      'currencyCode': currency,
    };
  }

  static Map<String, dynamic> _buildTransactionsSummary(
    List<RcTransaction> todayTxs,
    List<RcTransaction> yesterdayTxs,
    CommissionSettings commission,
    String currency,
    Map<String, double> exchangeRates,
  ) {
    final todayRevenue = _convert(netRevenueSum(todayTxs, commission), currency, exchangeRates);
    final yesterdayRevenue = _convert(netRevenueSum(yesterdayTxs, commission), currency, exchangeRates);

    // Count by type for today
    int trials = 0;
    int conversions = 0;
    int renewals = 0;
    int purchases = 0;
    int refunds = 0;
    int cancellations = 0;

    for (final tx in todayTxs) {
      if (tx.isSandbox == true) continue;
      final t = tx.type;
      if (t == RcTransactionType.trial) trials++;
      if (t == RcTransactionType.conversion) conversions++;
      if (t == RcTransactionType.renewal) renewals++;
      if (t == RcTransactionType.newSubscription ||
          t == RcTransactionType.oneTimePurchase) {
        purchases++;
      }
      if (t == RcTransactionType.refund) refunds++;
      if (tx.isCancelledSummaryBadge) cancellations++;
    }

    return {
      'totalRevenue': todayRevenue,
      'yesterdayRevenue': yesterdayRevenue,
      'trials': trials,
      'conversions': conversions,
      'renewals': renewals,
      'purchases': purchases,
      'refunds': refunds,
      'cancellations': cancellations,
    };
  }

  static Map<String, dynamic> _buildRevenueInsights(
    List<RcTransaction> txs,
    CommissionSettings commission,
    String currency,
    Map<String, double> exchangeRates,
  ) {
    final snapshot = computeRevenueInsights(txs, commission);

    return {
      'applePct': snapshot.applePct,
      'googlePct': snapshot.googlePct,
      'appleRevenue': _convert(snapshot.appleRevenue, currency, exchangeRates),
      'googleRevenue': _convert(snapshot.googleRevenue, currency, exchangeRates),
      'newPct': snapshot.newPct,
      'renewalPct': snapshot.renewalPct,
      'newRevenue': _convert(snapshot.newRevenue, currency, exchangeRates),
      'renewalRevenue': _convert(snapshot.renewalRevenue, currency, exchangeRates),
      'topApps': snapshot.topApps
          .map(
            (a) => {
              'label': a.label,
              'pct': a.pct,
              'revenue': _convert(a.revenue, currency, exchangeRates),
            },
          )
          .toList(),
      'topCountries': snapshot.topCountries
          .map(
            (c) => {
              'code': c.countryKey,
              'name': c.name,
              'pct': c.pct,
              'revenue': _convert(c.revenue, currency, exchangeRates),
            },
          )
          .toList(),
    };
  }

  static Map<String, dynamic> _buildRevenueTab(
    TransactionsState state,
    CommissionSettings commission,
    List<RcTransaction> mtdTxs,
    String currency,
    Map<String, double> exchangeRates,
  ) {
    final mtdRevenue = _convert(netRevenueSum(mtdTxs, commission), currency, exchangeRates);

    final todayKey = localTodayDayKey();
    final todayTxs = state.grouped[todayKey] ?? [];
    final todayRevenue = _convert(netRevenueSum(todayTxs, commission), currency, exchangeRates);

    final yesterdayKey = _yesterdayDayKey();
    final yesterdayTxs = state.grouped[yesterdayKey] ?? [];
    final yesterdayRevenue = _convert(netRevenueSum(yesterdayTxs, commission), currency, exchangeRates);

    final last7Txs = collectTransactionsInLastLocalDays(state.grouped, 7);
    final last7Revenue = _convert(netRevenueSum(last7Txs, commission), currency, exchangeRates);

    final last30Txs = collectTransactionsInLastLocalDays(state.grouped, 30);
    final last30Revenue = _convert(netRevenueSum(last30Txs, commission), currency, exchangeRates);

    return {
      'mtdRevenue': mtdRevenue,
      'mtdLabel': kRealtimeWindowSubtitle,
      'todayRevenue': todayRevenue,
      'yesterdayRevenue': yesterdayRevenue,
      'last7DaysRevenue': last7Revenue,
      'last30DaysRevenue': last30Revenue,
    };
  }

  static String _yesterdayDayKey() {
    final n = DateTime.now();
    final yesterday = DateTime(n.year, n.month, n.day)
        .subtract(const Duration(days: 1));
    return '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
  }
}
