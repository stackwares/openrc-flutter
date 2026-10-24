import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';
import 'package:openrc/models/product_labels.dart';
import 'package:openrc/services/push/push_names.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Names the developer gave to store product ids, per app, kept on this
/// device only. They change what the app shows, and travel on this device's
/// own webhook URL so notifications read the same ([PushNames]).
final productLabelsProvider =
    StateNotifierProvider<ProductLabelsNotifier, ProductLabels>((ref) {
      return ProductLabelsNotifier(
        onChanged: (labels) => unawaited(
          ref.read(pushSettingsProvider.notifier).setNames(PushNames.of(labels)),
        ),
      );
    });

/// One product's new label, from the editor or a suggestion.
class ProductLabelUpdate {
  const ProductLabelUpdate({this.name, this.planName});

  /// New display name; null or blank clears it.
  final String? name;

  /// Plan family name; null leaves the current plan, blank clears it.
  final String? planName;
}

class ProductLabelsNotifier extends StateNotifier<ProductLabels> {
  ProductLabelsNotifier({this.onChanged}) : super(const ProductLabels.empty()) {
    _ready = _hydrate();
  }

  /// Hears every change, including the one hydration makes, so whatever
  /// follows the names (notifications) starts from the saved ones.
  final void Function(ProductLabels labels)? onChanged;

  static const _prefsKey = 'product_labels_v1';

  late final Future<void> _ready;

  /// Completes once the saved labels are loaded.
  Future<void> get ready => _ready;

  ProductLabels? _undo;

  /// True when the last change can be taken back.
  bool get canUndo => _undo != null;

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        state = ProductLabels.fromJson(jsonDecode(raw));
      } catch (_) {
        // Corrupt or older payload: start clean rather than lose the screen.
      }
    }
    onChanged?.call(state);
  }

  Future<void> _commit(ProductLabels next) async {
    if (next == state) return;
    _undo = state;
    state = next;
    onChanged?.call(state);
    final prefs = await SharedPreferences.getInstance();
    if (next.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(next.toJson()));
    }
  }

  /// Takes back the last change (one level, e.g. a whole AI run).
  Future<void> undo() async {
    await ready;
    final previous = _undo;
    if (previous == null) return;
    _undo = null;
    state = previous;
    onChanged?.call(state);
    final prefs = await SharedPreferences.getInstance();
    if (previous.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(previous.toJson()));
    }
  }

  /// Sets or clears a product's display name in one app.
  Future<void> setName(String appKey, String productId, String? name) async {
    await applyUpdates(appKey, {productId: ProductLabelUpdate(name: name)});
  }

  /// Puts a product in a plan family (creating it when new), or clears it
  /// when [planName] is null or blank.
  Future<void> setPlan(
    String appKey,
    String productId,
    String? planName,
  ) async {
    await applyUpdates(appKey, {
      productId: ProductLabelUpdate(planName: planName ?? ''),
    });
  }

  Future<void> applyUpdates(
    String appKey,
    Map<String, ProductLabelUpdate> updates,
  ) => applyAll({appKey: updates});

  /// Applies labels for any number of apps as one change, so [undo] takes
  /// back a whole AI run rather than its last app.
  Future<void> applyAll(
    Map<String, Map<String, ProductLabelUpdate>> updatesByApp,
  ) async {
    await ready;
    var next = state;
    for (final entry in updatesByApp.entries) {
      if (entry.value.isEmpty) continue;
      next = _apply(next, entry.key, entry.value);
    }
    await _commit(next);
  }

  static ProductLabels _apply(
    ProductLabels base,
    String appKey,
    Map<String, ProductLabelUpdate> updates,
  ) {
    final app = base.forApp(appKey);
    final products = Map<String, ProductLabel>.from(app.products);
    final plans = Map<String, ProductPlan>.from(app.plans);

    for (final entry in updates.entries) {
      final current = products[entry.key] ?? const ProductLabel();
      var label = current;
      final update = entry.value;

      if (update.name != null) {
        final name = update.name!.trim();
        label = ProductLabel(
          name: name.isEmpty ? null : name,
          planId: label.planId,
        );
      }
      if (update.planName != null) {
        final planName = update.planName!.trim();
        if (planName.isEmpty) {
          label = ProductLabel(name: label.name);
        } else {
          final planId = _planIdFor(plans, planName);
          plans[planId] =
              plans[planId] ?? ProductPlan(id: planId, name: planName);
          label = ProductLabel(name: label.name, planId: planId);
        }
      }
      if (label.isEmpty) {
        products.remove(entry.key);
      } else {
        products[entry.key] = label;
      }
    }

    return base.withApp(
      appKey,
      AppProductLabels(products: products, plans: plans),
    );
  }

  /// Renames a plan family; every product in it follows.
  Future<void> renamePlan(String appKey, String planId, String name) async {
    await ready;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final app = state.forApp(appKey);
    final existing = app.plans[planId];
    if (existing == null || existing.name == trimmed) return;
    final plans = Map<String, ProductPlan>.from(app.plans);
    plans[planId] = ProductPlan(id: planId, name: trimmed);
    await _commit(
      state.withApp(
        appKey,
        AppProductLabels(products: app.products, plans: plans),
      ),
    );
  }

  /// Removes a plan family and takes its products out of it.
  Future<void> deletePlan(String appKey, String planId) async {
    await ready;
    final app = state.forApp(appKey);
    if (!app.plans.containsKey(planId)) return;
    final plans = Map<String, ProductPlan>.from(app.plans)..remove(planId);
    final products = <String, ProductLabel>{
      for (final e in app.products.entries)
        e.key: e.value.planId == planId
            ? ProductLabel(name: e.value.name)
            : e.value,
    }..removeWhere((_, label) => label.isEmpty);
    await _commit(
      state.withApp(appKey, AppProductLabels(products: products, plans: plans)),
    );
  }

  /// Forgets every label and plan in one app.
  Future<void> clearApp(String appKey) async {
    await ready;
    if (state.forApp(appKey).isEmpty) return;
    await _commit(state.withApp(appKey, const AppProductLabels()));
  }

  /// The id of an existing plan named [name] (ignoring case), else a new
  /// unique slug for it.
  static String _planIdFor(Map<String, ProductPlan> plans, String name) {
    final wanted = name.toLowerCase();
    for (final plan in plans.values) {
      if (plan.name.toLowerCase() == wanted) return plan.id;
    }
    final base = productPlanSlug(name);
    if (!plans.containsKey(base)) return base;
    for (var i = 2; ; i++) {
      final candidate = '$base-$i';
      if (!plans.containsKey(candidate)) return candidate;
    }
  }
}
