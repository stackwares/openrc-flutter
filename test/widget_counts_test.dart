import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/services/widget_data_channel.dart';

void main() {
  test('home screen widget counts match the app tiles', () {
    final day = [
      // Trial the user already turned off: a trial and a cancellation.
      const RcTransaction(isTrialPeriod: true, isAutoRenewing: false),
      // Renewal with a cancellation detected: a renewal and a cancellation.
      const RcTransaction(
        isRenewal: true,
        revenue: 9.99,
        unsubscribeDetectedAt: '2026-10-23T08:00:00Z',
      ),
      const RcTransaction(isTrialConversion: true, revenue: 39.99),
      const RcTransaction(wasRefunded: true, revenue: -4.99),
    ];
    final widget = WidgetDataChannel.buildTransactionsSummary(
      day,
      const [],
      const CommissionSettings(),
      'USD',
      const {},
    );
    final app = aggregateDayCounts(day);
    expect(widget['trials'], app.trials);
    expect(widget['renewals'], app.renewals);
    expect(widget['conversions'], app.conversions);
    expect(widget['purchases'], app.purchases);
    expect(widget['refunds'], app.refunds);
    expect(widget['cancellations'], app.cancelled);
    expect(widget['trials'], 1);
    expect(widget['cancellations'], 2);
  });
}
