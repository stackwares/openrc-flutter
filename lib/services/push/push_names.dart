import 'package:flutter/foundation.dart';
import 'package:openrc/models/product_labels.dart';

/// The product names Settings gave, as the notifier reads them from the
/// device's own webhook URL (`notifier/src/display.ts`).
///
/// A push is written by the notifier, which only has the webhook body: the
/// store's product id, never a name. The names therefore travel on the URL,
/// as `names=<id>\n<name>\t<id>\n<name>` percent-encoded. Every device has
/// its own webhook, so each device's notifications read its own names, and
/// they stay inside the RevenueCat account of whoever set them.
class PushNames {
  /// Nothing named: pushes use the store's product id.
  const PushNames.empty() : _byId = const {};

  /// [byId], cleaned the way a push shows it: one line per name, no control
  /// characters (the URL's own separators among them), and short enough for
  /// a notification row.
  PushNames(Map<String, String> byId) : _byId = _cleanAll(byId);

  /// The query parameter the notifier reads.
  static const key = 'names';

  /// Longest name a push shows; longer labels are cut.
  static const _maxName = 60;

  /// Longest product id worth carrying, matching what the notifier reads.
  static const _maxId = 200;

  /// The encoded entries stop here, so the webhook URL stays well inside
  /// what RevenueCat and Cloudflare accept. Names past it fall back to the
  /// product id, which is what notifications showed before.
  static const _maxEncoded = 1800;

  /// Names by store product id.
  final Map<String, String> _byId;

  /// Every name on the account, whichever app it belongs to.
  ///
  /// Product ids are the stores' own and don't repeat across an account's
  /// apps, so one map covers them all. Sorted, so the URL is stable: two
  /// builds with the same names make the same one. A product id two apps
  /// named differently keeps the first app's name.
  factory PushNames.of(ProductLabels labels) {
    final byId = <String, String>{};
    final appKeys = labels.apps.keys.toList()..sort();
    for (final appKey in appKeys) {
      final app = labels.forApp(appKey);
      for (final id in app.products.keys.toList()..sort()) {
        final name = app.products[id]?.name;
        if (name == null) continue;
        byId.putIfAbsent(id, () => name);
      }
    }
    return PushNames(byId);
  }

  bool get isEmpty => _byId.isEmpty;

  /// How many products are named.
  int get count => _byId.length;

  /// The name to show for [productId], when the developer gave one.
  String? nameOf(String? productId) {
    final id = productId?.trim();
    if (id == null || id.isEmpty) return null;
    return _byId[id];
  }

  bool sameAs(PushNames other) => mapEquals(_byId, other._byId);

  /// What the notifier reads, or null when nothing is named.
  String? get encoded {
    if (_byId.isEmpty) return null;
    final ids = _byId.keys.toList()..sort();
    final parts = <String>[];
    var length = 0;
    for (final id in ids) {
      if (id.length > _maxId) continue;
      final entry = Uri.encodeQueryComponent('$id\n${_byId[id]}');
      // A tab between entries, encoded.
      final grew = entry.length + (parts.isEmpty ? 0 : 3);
      if (length + grew > _maxEncoded) break;
      length += grew;
      parts.add(entry);
    }
    if (parts.isEmpty) return null;
    return parts.join('%09');
  }

  /// The query parameters a webhook URL carries for these names.
  Map<String, String> get query => {key: ?encoded};

  Map<String, Object?> toJson() => {'names': _byId};

  factory PushNames.fromJson(Object? json) {
    if (json is! Map) return const PushNames.empty();
    final raw = json['names'];
    if (raw is! Map) return const PushNames.empty();
    return PushNames({
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          (entry.key as String).trim(): entry.value as String,
    });
  }

  /// [byId] cleaned, blanks dropped, and two ids that clean alike kept apart.
  static Map<String, String> _cleanAll(Map<String, String> byId) {
    final cleaned = <String, String>{};
    for (final entry in byId.entries) {
      final id = entry.key.trim();
      final name = _cleanName(entry.value);
      if (id.isEmpty || name == null) continue;
      cleaned.putIfAbsent(id, () => name);
    }
    return cleaned;
  }

  /// What a push can show: one line, no control characters (the URL's own
  /// separators among them), and not longer than a notification row.
  static String? _cleanName(Object? value) {
    if (value is! String) return null;
    final cleaned = value
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return null;
    if (cleaned.length <= _maxName) return cleaned;
    return cleaned.substring(0, _maxName).trim();
  }
}
