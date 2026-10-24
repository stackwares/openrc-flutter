import 'package:easy_localization/easy_localization.dart';
import 'package:openrc/models/rc_transaction.dart';

/// The plan as the developer named it: the store product id.
String planProductId(RcTransaction tx, {String? ifEmpty}) {
  final id = tx.productIdentifier?.trim();
  if (id != null && id.isNotEmpty) return id;
  return ifEmpty ?? 'products.unknown'.tr();
}

/// Product id and, when the dates tell it, the plan length:
/// `com.acme.pro_yearly · Annual`.
String planDescription(RcTransaction tx) {
  final length = planLengthLabel(tx);
  final id = planProductId(tx);
  return length == null ? id : '$id  ·  $length';
}

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
