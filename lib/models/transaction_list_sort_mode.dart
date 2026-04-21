/// User preference for ordering transaction rows (day list, Revenue section drill-in).
enum TransactionListSortMode {
  purchaseNewestFirst,
  purchaseOldestFirst,
  revenueHighToLow,
  revenueLowToHigh,
}

extension TransactionListSortModeX on TransactionListSortMode {
  String get menuLabel => switch (this) {
    TransactionListSortMode.purchaseNewestFirst => 'Purchase time · newest first',
    TransactionListSortMode.purchaseOldestFirst => 'Purchase time · oldest first',
    TransactionListSortMode.revenueHighToLow => 'Amount · high to low',
    TransactionListSortMode.revenueLowToHigh => 'Amount · low to high',
  };
}

TransactionListSortMode transactionListSortModeFromStorage(String? raw) {
  if (raw == null || raw.isEmpty) {
    return TransactionListSortMode.purchaseNewestFirst;
  }
  for (final v in TransactionListSortMode.values) {
    if (v.name == raw) return v;
  }
  return TransactionListSortMode.purchaseNewestFirst;
}
