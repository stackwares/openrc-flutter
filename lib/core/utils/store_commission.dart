import 'package:openrc/services/commission_settings_store.dart';

enum StoreCommissionPlatform { apple, google, other }

/// Classifies [store] strings from RevenueCat (e.g. `App Store`, `Play Store`).
StoreCommissionPlatform classifyStore(String? store) {
  final s = store?.trim().toLowerCase().replaceAll(' ', '_') ?? '';
  if (s == 'app_store' ||
      s == 'mac_app_store' ||
      s == 'appstore' ||
      s == 'apple') {
    return StoreCommissionPlatform.apple;
  }
  if (s == 'play_store' ||
      s == 'google_play' ||
      s == 'playstore' ||
      s == 'android') {
    return StoreCommissionPlatform.google;
  }
  return StoreCommissionPlatform.other;
}

double _multiplierForPercent(double percent) {
  return 1 - (percent / 100).clamp(0.0, 100.0);
}

/// Net multiplier for a specific store (1.0 = no change).
double netMultiplierForStore(String? store, CommissionSettings settings) {
  if (!settings.adjustmentEnabled) return 1.0;
  switch (classifyStore(store)) {
    case StoreCommissionPlatform.apple:
      return _multiplierForPercent(settings.appleCommissionPercent);
    case StoreCommissionPlatform.google:
      return _multiplierForPercent(settings.googleCommissionPercent);
    case StoreCommissionPlatform.other:
      return 1.0;
  }
}

/// Average of Apple & Google rates — for aggregates without a store breakdown.
double netMultiplierBlended(CommissionSettings settings) {
  if (!settings.adjustmentEnabled) return 1.0;
  final avg = (settings.appleCommissionPercent + settings.googleCommissionPercent) /
      2;
  return _multiplierForPercent(avg);
}

/// Applies commission rules to a gross USD amount for display.
double adjustUsdForDisplay({
  required double gross,
  required CommissionSettings settings,
  String? store,
  bool useBlended = false,
}) {
  if (!settings.adjustmentEnabled) return gross;
  final m = useBlended ? netMultiplierBlended(settings) : netMultiplierForStore(store, settings);
  return gross * m;
}
