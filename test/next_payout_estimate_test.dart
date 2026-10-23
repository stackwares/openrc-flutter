import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/core/utils/store_payday_schedule.dart';
import 'package:revenuecat/features/revenue/revenue_next_payday_proceeds.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/commission_settings_store.dart';

RcTransaction _sale(String store, DateTime day) => RcTransaction(
  store: store,
  revenue: 10,
  purchaseDate: DateTime(day.year, day.month, day.day, 12).toIso8601String(),
);

void main() {
  test('payout estimates subtract store fees even when display is gross', () {
    final apple = AppStorePayday.upcoming!;
    final google = GooglePlayPayday.upcoming!;
    final est = computeNextPaydayProceedsEstimate(
      [
        _sale('App Store', apple.startDate),
        _sale('Play Store', google.earningsStart),
      ],
      const CommissionSettings(
        adjustmentEnabled: false,
        appleCommissionPercent: 15,
        googleCommissionPercent: 30,
      ),
    );
    expect(est.appleNetUsd, closeTo(8.5, 1e-9));
    expect(est.googleNetUsd, closeTo(7.0, 1e-9));
  });
}
