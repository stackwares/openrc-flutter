import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/ask/ask_context.dart';
import 'package:openrc/models/rc_transaction.dart';

void main() {
  test('selected day names the day and asks about it', () {
    final now = DateTime(2026, 10, 24);
    final today = AskPrefills.selectedDay('2026-10-24', now: now);
    expect(today.kind, AskContextKind.day);
    expect(today.label, 'Today');
    expect(today.prompt, 'Explain Today');

    final yesterday = AskPrefills.selectedDay('2026-10-23', now: now);
    expect(yesterday.label, 'Yesterday');
    expect(yesterday.prompt, 'Explain Yesterday');

    final older = AskPrefills.selectedDay('2026-10-20', now: now);
    expect(older.label, contains('Oct'));
    expect(older.prompt, contains('Oct'));
  });

  test('chart range names the metric', () {
    final range = AskPrefills.chartRange(range: 'Oct 1 – Oct 24, 2026');
    expect(range.kind, AskContextKind.charts);
    expect(range.label, 'Oct 1 – Oct 24, 2026');
    expect(range.prompt, 'Explain this Oct 1 – Oct 24, 2026 range');

    final metric = AskPrefills.chartRange(metric: 'MRR', range: 'Last 30 days');
    expect(metric.kind, AskContextKind.metric);
    expect(metric.label, 'MRR · Last 30 days');
    expect(metric.prompt, 'Explain MRR over Last 30 days');
  });

  test('payout and sale carry labels for the chip', () {
    expect(AskPrefills.payout().kind, AskContextKind.payout);
    expect(AskPrefills.payout().label, 'Next payout');
    expect(AskPrefills.payout().prompt, contains('payout'));

    expect(AskPrefills.sale().kind, AskContextKind.sale);
    expect(AskPrefills.sale().label, 'Sale');
    expect(AskPrefills.sale().prompt, contains('sale'));
  });

  test('a transaction carries its sale id and type', () {
    const tx = RcTransaction(
      wasRefunded: true,
      storeTransactionIdentifier: '2000001',
    );
    final attached = AskPrefills.transaction(tx);
    expect(attached.kind, AskContextKind.sale);
    expect(attached.label, 'Sale');
    expect(attached.prompt, contains('Refunded'));
    expect(attached.transactionId, '2000001');

    expect(AskPrefills.transaction(null).prompt, AskPrefills.sale().prompt);
  });
}
