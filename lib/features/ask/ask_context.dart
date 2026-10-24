import 'package:easy_localization/easy_localization.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/models/rc_transaction.dart';

/// Prefills for jumping to Ask from another screen. The tab stays one thread.
abstract final class AskPrefills {
  static String selectedDay(String dayKey, {DateTime? now}) {
    return 'agent.context.day'.tr(namedArgs: {'day': _dayLabel(dayKey, now: now)});
  }

  static String chartRange({String? metric, required String range}) {
    if (metric != null && metric.trim().isNotEmpty) {
      return 'agent.context.metric'.tr(
        namedArgs: {'metric': metric.trim(), 'range': range},
      );
    }
    return 'agent.context.charts'.tr(namedArgs: {'range': range});
  }

  static String payout() => 'agent.context.payout'.tr();

  static String transaction(RcTransaction? tx) {
    if (tx == null) return sale();
    return 'agent.context.transaction'.tr(
      namedArgs: {'type': _typeLabel(tx)},
    );
  }

  static String sale() => 'agent.context.sale'.tr();

  static String _dayLabel(String dayKey, {DateTime? now}) {
    final today = now == null
        ? localTodayDayKey()
        : DateFormat('yyyy-MM-dd').format(
            DateTime(now.year, now.month, now.day),
          );
    if (dayKey == today) return 'transactions.today'.tr();
    if (dayKey == _shiftDayKey(today, -1)) {
      return 'transactions.yesterday'.tr();
    }
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dayKey);
      final sameYear = date.year == (now ?? DateTime.now()).year;
      return (sameYear ? DateFormat.MMMEd() : DateFormat.yMMMd()).format(date);
    } catch (_) {
      return dayKey;
    }
  }

  static String _shiftDayKey(String dayKey, int days) {
    final parsed = DateTime.tryParse(dayKey);
    if (parsed == null) return dayKey;
    return DateFormat('yyyy-MM-dd').format(
      DateTime(parsed.year, parsed.month, parsed.day).add(Duration(days: days)),
    );
  }

  static String _typeLabel(RcTransaction tx) {
    return switch (tx.type) {
      RcTransactionType.refund => 'transactions.refunded'.tr(),
      RcTransactionType.trial => 'transactions.trial'.tr(),
      RcTransactionType.conversion => 'transactions.converted'.tr(),
      RcTransactionType.renewal => 'transactions.renewed'.tr(),
      RcTransactionType.newSubscription ||
      RcTransactionType.oneTimePurchase => 'transactions.purchased'.tr(),
      RcTransactionType.unknown => 'transactions.other'.tr(),
    };
  }
}
