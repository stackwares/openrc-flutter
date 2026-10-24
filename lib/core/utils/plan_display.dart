import 'package:easy_localization/easy_localization.dart';
import 'package:openrc/core/utils/app_identity.dart';
import 'package:openrc/core/utils/product_label_suggest.dart';
import 'package:openrc/models/product_labels.dart';
import 'package:openrc/models/rc_transaction.dart';

/// The product id exactly as RevenueCat stores it.
String rawProductId(RcTransaction tx, {String? ifEmpty}) {
  final id = tx.productIdentifier?.trim();
  if (id != null && id.isNotEmpty) return id;
  return ifEmpty ?? 'products.unknown'.tr();
}

/// What to call the product: the developer's name when they gave one, else
/// the store product id.
String planProductId(
  RcTransaction tx, {
  ProductLabels labels = const ProductLabels.empty(),
  String? ifEmpty,
}) {
  final id = tx.productIdentifier?.trim();
  if (id != null && id.isNotEmpty) {
    return labels.displayName(productLabelAppKey(tx), id) ?? id;
  }
  return ifEmpty ?? 'products.unknown'.tr();
}

/// The product's plan family (`Pro` for a monthly and an annual product),
/// when the developer grouped it.
String? planFamilyName(
  RcTransaction tx, {
  ProductLabels labels = const ProductLabels.empty(),
}) {
  return labels.planName(productLabelAppKey(tx), tx.productIdentifier);
}

/// Product name and, when the dates tell it, the plan length:
/// `com.acme.pro_yearly · Annual`.
///
/// A name that already is the period (`Monthly`, `Yearly`, `Lifetime`) is
/// not repeated: the row reads `Monthly`, not `Monthly · Monthly`.
String planDescription(
  RcTransaction tx, {
  ProductLabels labels = const ProductLabels.empty(),
}) {
  final id = planProductId(tx, labels: labels);
  final length = planLengthLabel(tx);
  if (length == null || _nameStatesLength(id, length)) return id;
  return '$id  ·  $length';
}

/// The localized name the built-in parser gives a period, e.g. `Monthly`.
String productPeriodName(ProductPeriodLabel period) => switch (period) {
  ProductPeriodLabel.yearly => 'products.nameYearly'.tr(),
  ProductPeriodLabel.monthly => 'products.nameMonthly'.tr(),
  ProductPeriodLabel.weekly => 'products.nameWeekly'.tr(),
  ProductPeriodLabel.lifetime => 'products.nameLifetime'.tr(),
  ProductPeriodLabel.oneYear => 'products.nameOneYear'.tr(),
  ProductPeriodLabel.oneMonth => 'products.nameOneMonth'.tr(),
  ProductPeriodLabel.oneWeek => 'products.nameOneWeek'.tr(),
};

/// True when [name] already says the plan length, so a row doesn't read
/// `Monthly · Monthly` or `Yearly · Annual`. A name that is any other period
/// keeps the length: `Pro · Monthly`, and a trial keeps its own label
/// (`Monthly · 3-day trial`).
bool _nameStatesLength(String name, String length) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) return false;
  final l = length.trim().toLowerCase();
  if (n == l) return true;
  for (final period in ProductPeriodLabel.values) {
    if (n != productPeriodName(period).toLowerCase()) continue;
    return _lengthKeyFor(period).tr().toLowerCase() == l;
  }
  return false;
}

/// The plan-length label a period name stands for.
String _lengthKeyFor(ProductPeriodLabel period) => switch (period) {
  ProductPeriodLabel.yearly || ProductPeriodLabel.oneYear => 'products.annual',
  ProductPeriodLabel.monthly || ProductPeriodLabel.oneMonth =>
    'products.monthly',
  ProductPeriodLabel.weekly || ProductPeriodLabel.oneWeek => 'products.weekly',
  ProductPeriodLabel.lifetime => 'products.oneTime',
};

/// Plan length read from the purchase and expiry dates, which works for any
/// product naming. Null when the dates can't tell: sandbox purchases (the
/// stores shorten test periods to minutes) or missing dates.
///
/// A trial or intro offer expires when the offer ends, not the plan, so it
/// is labelled as such instead.
String? planLengthLabel(RcTransaction tx) {
  if (tx.isSandbox == true) return null;
  final purchased = DateTime.tryParse(tx.purchaseDate?.trim() ?? '');
  if (purchased == null) return null;
  final expiresRaw = tx.expiresDate?.trim();
  if (expiresRaw == null || expiresRaw.isEmpty) {
    return 'products.oneTime'.tr();
  }
  final expires = DateTime.tryParse(expiresRaw);
  if (expires == null || !expires.isAfter(purchased)) return null;
  final days = (expires.difference(purchased).inHours / 24).round();

  if (tx.type == RcTransactionType.trial) {
    return days > 0 ? 'products.trialDays'.plural(days) : null;
  }
  if (tx.isInIntroductoryPricePeriod == true) {
    return 'products.introOffer'.tr();
  }
  return planLengthForDays(days);
}

/// Store periods for a span of [days]; months and years vary in length and
/// renewals can shift by a day, so each period matches a small range.
String? planLengthForDays(int days) {
  if (days <= 0) return null;
  if (days >= 6 && days <= 8) return 'products.weekly'.tr();
  if (days >= 358 && days <= 372) return 'products.annual'.tr();
  for (final months in const [1, 2, 3, 6]) {
    if ((days - months * 30.44).abs() <= months * 2 + 1) {
      return months == 1
          ? 'products.monthly'.tr()
          : 'products.months'.plural(months);
    }
  }
  return 'products.days'.plural(days);
}
