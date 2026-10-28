import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/settings/product_inventory.dart';
import 'package:openrc/models/rc_transaction.dart';

const _app = RcTransactionApp(id: 'app1', name: 'Acme');

RcTransaction _tx(
  String productId, {
  bool? autoRenews,
  bool? isRenewal,
  bool? wasRefunded,
}) => RcTransaction(
  app: _app,
  productIdentifier: productId,
  store: 'App Store',
  isAutoRenewing: autoRenews,
  isRenewal: isRenewal,
  wasRefunded: wasRefunded,
);

ProductUsage _usage(ProductInventory inventory, String productId) =>
    inventory.products.firstWhere((p) => p.productId == productId);

void main() {
  test('a product whose sales never renew is a one-off term', () {
    final inventory = buildProductInventory([
      _tx('com.acme.pass_yearly', autoRenews: false),
      _tx('com.acme.pass_monthly', autoRenews: false),
    ]);

    expect(_usage(inventory, 'com.acme.pass_yearly').renews, isFalse);
    expect(_usage(inventory, 'com.acme.pass_monthly').renews, isFalse);
  });

  test('a subscription renews even if a later row says it stopped', () {
    // The user cancelled: the subscription itself is still a recurring plan.
    final inventory = buildProductInventory([
      _tx('com.acme.pro_monthly', autoRenews: true, isRenewal: true),
      _tx('com.acme.pro_monthly', autoRenews: false),
    ]);

    expect(_usage(inventory, 'com.acme.pro_monthly').renews, isTrue);
  });

  test('a first purchase that renews nothing yet is still a subscription', () {
    final inventory = buildProductInventory([
      _tx('com.acme.pro_yearly', autoRenews: true),
    ]);

    expect(_usage(inventory, 'com.acme.pro_yearly').renews, isTrue);
  });

  test('rows that say nothing keep the product renewing', () {
    final inventory = buildProductInventory([
      _tx('com.acme.pro_yearly'),
      _tx('com.acme.pro_monthly'),
    ]);

    expect(_usage(inventory, 'com.acme.pro_yearly').renews, isTrue);
  });

  test('a refund does not decide either way', () {
    final inventory = buildProductInventory([
      _tx('com.acme.pass_yearly', autoRenews: false),
      _tx('com.acme.pass_yearly', wasRefunded: true),
    ]);
    expect(_usage(inventory, 'com.acme.pass_yearly').renews, isFalse);

    final unknown = buildProductInventory([
      _tx('com.acme.pass_yearly'),
      _tx('com.acme.pass_yearly', wasRefunded: true, autoRenews: false),
    ]);
    // The only row that spoke was a refund, so nothing is known.
    expect(_usage(unknown, 'com.acme.pass_yearly').renews, isTrue);
  });

  test('renewal evidence is per product, not per app', () {
    final inventory = buildProductInventory([
      _tx('com.acme.pro_monthly', autoRenews: true),
      _tx('com.acme.pass_yearly', autoRenews: false),
    ]);

    expect(_usage(inventory, 'com.acme.pro_monthly').renews, isTrue);
    expect(_usage(inventory, 'com.acme.pass_yearly').renews, isFalse);
  });
}
