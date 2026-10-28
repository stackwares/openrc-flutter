import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/utils/app_identity.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/models/rc_transaction.dart';

/// One product id seen in the loaded transactions.
class ProductUsage {
  const ProductUsage({
    required this.appKey,
    required this.appLabel,
    this.appId,
    required this.productId,
    required this.sales,
    this.renews = true,
  });

  final String appKey;
  final String appLabel;

  /// RevenueCat app id, when the transactions carried one.
  final String? appId;
  final String productId;

  /// Transactions in the loaded window that carry this product id.
  final int sales;

  /// False when the loaded rows say this product does not renew and none of
  /// them ever renewed: a non-renewing subscription, or a one-time purchase
  /// of a term. Stays true when the rows say nothing either way.
  final bool renews;

  String get key => '$appKey\u0000$productId';
}

/// Product ids on this account, grouped by app.
class ProductInventory {
  const ProductInventory({
    this.products = const [],
    this.appLabels = const {},
    this.appIds = const {},
  });

  final List<ProductUsage> products;
  final Map<String, String> appLabels;

  /// First RevenueCat app id seen per app key, if any.
  final Map<String, String> appIds;

  bool get isEmpty => products.isEmpty;

  int get appCount => appLabels.length;

  List<ProductUsage> forApp(String appKey) => [
    for (final p in products)
      if (p.appKey == appKey) p,
  ];
}

/// Built from transactions already in memory: no extra API calls, and it
/// works offline. On a fresh account with nothing loaded it is empty.
final productInventoryProvider = Provider<ProductInventory>((ref) {
  final state = ref.watch(transactionsProvider);
  return buildProductInventory(
    flattenGroupedTransactionsDeduped(state.dayView),
  );
});

ProductInventory buildProductInventory(Iterable<RcTransaction> txs) {
  final counts = <String, int>{};
  final productIds = <String, String>{};
  final appKeys = <String, String>{};
  final appLabels = <String, String>{};
  final appIds = <String, String>{};
  // Whether some row renewed, and whether some row said it won't. A
  // subscription that was later cancelled keeps its renewals, so it stays a
  // recurring plan; only rows that never renew at all make a one-off term.
  final renewed = <String>{};
  final stoppedRenewing = <String>{};

  for (final tx in txs) {
    final productId = tx.productIdentifier?.trim();
    if (productId == null || productId.isEmpty) continue;
    final appKey = productLabelAppKey(tx);
    final key = '$appKey\u0000$productId';
    counts.update(key, (v) => v + 1, ifAbsent: () => 1);
    productIds[key] = productId;
    appKeys[key] = appKey;
    if (!appLabels.containsKey(appKey)) {
      appLabels[appKey] = appLabelForTransaction(tx);
    }
    final appId = tx.app?.id?.trim();
    if (appId != null && appId.isNotEmpty) {
      appIds.putIfAbsent(appKey, () => appId);
    }
    // A refund says nothing about whether the product renews.
    if (tx.wasRefunded == true) continue;
    if (tx.isAutoRenewing == true || tx.isRenewal == true) renewed.add(key);
    if (tx.isAutoRenewing == false) stoppedRenewing.add(key);
  }

  final products =
      [
        for (final entry in counts.entries)
          ProductUsage(
            appKey: appKeys[entry.key]!,
            appLabel: appLabels[appKeys[entry.key]!] ?? '',
            appId: appIds[appKeys[entry.key]],
            productId: productIds[entry.key]!,
            sales: entry.value,
            renews: !(stoppedRenewing.contains(entry.key) &&
                !renewed.contains(entry.key)),
          ),
      ]..sort((a, b) {
        final byApp = a.appLabel.toLowerCase().compareTo(
          b.appLabel.toLowerCase(),
        );
        if (byApp != 0) return byApp;
        final bySales = b.sales.compareTo(a.sales);
        if (bySales != 0) return bySales;
        return a.productId.compareTo(b.productId);
      });

  return ProductInventory(
    products: products,
    appLabels: appLabels,
    appIds: appIds,
  );
}
