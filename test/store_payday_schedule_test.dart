import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/core/utils/store_payday_schedule.dart';

void main() {
  test('the fiscal rules reproduce every published App Store row', () {
    final published = AppStorePayday.published;
    expect(published, isNotEmpty);
    final years = published.map((p) => p.fiscalYear).toSet();
    for (final fy in years) {
      final projected = AppStorePayday.projectFiscalYear(fy);
      final rows = published.where((p) => p.fiscalYear == fy).toList();
      expect(projected.length, rows.length, reason: 'FY$fy months');
      for (var i = 0; i < rows.length; i++) {
        expect(projected[i].startDate, rows[i].startDate, reason: 'FY$fy #$i');
        expect(projected[i].endDate, rows[i].endDate, reason: 'FY$fy #$i');
        expect(
          projected[i].paymentDate,
          rows[i].paymentDate,
          reason: 'FY$fy #$i',
        );
        expect(projected[i].fiscalMonthStart, rows[i].fiscalMonthStart);
      }
    }
  });

  test('there is always a next App Store payout after the table ends', () {
    final last = AppStorePayday.published.last;
    final next = AppStorePayday.upcomingOn(
      DateTime(
        last.paymentDate.year,
        last.paymentDate.month,
        last.paymentDate.day + 1,
      ),
    );
    expect(next, isNotNull);
    expect(next!.isProjected, isTrue);
    expect(next.startDate, DateTime(2026, 9, 27));
    expect(next.endDate, DateTime(2026, 10, 31));
    expect(next.paymentDate, DateTime(2026, 12, 3));

    for (
      var d = DateTime(2026, 10, 1);
      d.isBefore(DateTime(2030, 1, 1));
      d = DateTime(d.year, d.month, d.day + 7)
    ) {
      expect(AppStorePayday.upcomingOn(d), isNotNull, reason: '$d');
    }
  });

  test('a 53-week fiscal year puts the extra week in December', () {
    final fy2028 = AppStorePayday.projectFiscalYear(2028);
    expect(AppStorePayday.fiscalYearEnd(2028), DateTime(2028, 9, 30));
    final december = fy2028[2];
    expect(december.endDate.difference(december.startDate).inDays + 1, 35);
    expect(fy2028.last.endDate, DateTime(2028, 9, 30));
  });
}
