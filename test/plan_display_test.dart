import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/core/utils/plan_display.dart';
import 'package:openrc/models/rc_transaction.dart';

RcTransaction _tx({
  int? days,
  bool trial = false,
  bool intro = false,
  bool sandbox = false,
  String? product = 'com.acme.pro',
}) {
  final start = DateTime.utc(2026, 1, 15, 10);
  return RcTransaction(
    productIdentifier: product,
    purchaseDate: start.toIso8601String(),
    expiresDate: days == null
        ? null
        : start.add(Duration(days: days)).toIso8601String(),
    isTrialPeriod: trial,
    isInIntroductoryPricePeriod: intro,
    isSandbox: sandbox,
  );
}

void main() {
  test('plan length comes from the purchase and expiry dates', () {
    expect(planLengthLabel(_tx(days: 7)), 'Weekly');
    expect(planLengthLabel(_tx(days: 28)), 'Monthly');
    expect(planLengthLabel(_tx(days: 31)), 'Monthly');
    expect(planLengthLabel(_tx(days: 59)), '2 months');
    expect(planLengthLabel(_tx(days: 92)), '3 months');
    expect(planLengthLabel(_tx(days: 181)), '6 months');
    expect(planLengthLabel(_tx(days: 365)), 'Annual');
    expect(planLengthLabel(_tx(days: 366)), 'Annual');
    expect(planLengthLabel(_tx(days: 14)), '14 days');
    expect(planLengthLabel(_tx()), 'One-time');
  });

  test('offers, trials and test purchases don’t claim a plan length', () {
    expect(planLengthLabel(_tx(days: 3, trial: true)), '3-day trial');
    expect(planLengthLabel(_tx(days: 30, intro: true)), 'Intro offer');
    expect(planLengthLabel(_tx(days: 365, sandbox: true)), isNull);
  });

  test('the plan is named by its product id, whatever its naming', () {
    expect(planDescription(_tx(days: 365)), 'com.acme.pro  ·  Annual');
    expect(planDescription(_tx(sandbox: true)), 'com.acme.pro');
    expect(planProductId(_tx(product: null)), 'Unknown');
  });
}
