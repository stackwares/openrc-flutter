class RcTransactionDetailEvent {
  final String? type;
  final double? price;
  final String? currency;
  final double? priceInPurchasedCurrency;
  final int? eventTimestampMs;
  final int? purchasedAtMs;
  final int? expirationAtMs;
  final String? productId;
  final String? newProductId;
  final String? offerCode;
  final String? cancelReason;
  final String? periodType;
  final bool? isTrialConversion;
  final List<String>? transferredFrom;
  final List<String>? transferredTo;

  const RcTransactionDetailEvent({
    this.type,
    this.price,
    this.currency,
    this.priceInPurchasedCurrency,
    this.eventTimestampMs,
    this.purchasedAtMs,
    this.expirationAtMs,
    this.productId,
    this.newProductId,
    this.offerCode,
    this.cancelReason,
    this.periodType,
    this.isTrialConversion,
    this.transferredFrom,
    this.transferredTo,
  });

  factory RcTransactionDetailEvent.fromJson(Map<String, dynamic> json) =>
      RcTransactionDetailEvent(
        type: json['type'] as String?,
        price: (json['price'] as num?)?.toDouble(),
        currency: json['currency'] as String?,
        priceInPurchasedCurrency:
            (json['price_in_purchased_currency'] as num?)?.toDouble(),
        eventTimestampMs: json['event_timestamp_ms'] as int?,
        purchasedAtMs: json['purchased_at_ms'] as int?,
        expirationAtMs: json['expiration_at_ms'] as int?,
        productId: json['product_id'] as String?,
        newProductId: json['new_product_id'] as String?,
        offerCode: json['offer_code'] as String?,
        cancelReason: json['cancel_reason'] as String?,
        periodType: json['period_type'] as String?,
        isTrialConversion: json['is_trial_conversion'] as bool?,
        transferredFrom: (json['transferred_from'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList(),
        transferredTo: (json['transferred_to'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList(),
      );
}

class RcTransactionDetailActivityResponse {
  final List<RcTransactionDetailEvent>? events;
  final String? subscriberAppUserId;

  const RcTransactionDetailActivityResponse({
    this.events,
    this.subscriberAppUserId,
  });

  factory RcTransactionDetailActivityResponse.fromJson(
      Map<String, dynamic> json) {
    final subscriber = json['subscriber'] as Map<String, dynamic>?;
    return RcTransactionDetailActivityResponse(
      events: (json['events'] as List<dynamic>?)
          ?.map((e) => RcTransactionDetailEvent.fromJson(
              e as Map<String, dynamic>))
          .toList(),
      subscriberAppUserId: subscriber?['app_user_id'] as String?,
    );
  }
}
