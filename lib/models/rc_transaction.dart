class RcTransactionApp {
  final String? bundleId;
  final String? id;
  final String? name;

  const RcTransactionApp({this.bundleId, this.id, this.name});

  factory RcTransactionApp.fromJson(Map<String, dynamic> json) =>
      RcTransactionApp(
        bundleId: json['bundle_id'] as String?,
        id: json['id'] as String?,
        name: json['name'] as String?,
      );
}

enum RcTransactionType {
  newSubscription,
  oneTimePurchase,
  renewal,
  trial,
  conversion,
  refund,
  unknown,
}

class RcTransaction {
  final RcTransactionApp? app;
  final String? expiresDate;
  final bool? isInIntroductoryPricePeriod;
  final bool? isRenewal;
  final bool? isSandbox;
  final bool? isTrialConversion;
  final bool? isTrialPeriod;
  final String? productIdentifier;
  final String? purchaseDate;
  final double? revenue;
  final String? store;
  final String? storeTransactionIdentifier;
  final String? subscriberCountryCode;
  final String? subscriberId;
  final String? subscriberLastSeenPlatform;
  final bool? wasRefunded;

  const RcTransaction({
    this.app,
    this.expiresDate,
    this.isInIntroductoryPricePeriod,
    this.isRenewal,
    this.isSandbox,
    this.isTrialConversion,
    this.isTrialPeriod,
    this.productIdentifier,
    this.purchaseDate,
    this.revenue,
    this.store,
    this.storeTransactionIdentifier,
    this.subscriberCountryCode,
    this.subscriberId,
    this.subscriberLastSeenPlatform,
    this.wasRefunded,
  });

  factory RcTransaction.fromJson(Map<String, dynamic> json) => RcTransaction(
    app: json['app'] != null
        ? RcTransactionApp.fromJson(json['app'] as Map<String, dynamic>)
        : null,
    expiresDate: json['expires_date'] as String?,
    isInIntroductoryPricePeriod:
        json['is_in_introductory_price_period'] as bool?,
    isRenewal: json['is_renewal'] as bool?,
    isSandbox: json['is_sandbox'] as bool?,
    isTrialConversion: json['is_trial_conversion'] as bool?,
    isTrialPeriod: json['is_trial_period'] as bool?,
    productIdentifier: json['product_identifier'] as String?,
    purchaseDate: json['purchase_date'] as String?,
    revenue: (json['revenue'] as num?)?.toDouble(),
    store: json['store'] as String?,
    storeTransactionIdentifier:
        json['store_transaction_identifier'] as String?,
    subscriberCountryCode: json['subscriber_country_code'] as String?,
    subscriberId: json['subscriber_id'] as String?,
    subscriberLastSeenPlatform:
        json['subscriber_last_seen_platform'] as String?,
    wasRefunded: json['was_refunded'] as bool?,
  );

  RcTransactionType get type {
    if (wasRefunded == true) return RcTransactionType.refund;
    if (isTrialPeriod == true && isTrialConversion != true) {
      return RcTransactionType.trial;
    }
    if (isTrialConversion == true) return RcTransactionType.conversion;
    if (isRenewal == true) return RcTransactionType.renewal;
    if (isTrialPeriod == true) return RcTransactionType.newSubscription;
    final store = this.store;
    if (store == 'Stripe' && isRenewal != true && isTrialPeriod != true) {
      return RcTransactionType.oneTimePurchase;
    }
    if (isRenewal != true && isTrialPeriod != true) {
      return RcTransactionType.newSubscription;
    }
    return RcTransactionType.unknown;
  }
}

class RcTransactionsRequest {
  final bool sandboxMode;
  final int limit;
  final int? startFrom;
  final String? endDate;

  const RcTransactionsRequest({
    this.sandboxMode = false,
    this.limit = 20,
    this.startFrom,
    this.endDate,
  });

  Map<String, dynamic> toQueryParameters() => {
    'sandbox_mode': sandboxMode,
    'limit': limit,
    if (startFrom != null) 'start_from': startFrom,
    if (endDate != null) 'end_date': endDate,
  };
}

class RcTransactionsResponse {
  final int? firstPurchaseMs;
  final int? lastPurchaseMs;
  final List<RcTransaction>? transactions;

  const RcTransactionsResponse({
    this.firstPurchaseMs,
    this.lastPurchaseMs,
    this.transactions,
  });

  factory RcTransactionsResponse.fromJson(Map<String, dynamic> json) =>
      RcTransactionsResponse(
        firstPurchaseMs: json['first_purchase_ms'] as int?,
        lastPurchaseMs: json['last_purchase_ms'] as int?,
        transactions: (json['transactions'] as List<dynamic>?)
            ?.map((e) => RcTransaction.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
