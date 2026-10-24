import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/ask/ask_context.dart';
import 'package:openrc/models/rc_transaction.dart';

void main() {
  test('selected day uses today and yesterday labels', () {
    final now = DateTime(2026, 10, 24);
    expect(
      AskPrefills.selectedDay('2026-10-24', now: now),
      'Explain Today',
    );
    expect(
      AskPrefills.selectedDay('2026-10-23', now: now),
      'Explain Yesterday',
    );
    expect(
      AskPrefills.selectedDay('2026-10-20', now: now),
      contains('Oct'),
    );
  });

  test('chart range can name a metric', () {
    expect(
      AskPrefills.chartRange(range: 'Oct 1 – Oct 24, 2026'),
      'Explain this Oct 1 – Oct 24, 2026 range',
    );
    expect(
      AskPrefills.chartRange(metric: 'MRR', range: 'Last 30 days'),
      'Explain MRR over Last 30 days',
    );
  });

  test('payout and sale prefills are specific questions', () {
    expect(AskPrefills.payout(), contains('payout'));
    expect(AskPrefills.sale(), contains('sale'));
  });

  test('a refund transaction names the type', () {
    const tx = RcTransaction(wasRefunded: true);
    expect(AskPrefills.transaction(tx), contains('Refunded'));
    expect(AskPrefills.transaction(null), AskPrefills.sale());
  });
}
