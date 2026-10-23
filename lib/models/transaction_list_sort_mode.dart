import 'package:easy_localization/easy_localization.dart';

/// User preference for ordering transaction rows (day list, Revenue section drill-in).
enum TransactionListSortMode {
  purchaseNewestFirst,
  purchaseOldestFirst,
  revenueHighToLow,
  revenueLowToHigh,
}

extension TransactionListSortModeX on TransactionListSortMode {
  String get menuLabel => switch (this) {
    TransactionListSortMode.purchaseNewestFirst => 'transactions.sortPurchaseNewest'.tr(),
    TransactionListSortMode.purchaseOldestFirst => 'transactions.sortPurchaseOldest'.tr(),
    TransactionListSortMode.revenueHighToLow => 'transactions.sortAmountHighToLow'.tr(),
    TransactionListSortMode.revenueLowToHigh => 'transactions.sortAmountLowToHigh'.tr(),
  };

  /// Short label for the list header button.
  String get shortLabel => switch (this) {
    TransactionListSortMode.purchaseNewestFirst => 'transactions.sortNewest'.tr(),
    TransactionListSortMode.purchaseOldestFirst => 'transactions.sortOldest'.tr(),
    TransactionListSortMode.revenueHighToLow => 'transactions.sortHighest'.tr(),
    TransactionListSortMode.revenueLowToHigh => 'transactions.sortLowest'.tr(),
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
