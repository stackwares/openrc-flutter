import 'package:openrc/core/utils/store_commission.dart';
import 'package:openrc/core/utils/store_payday_schedule.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/commission_settings_store.dart';

/// Estimated net proceeds from loaded transactions that fall in each
/// platform’s **next** payout accrual window, always after the configured
/// store-fee rates (payouts are net of fees whatever the display setting).
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
/// - the start of the current local calendar month (Revenue tab MTD), and
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

NextPaydayProceedsEstimate computeNextPaydayProceedsEstimate(
  Iterable<RcTransaction> transactions,
  CommissionSettings commission,
) {
  final apple = AppStorePayday.upcoming;
  final google = GooglePlayPayday.upcoming;
  var appleSum = 0.0;
  var googleSum = 0.0;

  // Reduced once, not per row: these bounds are checked against the whole
  // loaded feed and building a local DateTime costs more than the test.
  final appleStart = apple == null ? null : localCalendarDay(apple.startDate);
  final appleEnd = apple == null ? null : localCalendarDay(apple.endDate);
  final googleStart = google == null
      ? null
      : localCalendarDay(google.earningsStart);
  final googleEnd = google == null
      ? null
      : localCalendarDay(google.earningsEnd);

  // Stores always keep their fee before paying out, so apply the configured
  // rates even when revenue elsewhere is shown before fees.
  final fees = commission.copyWith(adjustmentEnabled: true);
  // The accrual windows cover days, the feed covers months: pick the rows
  // first and net only those, instead of classifying and adjusting every
  // loaded transaction to throw most of it away.
  for (final tx in transactions) {
    final store = classifyStore(tx.storeForCommission);
    if (store == StoreCommissionPlatform.apple) {
      if (appleStart == null || appleEnd == null) continue;
      if (!localPurchaseDayInDayRange(tx, appleStart, appleEnd)) continue;
      appleSum += adjustUsdForDisplay(
        gross: tx.revenue ?? 0,
        settings: fees,
        store: tx.storeForCommission,
      );
    } else if (store == StoreCommissionPlatform.google) {
      if (googleStart == null || googleEnd == null) continue;
      if (!localPurchaseDayInDayRange(tx, googleStart, googleEnd)) continue;
      googleSum += adjustUsdForDisplay(
        gross: tx.revenue ?? 0,
        settings: fees,
        store: tx.storeForCommission,
      );
    }
  }

  return NextPaydayProceedsEstimate(
    applePayday: apple,
    appleNetUsd: appleSum,
    googlePayday: google,
    googleNetUsd: googleSum,
  );
}
