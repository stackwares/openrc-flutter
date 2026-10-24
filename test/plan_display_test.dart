import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/core/utils/plan_display.dart';
import 'package:openrc/models/product_labels.dart';
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

  test('a saved name replaces the id and leaves the id reachable', () {
    const labels = ProductLabels(
      apps: {
        'app1': AppProductLabels(
          products: {'com.acme.pro': ProductLabel(name: 'Pro', planId: 'pro')},
          plans: {'pro': ProductPlan(id: 'pro', name: 'Pro')},
        ),
      },
    );
    final tx = RcTransaction(
      app: const RcTransactionApp(id: 'app1', name: 'Acme'),
      productIdentifier: 'com.acme.pro',
      purchaseDate: DateTime.utc(2026, 1, 15, 10).toIso8601String(),
      expiresDate: DateTime.utc(2027, 1, 15, 10).toIso8601String(),
    );

    expect(planProductId(tx, labels: labels), 'Pro');
    expect(planDescription(tx, labels: labels), 'Pro  ·  Annual');
    expect(planFamilyName(tx, labels: labels), 'Pro');
    expect(rawProductId(tx), 'com.acme.pro');
  });

  test('a name that already is the period is not repeated', () {
    const labels = ProductLabels(
      apps: {
        'app1': AppProductLabels(
          products: {
            'com.acme.pro_monthly': ProductLabel(name: 'Monthly'),
            'com.acme.annual': ProductLabel(name: 'Yearly'),
            'com.acme.life': ProductLabel(name: 'Lifetime'),
          },
        ),
      },
    );
    RcTransaction tx(String product, {int? days}) => RcTransaction(
      app: const RcTransactionApp(id: 'app1'),
      productIdentifier: product,
      purchaseDate: DateTime.utc(2026, 1, 15, 10).toIso8601String(),
      expiresDate: days == null
          ? null
          : DateTime.utc(2026, 1, 15, 10)
                .add(Duration(days: days))
                .toIso8601String(),
    );

    // The product id itself names a month, and so does the name.
    expect(
      planDescription(tx('com.acme.pro_monthly', days: 30), labels: labels),
      'Monthly',
    );
    // The id says annual, the app calls it Yearly, the dates say Annual.
    expect(
      planDescription(tx('com.acme.annual', days: 365), labels: labels),
      'Yearly',
    );
    // A one-time purchase reads Lifetime, not "Lifetime · One-time".
    expect(planDescription(tx('com.acme.life'), labels: labels), 'Lifetime');
  });

  test('a real name keeps the period beside it', () {
    const labels = ProductLabels(
      apps: {
        'app1': AppProductLabels(
          products: {'com.acme.pro_monthly': ProductLabel(name: 'Pro')},
        ),
      },
    );
    final tx = RcTransaction(
      app: const RcTransactionApp(id: 'app1'),
      productIdentifier: 'com.acme.pro_monthly',
      purchaseDate: DateTime.utc(2026, 1, 15, 10).toIso8601String(),
      expiresDate: DateTime.utc(2026, 2, 14, 10).toIso8601String(),
    );
    expect(planDescription(tx, labels: labels), 'Pro  ·  Monthly');
  });

  test('a trial keeps its own label', () {
    const labels = ProductLabels(
      apps: {
        'app1': AppProductLabels(
          products: {'com.acme.pro_monthly': ProductLabel(name: 'Monthly')},
        ),
      },
    );
    final tx = RcTransaction(
      app: const RcTransactionApp(id: 'app1'),
      productIdentifier: 'com.acme.pro_monthly',
      isTrialPeriod: true,
      purchaseDate: DateTime.utc(2026, 1, 15, 10).toIso8601String(),
      expiresDate: DateTime.utc(2026, 1, 18, 10).toIso8601String(),
    );
    expect(
      planDescription(tx, labels: labels),
      'Monthly  ·  3-day trial',
    );
  });

  test('names are per app', () {
    const labels = ProductLabels(
      apps: {
        'app1': AppProductLabels(products: {'pro': ProductLabel(name: 'Pro')}),
      },
    );
    const other = RcTransaction(
      app: RcTransactionApp(id: 'app2'),
      productIdentifier: 'pro',
    );
    expect(planProductId(other, labels: labels), 'pro');
  });
}
