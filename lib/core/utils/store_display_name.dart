import 'package:easy_localization/easy_localization.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/features/transactions/transactions_common.dart';

/// Localized label for RevenueCat store strings (`App Store`, `Play Store`, …).
String revenueCatStoreDisplayName(String store) {
  final s = store.trim();
  return switch (s) {
    'App Store' || 'Mac App Store' => 'storeNames.appStore'.tr(),
    'Play Store' || 'Google Play' => 'storeNames.googlePlay'.tr(),
    'Stripe' => 'storeNames.stripe'.tr(),
    _ => s,
  };
}

String transactionPlatformFilterLabel(TransactionPlatformFilter platform) =>
    switch (platform) {
      TransactionPlatformFilter.apple => 'storeNames.appStore'.tr(),
      TransactionPlatformFilter.google => 'storeNames.googlePlay'.tr(),
      TransactionPlatformFilter.web => 'transactions.web'.tr(),
    };

String transactionDaySummaryPlatformLabel(
  TransactionDaySummaryPlatform platform,
) =>
    switch (platform) {
      TransactionDaySummaryPlatform.apple => 'storeNames.appStore'.tr(),
      TransactionDaySummaryPlatform.google => 'storeNames.googlePlay'.tr(),
      TransactionDaySummaryPlatform.web => 'transactions.web'.tr(),
      TransactionDaySummaryPlatform.other => 'transactions.other'.tr(),
    };

extension PayoutStoreDisplay on PayoutStore {
  String get displayLabel => switch (this) {
        PayoutStore.apple => 'storeNames.appStore'.tr(),
        PayoutStore.google => 'storeNames.googlePlay'.tr(),
      };
}
