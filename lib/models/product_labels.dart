/// Product names a developer gave to store product ids, per app.
///
/// RevenueCat product ids are technical (`com.acme.pro.sub.annual.false`).
/// These labels are chosen on the device, never stored on a server, and only
/// change what the app shows: amounts, dates and counts are unaffected.
library;

/// A plan family inside one app, e.g. `pro` → "Pro", so a monthly and an
/// annual product can be counted as one plan.
class ProductPlan {
  const ProductPlan({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'name': name};

  static ProductPlan? fromJson(String id, Object? json) {
    if (json is! Map) return null;
    final name = _clean(json['name']);
    if (name == null) return null;
    return ProductPlan(id: id, name: name);
  }
}

/// One product's label inside one app. Either field may be null.
class ProductLabel {
  const ProductLabel({this.name, this.planId});

  /// What the app shows instead of the product id.
  final String? name;

  /// The [ProductPlan.id] this product belongs to, if any.
  final String? planId;

  bool get isEmpty => _clean(name) == null && _clean(planId) == null;

  Map<String, dynamic> toJson() => {
    'name': ?_clean(name),
    'plan': ?_clean(planId),
  };

  static ProductLabel? fromJson(Object? json) {
    if (json is! Map) return null;
    final label = ProductLabel(
      name: _clean(json['name']),
      planId: _clean(json['plan']),
    );
    return label.isEmpty ? null : label;
  }
}

/// Everything named inside one app.
class AppProductLabels {
  const AppProductLabels({this.products = const {}, this.plans = const {}});

  final Map<String, ProductLabel> products;
  final Map<String, ProductPlan> plans;

  bool get isEmpty => products.isEmpty && plans.isEmpty;

  int get namedCount =>
      products.values.where((l) => _clean(l.name) != null).length;

  String? nameOf(String productId) => _clean(products[productId]?.name);

  String? planIdOf(String productId) => _clean(products[productId]?.planId);

  String? planName(String? planId) {
    final id = _clean(planId);
    if (id == null) return null;
    return _clean(plans[id]?.name);
  }

  /// Plan id whose name matches [name] ignoring case, else null.
  String? planIdForName(String name) {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final plan in plans.values) {
      if (plan.name.toLowerCase() == wanted) return plan.id;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    if (plans.isNotEmpty)
      'plans': {for (final p in plans.values) p.id: p.toJson()},
    if (products.isNotEmpty)
      'products': {for (final e in products.entries) e.key: e.value.toJson()},
  };

  static AppProductLabels fromJson(Object? json) {
    if (json is! Map) return const AppProductLabels();
    final plans = <String, ProductPlan>{};
    final rawPlans = json['plans'];
    if (rawPlans is Map) {
      for (final e in rawPlans.entries) {
        final id = _clean(e.key);
        final plan = id == null ? null : ProductPlan.fromJson(id, e.value);
        if (plan != null) plans[plan.id] = plan;
      }
    }
    final products = <String, ProductLabel>{};
    final rawProducts = json['products'];
    if (rawProducts is Map) {
      for (final e in rawProducts.entries) {
        final id = _clean(e.key);
        if (id == null) continue;
        final label = ProductLabel.fromJson(e.value);
        if (label == null) continue;
        // A plan that is no longer in [plans] would show as a raw slug, so
        // drop the reference but keep the name.
        products[id] = label.planId == null || plans.containsKey(label.planId)
            ? label
            : ProductLabel(name: label.name);
      }
    }
    return AppProductLabels(products: products, plans: plans);
  }
}

/// Labels for every app on the account, keyed by
/// `appKeyForTransaction` (app id, else bundle id, else name).
class ProductLabels {
  const ProductLabels({this.apps = const {}});

  const ProductLabels.empty() : apps = const {};

  final Map<String, AppProductLabels> apps;

  bool get isEmpty => apps.values.every((a) => a.isEmpty);

  AppProductLabels forApp(String appKey) =>
      apps[appKey] ?? const AppProductLabels();

  /// The name to show for [productId] in [appKey], if the developer set one.
  String? displayName(String appKey, String? productId) {
    final id = _clean(productId);
    if (id == null) return null;
    return forApp(appKey).nameOf(id);
  }

  /// The plan family's name for [productId] in [appKey], if it has one.
  String? planName(String appKey, String? productId) {
    final id = _clean(productId);
    if (id == null) return null;
    final app = forApp(appKey);
    return app.planName(app.planIdOf(id));
  }

  int get namedCount => apps.values.fold(0, (sum, app) => sum + app.namedCount);

  ProductLabels withApp(String appKey, AppProductLabels app) {
    final next = Map<String, AppProductLabels>.from(apps);
    if (app.isEmpty) {
      next.remove(appKey);
    } else {
      next[appKey] = app;
    }
    return ProductLabels(apps: next);
  }

  Map<String, dynamic> toJson() => {
    'apps': {
      for (final e in apps.entries)
        if (!e.value.isEmpty) e.key: e.value.toJson(),
    },
  };

  static ProductLabels fromJson(Object? json) {
    if (json is! Map) return const ProductLabels.empty();
    final rawApps = json['apps'];
    if (rawApps is! Map) return const ProductLabels.empty();
    final apps = <String, AppProductLabels>{};
    for (final e in rawApps.entries) {
      final key = _clean(e.key);
      if (key == null) continue;
      final app = AppProductLabels.fromJson(e.value);
      if (!app.isEmpty) apps[key] = app;
    }
    return ProductLabels(apps: apps);
  }
}

/// Lowercase slug for a new plan: `Pro Annual` → `pro-annual`.
String productPlanSlug(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'plan' : slug;
}

String? _clean(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
