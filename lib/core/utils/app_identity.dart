import 'package:easy_localization/easy_localization.dart';
import 'package:openrc/models/rc_transaction.dart';

/// Stable key for the app a transaction belongs to: app id, else bundle id,
/// else name, else empty. Product labels and filters group by this.
String appKeyForTransaction(RcTransaction tx) {
  final a = tx.app;
  if (a == null) return '';
  final id = a.id?.trim();
  if (id != null && id.isNotEmpty) return id;
  final bid = a.bundleId?.trim();
  if (bid != null && bid.isNotEmpty) return bid;
  final name = a.name?.trim();
  if (name != null && name.isNotEmpty) return name;
  return '';
}

/// What a transaction's app is called on screen.
String appLabelForTransaction(RcTransaction tx) {
  final a = tx.app;
  if (a == null) return 'transactions.unknownApp'.tr();
  final name = a.name?.trim();
  if (name != null && name.isNotEmpty) return name;
  final bid = a.bundleId?.trim();
  if (bid != null && bid.isNotEmpty) return bid;
  final id = a.id?.trim();
  if (id != null && id.isNotEmpty) return id;
  return 'transactions.unknownApp'.tr();
}

/// Bucket for transactions the API returns without an app.
const kUnknownAppLabelKey = '__unknown';

/// Key for per-app product labels; transactions without an app share one
/// bucket instead of keying labels on an empty string.
String productLabelAppKey(RcTransaction tx) {
  final key = appKeyForTransaction(tx);
  return key.isEmpty ? kUnknownAppLabelKey : key;
}
