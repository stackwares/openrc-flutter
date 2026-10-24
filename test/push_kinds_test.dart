import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/services/push/push_kinds.dart';

void main() {
  test('every kind is in the notifier\'s list, by the same id', () {
    // notifier/src/copy.ts, KINDS.
    expect(PushKind.values.map((k) => k.id), [
      'new',
      'trial',
      'conversion',
      'renewal',
      'purchase',
      'resubscribe',
      'cancel',
      'refund',
      'billing',
      'expire',
      'change',
    ]);
  });

  test('asks RevenueCat only for the events the kinds need', () {
    expect(PushKind.eventTypesFor({PushKind.trial}), ['INITIAL_PURCHASE']);
    expect(PushKind.eventTypesFor({PushKind.trial, PushKind.newSubscription}), [
      'INITIAL_PURCHASE',
    ]);
    expect(PushKind.eventTypesFor({PushKind.refund}), [
      'CANCELLATION',
      'REFUND_REVERSED',
    ]);
    expect(
      PushKind.eventTypesFor(PushKind.all),
      isNot(contains('PAYWALL_IMPRESSION')),
    );
  });

  test('names chosen kinds in the URL, and nothing for all', () {
    expect(PushKind.queryFor(PushKind.all), isNull);
    expect(
      PushKind.queryFor({PushKind.renewal, PushKind.trial}),
      'trial,renewal',
    );
    expect(PushKind.fromIds(['trial', 'bogus']), {PushKind.trial});
  });
}
