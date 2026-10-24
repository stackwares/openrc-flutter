import 'package:easy_localization/easy_localization.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/models/rc_transaction.dart';

/// What a jump into Ask is about. The chip above the composer shows [label];
/// the composer starts with [prompt]; tools focus on [transactionId].
class AskContext {
  const AskContext({
    required this.kind,
    required this.label,
    required this.prompt,
    this.transactionId,
  });

  final AskContextKind kind;
  final String label;
  final String prompt;
  final String? transactionId;
}

enum AskContextKind { sale, day, metric, charts, payout }

/// Prefills for jumping to Ask from another screen. The tab stays one thread.
abstract final class AskPrefills {
  static AskContext selectedDay(String dayKey, {DateTime? now}) {
    final day = _dayLabel(dayKey, now: now);
    return AskContext(
      kind: AskContextKind.day,
      label: day,
      prompt: 'agent.context.day'.tr(namedArgs: {'day': day}),
    );
  }

  static AskContext chartRange({String? metric, required String range}) {
    final name = metric?.trim();
    if (name != null && name.isNotEmpty) {
      return AskContext(
        kind: AskContextKind.metric,
        label: '$name · $range',
        prompt: 'agent.context.metric'.tr(
          namedArgs: {'metric': name, 'range': range},
        ),
      );
    }
    return AskContext(
      kind: AskContextKind.charts,
      label: range,
      prompt: 'agent.context.charts'.tr(namedArgs: {'range': range}),
    );
  }

  static AskContext payout() => AskContext(
    kind: AskContextKind.payout,
    label: 'agent.contextLabels.payout'.tr(),
    prompt: 'agent.context.payout'.tr(),
  );

  static AskContext transaction(RcTransaction? tx) {
    if (tx == null) return sale();
    return AskContext(
      kind: AskContextKind.sale,
      label: 'agent.contextLabels.sale'.tr(),
      prompt: 'agent.context.transaction'.tr(
        namedArgs: {'type': _typeLabel(tx)},
      ),
      transactionId: tx.storeTransactionIdentifier,
    );
  }

  static AskContext sale({String? transactionId}) => AskContext(
    kind: AskContextKind.sale,
    label: 'agent.contextLabels.sale'.tr(),
    prompt: 'agent.context.sale'.tr(),
    transactionId: transactionId,
  );

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
