import 'package:revenuecat/core/utils/store_commission.dart';
import 'package:revenuecat/core/utils/store_payday_schedule.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/commission_settings_store.dart';

/// Estimated net proceeds (after [CommissionSettings] store-fee rules) from loaded
/// transactions that fall in each platform’s **next** payout accrual window.
class NextPaydayProceedsEstimate {
  final AppStorePayday? applePayday;
  final double appleNetUsd;
  final GooglePlayPayday? googlePayday;
  final double googleNetUsd;

  const NextPaydayProceedsEstimate({
    required this.applePayday,
    required this.appleNetUsd,
    required this.googlePayday,
    required this.googleNetUsd,
  });
}

/// True when newest-first pagination has gone past:
/// - the start of the current local calendar month (Realtime MTD), and
/// - the start of [AppStorePayday.upcoming]'s accrual window (Apple next-payout sum).
///
/// [grouped] is the merged `/me/transactions` map; [oldestPurchaseLocalCalendarDay]
/// must be strictly before each boundary to include all in-window days.
bool realtimeTabPreloadBoundaryReached(
  Map<String, List<RcTransaction>> grouped,
) {
  final oldest = oldestPurchaseLocalCalendarDay(grouped);
  if (oldest == null) return true;

  final monthStart = localStartOfCurrentMonth();
  if (!oldest.isBefore(monthStart)) return false;

  final apple = AppStorePayday.upcoming;
  if (apple != null) {
    final accrualStart = DateTime(
      apple.startDate.year,
      apple.startDate.month,
      apple.startDate.day,
    );
    if (!oldest.isBefore(accrualStart)) return false;
  }
  return true;
}

bool _localPurchaseDayInInclusiveRange(
  RcTransaction tx,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final pd = tx.purchaseDate?.trim();
  if (pd == null || pd.isEmpty) return false;
  final parsed = DateTime.tryParse(pd);
  if (parsed == null) return false;
  final local = parsed.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final s = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  final e = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
  return !day.isBefore(s) && !day.isAfter(e);
}

NextPaydayProceedsEstimate computeNextPaydayProceedsEstimate(
  Iterable<RcTransaction> transactions,
  CommissionSettings commission,
) {
  final apple = AppStorePayday.upcoming;
  final google = GooglePlayPayday.upcoming;
  var appleSum = 0.0;
  var googleSum = 0.0;

  for (final tx in transactions) {
    final gross = tx.revenue ?? 0;
    final net = adjustUsdForDisplay(
      gross: gross,
      settings: commission,
      store: tx.storeForCommission,
    );

    switch (classifyStore(tx.storeForCommission)) {
      case StoreCommissionPlatform.apple:
        if (apple != null &&
            _localPurchaseDayInInclusiveRange(tx, apple.startDate, apple.endDate)) {
          appleSum += net;
        }
        break;
      case StoreCommissionPlatform.google:
        if (google != null &&
            _localPurchaseDayInInclusiveRange(
              tx,
              google.earningsStart,
              google.earningsEnd,
            )) {
          googleSum += net;
        }
        break;
      case StoreCommissionPlatform.other:
        break;
    }
  }

  return NextPaydayProceedsEstimate(
    applePayday: apple,
    appleNetUsd: appleSum,
    googlePayday: google,
    googleNetUsd: googleSum,
  );
}
