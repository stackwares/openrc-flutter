import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/models/rc_chart_response.dart';
import 'package:openrc/services/rc_api_service.dart';

/// Answers every request with an empty chart and remembers what was asked.
class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"values":[]}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

RcChartDataPoint _point(DateTime utcDay, double value, {int measure = 0}) =>
    RcChartDataPoint(
      cohort: utcDay.millisecondsSinceEpoch ~/ 1000,
      measure: measure,
      value: value,
    );

int _days(DayRange r) =>
    DateTime.utc(r.end.year, r.end.month, r.end.day)
        .difference(DateTime.utc(r.start.year, r.start.month, r.start.day))
        .inDays +
    1;

void main() {
  final today = DateTime(2026, 10, 23);
  final apple = paidPayouts(PayoutStore.apple, today);
  final google = paidPayouts(PayoutStore.google, today);

  group('paid payouts', () {
    test('App Store: paid in the last 12 months, oldest first', () {
      // November 2025 had no App Store payday; three months had two.
      expect(apple, hasLength(11));
      expect(apple.first.paymentDate, DateTime(2025, 12, 4));
      expect(apple.first.earningsStart, DateTime(2025, 9, 28));
      expect(apple.last.paymentDate, DateTime(2026, 10, 1));
      expect(apple.last.earningsStart, DateTime(2026, 8, 2));
      expect(apple.last.earningsEnd, DateTime(2026, 8, 29));
    });

    test('Google Play: each month is paid the month after', () {
      expect(google, hasLength(12));
      expect(google.first.earningsStart, DateTime(2025, 10, 1));
      // The 15th was a Saturday.
      expect(google.first.paymentDate, DateTime(2025, 11, 17));
      expect(google.last.earningsEnd, DateTime(2026, 9, 30));
      expect(google.last.paymentDate, DateTime(2026, 10, 15));
    });

    test('a payday counts as paid from the next day', () {
      expect(
        paidPayouts(
          PayoutStore.google,
          DateTime(2026, 10, 15),
        ).last.paymentDate,
        DateTime(2026, 9, 15),
      );
      expect(
        paidPayouts(
          PayoutStore.google,
          DateTime(2026, 10, 16),
        ).last.paymentDate,
        DateTime(2026, 10, 15),
      );
    });

    test('ids are the store and first earning day', () {
      expect(apple.last.id, 'apple:2026-08-02');
      expect(google.last.id, 'google:2026-09-01');
    });
  });

  group('chart ranges', () {
    test('cover every day once, in requests of at most 366 days', () {
      final ranges = chartRangesFor([...apple, ...google]);
      expect(ranges.first.start, DateTime(2025, 9, 28));
      expect(ranges.last.end, DateTime(2026, 9, 30));
      expect(ranges.map(_days), [366, 2]);
      expect(
        ranges[1].start,
        DateTime(
          ranges[0].end.year,
          ranges[0].end.month,
          ranges[0].end.day + 1,
        ),
      );
    });

    test('one new payout is one short request', () {
      final ranges = chartRangesFor([google.last]);
      expect(ranges, hasLength(1));
      expect(ranges.single.start, DateTime(2026, 9, 1));
      expect(ranges.single.end, DateTime(2026, 9, 30));
    });

    test('nothing missing asks for nothing', () {
      expect(chartRangesFor(const []), isEmpty);
    });
  });

  test('the store filter goes out as one comma-joined parameter', () async {
    final adapter = _RecordingAdapter();
    final api = RcApiService(
      dio: Dio()..httpClientAdapter = adapter,
      internalDio: Dio(),
    );
    await api.charts(
      name: 'revenue',
      revenueType: 'proceeds',
      filters: {'store': PayoutStore.apple.chartStores},
    );
    final query = adapter.requests.single.uri.queryParameters;
    expect(query['store'], 'app_store,mac_app_store');
    expect(query['revenue_type'], 'proceeds');
    expect(query.containsKey('filters'), isFalse);
  });

  test('ignored query parameters are read from the response', () {
    final response = RcChartResponse.fromJson({
      'unsupported_params': {
        'filters': ['filters', 'store'],
        'segment': null,
      },
    });
    expect(response.ignoredParams, ['filters', 'store']);
    expect(RcChartResponse.fromJson(const {}).ignoredParams, isEmpty);
  });

  group('totals', () {
    test('read days in UTC and skip the transaction count series', () {
      final daily = dailyProceeds(
        RcChartResponse(
          values: [
            _point(DateTime.utc(2026, 9, 1), 10),
            _point(DateTime.utc(2026, 9, 1), 3, measure: 1),
            _point(DateTime.utc(2026, 9, 30), 5.5),
            _point(DateTime.utc(2026, 10, 1), 99),
          ],
        ),
      );
      expect(daily, {'2026-09-01': 10, '2026-09-30': 5.5, '2026-10-01': 99});
      expect(payoutTotal(google.last, daily), 15.5);
    });

    test('cohorts in milliseconds read the same', () {
      final ms = DateTime.utc(2026, 9, 2).millisecondsSinceEpoch;
      final daily = dailyProceeds(
        RcChartResponse(
          values: [RcChartDataPoint(cohort: ms, measure: 0, value: 4)],
        ),
      );
      expect(daily, {'2026-09-02': 4});
    });

    test('round to the cent', () {
      expect(
        payoutTotal(google.last, {'2026-09-01': 0.1, '2026-09-02': 0.2}),
        0.3,
      );
    });
  });

  test('the same non-zero series for both stores means an ignored filter', () {
    expect(storeFilterIgnored({'2026-09-01': 10}, {'2026-09-01': 10}), isTrue);
    expect(storeFilterIgnored({'2026-09-01': 10}, {'2026-09-01': 4}), isFalse);
    expect(storeFilterIgnored({'2026-09-01': 10}, {}), isFalse);
    expect(storeFilterIgnored({'2026-09-01': 0}, {'2026-09-01': 0}), isFalse);
    expect(storeFilterIgnored({}, {}), isFalse);
  });

  group('months', () {
    final payouts = [
      for (final p in apple) Payout(p, 100),
      for (final p in google) Payout(p, 50),
    ];

    test('run oldest first, each with its payouts newest first', () {
      final months = payoutMonths(payouts, today);
      expect(months, hasLength(12));
      expect(months.first.month, DateTime(2025, 11));
      expect(months.last.month, DateTime(2026, 10));
      expect(months.last.payouts.map((p) => p.period.paymentDate), [
        DateTime(2026, 10, 15),
        DateTime(2026, 10, 1),
      ]);
      expect(months.last.total, 150);
      expect(months.last.totalFor(PayoutStore.apple), 100);
      // November 2025: Google Play only.
      expect(months.first.payouts.single.period.store, PayoutStore.google);
      // January 2026: two App Store paydays.
      expect(months[2].totalFor(PayoutStore.apple), 200);
    });

    test('compare each payout with the same store’s one before', () {
      final previous = previousPayouts(payouts);
      expect(previous[google.first.id], isNull);
      expect(previous[apple.first.id], isNull);
      expect(
        previous[google.last.id]!.period.paymentDate,
        DateTime(2026, 9, 15),
      );
      expect(previous[apple.last.id]!.period.store, PayoutStore.apple);
    });
  });
}
