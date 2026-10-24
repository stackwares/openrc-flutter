import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/utils/currency_format.dart';
import 'package:openrc/core/utils/store_commission.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/services/display_currency_store.dart';
import 'package:openrc/services/exchange_rate_provider.dart';

/// Converts RevenueCat USD amounts into the user's display currency and fee
/// setting so the model never invents FX.
class AgentDisplayMoney {
  const AgentDisplayMoney({
    required this.currency,
    required this.feesApplied,
    required this.usdToDisplay,
    required this.settings,
  });

  factory AgentDisplayMoney.fromRef(Ref ref) {
    final settings = ref.read(commissionSettingsProvider);
    final requested = ref.read(displayCurrencyProvider);
    final rates = ref.read(usdExchangeRatesProvider).asData?.value;
    final rate = requested == 'USD'
        ? 1.0
        : rates?[requested.toLowerCase()];
    final usable = rate != null && rate > 0;
    return AgentDisplayMoney(
      currency: usable ? requested : 'USD',
      feesApplied: settings.adjustmentEnabled,
      usdToDisplay: usable ? rate : 1.0,
      settings: settings,
    );
  }

  final String currency;
  final bool feesApplied;
  final double usdToDisplay;
  final CommissionSettings settings;

  double toDisplay(
    double usd, {
    String? store,
    bool blended = false,
  }) {
    final net = adjustUsdForDisplay(
      gross: usd,
      settings: settings,
      store: store,
      useBlended: blended,
    );
    return net * usdToDisplay;
  }

  /// Currency conversion only, for amounts that are already net (payouts)
  /// or that the app shows before fees (Charts).
  double convert(double usd) => usd * usdToDisplay;

  String format(double displayAmount) {
    if (currency == 'USD') return formatCompactUsd(displayAmount);
    return formatCompactForeign(displayAmount, currency);
  }

  /// [fees] false marks results whose amounts skip the fee setting.
  Map<String, dynamic> meta({bool fees = true}) => {
        'currency': currency,
        'fees_applied': fees && feesApplied,
      };
}
