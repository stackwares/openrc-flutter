import 'package:openrc/core/utils/store_commission.dart';
import 'package:openrc/core/utils/store_payday_schedule.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/models/rc_chart_response.dart';
import 'package:openrc/models/rc_transaction.dart';

/// A store that pays developers on its own schedule.
enum PayoutStore {
  apple(['app_store', 'mac_app_store']),
  google(['play_store']);

  const PayoutStore(this.chartStores);

  /// RevenueCat `store` chart filter values whose proceeds this store pays.
  final List<String> chartStores;
}

/// One store payment: the days it pays for and the day it is paid.
class PayoutPeriod {
  const PayoutPeriod({
    required this.store,
    required this.earningsStart,
    required this.earningsEnd,
    required this.paymentDate,
    this.isProjected = false,
  });

  final PayoutStore store;

  /// First and last earning days, inclusive (local calendar dates).
  final DateTime earningsStart;
  final DateTime earningsEnd;
  final DateTime paymentDate;

  /// Pay date computed from Apple's fiscal rules, not its published calendar.
  final bool isProjected;

  /// Key for the payout's saved total.
  String get id => '${store.name}:${dayKey(earningsStart)}';

  @override
  bool operator ==(Object other) => other is PayoutPeriod && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A paid payout and RevenueCat's proceeds for its days.
class Payout {
  const Payout(this.period, this.amount);

  final PayoutPeriod period;

  /// USD after store fees and estimated taxes.
  final double amount;
}

/// Payouts paid in one calendar month.
class PayoutMonth {
  const PayoutMonth(this.month, this.payouts);

  /// First day of the month.
  final DateTime month;

  /// Newest first.
  final List<Payout> payouts;

  double get total => payouts.fold(0, (sum, p) => sum + p.amount);

  double totalFor(PayoutStore store) => payouts
      .where((p) => p.period.store == store)
      .fold(0, (sum, p) => sum + p.amount);
}

/// An inclusive run of calendar days.
class DayRange {
  const DayRange(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

/// How many months the history covers, ending with the current one.
const payoutHistoryMonths = 12;

/// Longest run of days asked for in one chart request, as on the Charts tab.
const maxChartRequestDays = 366;

/// Sales this store pays in [period]'s earnings window.
List<RcTransaction> transactionsForPayout(
  Iterable<RcTransaction> transactions,
  PayoutPeriod period,
) {
  final platform = switch (period.store) {
    PayoutStore.apple => StoreCommissionPlatform.apple,
    PayoutStore.google => StoreCommissionPlatform.google,
  };
  return collectTransactionsInLocalInclusiveRange(
    [
      for (final tx in transactions)
        if (classifyStore(tx.storeForCommission) == platform) tx,
    ],
    start: period.earningsStart,
    end: period.earningsEnd,
  );
}

/// `yyyy-MM-dd` for a calendar day; also the chart API's date format.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// First day of the oldest month in the history.
DateTime payoutWindowStart(DateTime today) =>
    DateTime(today.year, today.month - (payoutHistoryMonths - 1), 1);

/// Payouts [store] made in the history window, oldest first. A payout counts
/// once its pay date has passed: on the day itself it is still the next one.
List<PayoutPeriod> paidPayouts(PayoutStore store, DateTime today) {
  final from = payoutWindowStart(today);
  final day = DateTime(today.year, today.month, today.day);
  return [
    for (final p in _schedule(store, from, day))
      if (!p.paymentDate.isBefore(from) && p.paymentDate.isBefore(day)) p,
  ];
}

Iterable<PayoutPeriod> _schedule(
  PayoutStore store,
  DateTime from,
  DateTime to,
) sync* {
  switch (store) {
    case PayoutStore.apple:
      for (final p in AppStorePayday.all) {
        yield PayoutPeriod(
          store: store,
          earningsStart: p.startDate,
          earningsEnd: p.endDate,
          paymentDate: p.paymentDate,
          isProjected: p.isProjected,
        );
      }
    case PayoutStore.google:
      // Each month is paid the next, so start a month before the window.
      for (
        var m = DateTime(from.year, from.month - 1);
        !m.isAfter(to);
        m = DateTime(m.year, m.month + 1)
      ) {
        final p = GooglePlayPayday.forEarningsMonth(m.year, m.month);
        yield PayoutPeriod(
          store: store,
          earningsStart: p.earningsStart,
          earningsEnd: p.earningsEnd,
          paymentDate: p.paymentDate,
        );
      }
  }
}

/// The days [periods] cover as one run, split into requests of at most
/// [maxDays] days.
List<DayRange> chartRangesFor(
  Iterable<PayoutPeriod> periods, {
  int maxDays = maxChartRequestDays,
}) {
  if (periods.isEmpty) return const [];
  var start = periods
      .map((p) => p.earningsStart)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final end = periods
      .map((p) => p.earningsEnd)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final out = <DayRange>[];
  while (!start.isAfter(end)) {
    final last = DateTime(start.year, start.month, start.day + maxDays - 1);
    final chunkEnd = last.isAfter(end) ? end : last;
    out.add(DayRange(start, chunkEnd));
    start = DateTime(chunkEnd.year, chunkEnd.month, chunkEnd.day + 1);
  }
  return out;
}

/// Daily amounts from a day-resolution `charts_v2/revenue` response, by
/// [dayKey]. Days are read in UTC, the timezone RevenueCat charts use.
Map<String, double> dailyProceeds(RcChartResponse response) {
  final out = <String, double>{};
  for (final point in response.values ?? const <RcChartDataPoint>[]) {
    // Series 0 is the amount; series 1 counts transactions.
    if ((point.measure ?? 0) != 0) continue;
    final c = point.cohort;
    if (c == null || c <= 0) continue;
    final ms = c < 10000000000 ? c * 1000 : c;
    final key = dayKey(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
    out[key] = (out[key] ?? 0) + (point.value ?? 0);
  }
  return out;
}

/// Proceeds over [period]'s earning days, to the cent.
double payoutTotal(PayoutPeriod period, Map<String, double> daily) {
  var sum = 0.0;
  for (
    var d = period.earningsStart;
    !d.isAfter(period.earningsEnd);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    sum += daily[dayKey(d)] ?? 0;
  }
  return (sum * 100).roundToDouble() / 100;
}

/// True when two stores came back with the same non-zero days: RevenueCat
/// ignored the store filter and sent the all-store total for both.
bool storeFilterIgnored(Map<String, double> a, Map<String, double> b) {
  var anyRevenue = false;
  for (final key in {...a.keys, ...b.keys}) {
    final x = a[key] ?? 0;
    if ((x - (b[key] ?? 0)).abs() > 0.005) return false;
    if (x.abs() > 0.005) anyRevenue = true;
  }
  return anyRevenue;
}

/// The history's months, oldest first, each with the payouts it received.
List<PayoutMonth> payoutMonths(Iterable<Payout> payouts, DateTime today) {
  final from = payoutWindowStart(today);
  final out = <PayoutMonth>[];
  for (var i = 0; i < payoutHistoryMonths; i++) {
    final month = DateTime(from.year, from.month + i);
    final paid =
        payouts
            .where(
              (p) =>
                  p.period.paymentDate.year == month.year &&
                  p.period.paymentDate.month == month.month,
            )
            .toList()
          ..sort(
            (a, b) => b.period.paymentDate.compareTo(a.period.paymentDate),
          );
    out.add(PayoutMonth(month, paid));
  }
  return out;
}

/// Each payout's predecessor from the same store, by [PayoutPeriod.id].
Map<String, Payout> previousPayouts(Iterable<Payout> payouts) {
  final out = <String, Payout>{};
  for (final store in PayoutStore.values) {
    final mine = payouts.where((p) => p.period.store == store).toList()
      ..sort((a, b) => a.period.paymentDate.compareTo(b.period.paymentDate));
    for (var i = 1; i < mine.length; i++) {
      out[mine[i].period.id] = mine[i - 1];
    }
  }
  return out;
}
