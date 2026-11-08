import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/utils/app_identity.dart';
import 'package:openrc/core/utils/region_display_name.dart';
import 'package:openrc/core/utils/store_display_name.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/features/upcoming/upcoming_provider.dart';
import 'package:openrc/models/product_labels.dart';
import 'package:openrc/models/rc_transaction.dart';

/// Most rows a search lists; the rest are counted but not built.
const kSearchMaxResults = 200;

/// Every transaction the app holds right now: each loaded day on Home
/// (today's run back plus days jumped to) and the look-back windows loaded
/// for Upcoming, without duplicates.
final searchPoolProvider = Provider<List<RcTransaction>>((ref) {
  final days = ref.watch(transactionsProvider).dayView;
  final upcoming = ref.watch(upcomingTransactionsProvider).transactions;
  final seen = <String>{};
  final out = <RcTransaction>[];
  void add(RcTransaction tx) {
    if (seen.add(searchDedupeKey(tx))) out.add(tx);
  }

  for (final list in days.values) {
    list.forEach(add);
  }
  upcoming.forEach(add);
  return out;
});

/// One key per sale: the store's transaction id within its project, or the
/// customer, product and time when the store id is missing.
String searchDedupeKey(RcTransaction tx) {
  final id = tx.storeTransactionIdentifier?.trim();
  if (id != null && id.isNotEmpty) return '${tx.app?.id}|$id';
  return '${tx.app?.id}|${tx.subscriberId}|${tx.productIdentifier}|'
      '${tx.purchaseDate}';
}

/// What a search found: the first [kSearchMaxResults] matches, best first,
/// and how many matched in all.
class TransactionSearchResult {
  const TransactionSearchResult(this.matches, this.total);

  static const empty = TransactionSearchResult([], 0);

  final List<RcTransaction> matches;
  final int total;
}

/// Matches [query] against the store transaction id, customer id, product id
/// and the name Settings gave it, project, store and country. Every word of
/// the query has to match (in any field), ignoring case.
///
/// An exact transaction or customer id comes first, then ids that start with
/// the query, then everything else; newest first within each.
TransactionSearchResult searchTransactions(
  Iterable<RcTransaction> pool,
  String query, {
  ProductLabels labels = const ProductLabels.empty(),
  int limit = kSearchMaxResults,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return TransactionSearchResult.empty;
  final words = q.split(RegExp(r'\s+'));

  final scored = <(int, DateTime?, RcTransaction)>[];
  for (final tx in pool) {
    final haystack = _haystack(tx, labels);
    if (!words.every(haystack.contains)) continue;
    scored.add((_rank(tx, q), DateTime.tryParse(tx.purchaseDate ?? ''), tx));
  }
  scored.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    if (byRank != 0) return byRank;
    final at = a.$2, bt = b.$2;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return TransactionSearchResult([
    for (final s in scored.take(limit)) s.$3,
  ], scored.length);
}

int _rank(RcTransaction tx, String q) {
  final ids = [
    tx.storeTransactionIdentifier?.toLowerCase(),
    tx.subscriberId?.toLowerCase(),
  ];
  if (ids.contains(q)) return 0;
  if (ids.any((id) => id != null && id.startsWith(q))) return 1;
  return 2;
}

String _haystack(RcTransaction tx, ProductLabels labels) {
  final country = tx.subscriberCountryCode;
  final store = tx.store;
  return [
    tx.storeTransactionIdentifier,
    tx.subscriberId,
    tx.productIdentifier,
    labels.displayName(productLabelAppKey(tx), tx.productIdentifier),
    labels.planName(productLabelAppKey(tx), tx.productIdentifier),
    tx.app?.name,
    tx.app?.id,
    store,
    if (store != null) revenueCatStoreDisplayName(store),
    country,
    if (country != null) regionDisplayNameEnglish(country),
  ].whereType<String>().join('\n').toLowerCase();
}

/// Whether [query] could be a customer id worth looking up on RevenueCat:
/// one word, at least three characters.
bool canLookUpCustomer(String query) {
  final q = query.trim();
  return q.length >= 3 && !q.contains(RegExp(r'\s'));
}

/// The newest loaded transaction of customer [subscriberId] in [projectId].
RcTransaction? newestLoadedForCustomer(
  Iterable<RcTransaction> pool, {
  required String projectId,
  required String subscriberId,
}) {
  RcTransaction? best;
  DateTime? bestAt;
  for (final tx in pool) {
    if (tx.app?.id != projectId || tx.subscriberId != subscriberId) continue;
    final at = DateTime.tryParse(tx.purchaseDate ?? '');
    if (best == null ||
        (at != null && (bestAt == null || at.isAfter(bestAt)))) {
      best = tx;
      bestAt = at;
    }
  }
  return best;
}
