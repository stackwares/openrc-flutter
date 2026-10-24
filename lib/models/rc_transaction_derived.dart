import 'package:openrc/models/rc_transaction.dart';

/// Values parsed from a transaction's immutable fields, parsed once per row.
///
/// The dashboard re-walks every loaded transaction several times for a single
/// frame — the day list, the month window, the next-payout estimate and the
/// tenure maps each go over the loaded feed — and parsing an ISO-8601
/// timestamp (`DateTime.tryParse` plus the `toLocal` time zone lookup) is the
/// most expensive part of that walk. [RcTransaction] keeps its `const`
/// constructor, so the caches live here instead: one entry per row, held
/// weakly, so a dropped row takes its parsed values with it.
///
/// Everything cached here depends only on final fields, so a cached value can
/// never go stale.
extension RcTransactionDerived on RcTransaction {
  /// [purchaseDate] as the local calendar day (midnight), or null when the
  /// timestamp is missing or can't be parsed.
  DateTime? get purchaseLocalDay {
    final hit = _localPurchaseDay[this];
    if (hit != null) return hit.value;
    final value = _parseLocal(purchaseDate, calendarDay: true);
    _localPurchaseDay[this] = _Box(value);
    return value;
  }

  /// [purchaseDate] as a local instant, for same-day "Xs ago" math.
  DateTime? get purchaseLocalInstant {
    final hit = _localPurchaseInstant[this];
    if (hit != null) return hit.value;
    final value = _parseLocal(purchaseDate);
    _localPurchaseInstant[this] = _Box(value);
    return value;
  }

  /// [expiresDate] as a local instant.
  DateTime? get expiresLocalInstant {
    final hit = _localExpiresInstant[this];
    if (hit != null) return hit.value;
    final value = _parseLocal(expiresDate);
    _localExpiresInstant[this] = _Box(value);
    return value;
  }

  /// Stable key for merging paginated `/me/transactions` responses
  /// (Kedi-style dedupe): the store transaction id, else a
  /// subscriber + product + purchase date composite.
  ///
  /// Built once per row: every merge, every pass that flattens the feed and
  /// every list row key asks for it again.
  String? get mergeKey {
    final hit = _mergeKey[this];
    if (hit != null) return hit.value;
    final value = _buildMergeKey(this);
    _mergeKey[this] = _Box(value);
    return value;
  }
}

/// Holds a possibly-null value so an [Expando] can memoize it.
class _Box<T> {
  const _Box(this.value);

  final T value;
}

final _localPurchaseDay = Expando<_Box<DateTime?>>('rc.purchaseLocalDay');
final _localPurchaseInstant = Expando<_Box<DateTime?>>(
  'rc.purchaseLocalInstant',
);
final _localExpiresInstant = Expando<_Box<DateTime?>>('rc.expiresLocalInstant');
final _mergeKey = Expando<_Box<String?>>('rc.mergeKey');

String? _buildMergeKey(RcTransaction tx) {
  final stid = tx.storeTransactionIdentifier?.trim();
  if (stid != null && stid.isNotEmpty) return 'stid:$stid';
  final sub = tx.subscriberId?.trim();
  final prod = tx.productIdentifier?.trim();
  final pd = tx.purchaseDate?.trim();
  if (sub != null &&
      sub.isNotEmpty &&
      prod != null &&
      prod.isNotEmpty &&
      pd != null &&
      pd.isNotEmpty) {
    return 'cmp:$sub|$prod|$pd';
  }
  return null;
}

DateTime? _parseLocal(String? iso, {bool calendarDay = false}) {
  final raw = iso?.trim();
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  final local = parsed.toLocal();
  if (!calendarDay) return local;
  return DateTime(local.year, local.month, local.day);
}
