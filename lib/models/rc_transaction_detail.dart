import 'package:revenuecat/models/rc_transaction.dart';

class RcSubscriberAttribute {
  final String? key;
  final String? value;

  const RcSubscriberAttribute({this.key, this.value});

  factory RcSubscriberAttribute.fromJson(Map<String, dynamic> json) =>
      RcSubscriberAttribute(
        key: json['key'] as String?,
        value: (json['value'] is Map)
            ? (json['value']['value'] as String?)
            : json['value'] as String?,
      );
}

class RcSubscriptionStatus {
  final String? billingIssuesDetectedAt;
  final String? cancellationDate;
  final String? entitlementIdentifier;
  final String? expiresDate;
  final bool? isAutoRenewing;
  final bool? isTrial;
  final String? productIdentifier;
  final String? purchaseDate;
  final String? refundedAt;
  final String? unsubscribeDetectedAt;

  const RcSubscriptionStatus({
    this.billingIssuesDetectedAt,
    this.cancellationDate,
    this.entitlementIdentifier,
    this.expiresDate,
    this.isAutoRenewing,
    this.isTrial,
    this.productIdentifier,
    this.purchaseDate,
    this.refundedAt,
    this.unsubscribeDetectedAt,
  });

  factory RcSubscriptionStatus.fromJson(Map<String, dynamic> json) =>
      RcSubscriptionStatus(
        billingIssuesDetectedAt:
            json['billing_issues_detected_at'] as String?,
        cancellationDate: json['cancellation_date'] as String?,
        entitlementIdentifier:
            json['entitlement_identifier'] as String?,
        expiresDate: json['expires_date'] as String?,
        isAutoRenewing: json['is_auto_renewing'] as bool?,
        isTrial: json['is_trial'] as bool?,
        productIdentifier: json['product_identifier'] as String?,
        purchaseDate: json['purchase_date'] as String?,
        refundedAt: json['refunded_at'] as String?,
        unsubscribeDetectedAt:
            json['unsubscribe_detected_at'] as String?,
      );
}

class RcSubscriberHistory {
  final String? at;
  final String? event;
  final String? alias;
  final String? currency;
  final double? priceInPurchasedCurrency;
  final double? priceInUsd;
  final String? product;

  const RcSubscriberHistory({
    this.at,
    this.event,
    this.alias,
    this.currency,
    this.priceInPurchasedCurrency,
    this.priceInUsd,
    this.product,
  });

  factory RcSubscriberHistory.fromJson(Map<String, dynamic> json) =>
      RcSubscriberHistory(
        at: json['at'] as String?,
        event: json['event'] as String?,
        alias: json['alias'] as String?,
        currency: json['currency'] as String?,
        priceInPurchasedCurrency:
            (json['price_in_purchased_currency'] as num?)?.toDouble(),
        priceInUsd: (json['price_in_usd'] as num?)?.toDouble(),
        product: json['product'] as String?,
      );
}

class RcTransactionDetailResponse {
  final RcTransactionApp? app;
  final String? createdAt;
  final double? dollarsSpent;
  final List<RcSubscriberHistory>? history;
  final String? lastSeen;
  final String? lastSeenAppVersion;
  final String? lastSeenCountry;
  final String? lastSeenLocale;
  final String? lastSeenPlatform;
  final String? lastSeenPlatformVersion;
  final String? lastSeenSdkVersion;
  final List<RcSubscriberAttribute>? subscriberAttributes;
  final List<RcSubscriptionStatus>? subscriptionStatuses;

  const RcTransactionDetailResponse({
    this.app,
    this.createdAt,
    this.dollarsSpent,
    this.history,
    this.lastSeen,
    this.lastSeenAppVersion,
    this.lastSeenCountry,
    this.lastSeenLocale,
    this.lastSeenPlatform,
    this.lastSeenPlatformVersion,
    this.lastSeenSdkVersion,
    this.subscriberAttributes,
    this.subscriptionStatuses,
  });

  factory RcTransactionDetailResponse.fromJson(Map<String, dynamic> json) {
    final subscriber = json['subscriber'] as Map<String, dynamic>? ?? json;
    final subStatus = subscriber['subscription_status'] as Map<String, dynamic>?;
    final liveStatuses = subStatus?['live'] as List<dynamic>?;

    return RcTransactionDetailResponse(
      app: subscriber['app'] != null
          ? RcTransactionApp.fromJson(
              subscriber['app'] as Map<String, dynamic>)
          : null,
      createdAt: subscriber['created_at'] as String?,
      dollarsSpent: (subscriber['dollars_spent'] as num?)?.toDouble(),
      history: (subscriber['history'] as List<dynamic>?)
          ?.map((e) =>
              RcSubscriberHistory.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastSeen: subscriber['last_seen'] as String?,
      lastSeenAppVersion:
          subscriber['last_seen_app_version'] as String?,
      lastSeenCountry: subscriber['last_seen_country'] as String?,
      lastSeenLocale: subscriber['last_seen_locale'] as String?,
      lastSeenPlatform: subscriber['last_seen_platform'] as String?,
      lastSeenPlatformVersion:
          subscriber['last_seen_platform_version'] as String?,
      lastSeenSdkVersion:
          subscriber['last_seen_sdk_version'] as String?,
      subscriberAttributes:
          (subscriber['subscriber_attributes'] as List<dynamic>?)
              ?.map((e) => RcSubscriberAttribute.fromJson(
                  e as Map<String, dynamic>))
              .toList(),
      subscriptionStatuses: liveStatuses
          ?.map((e) => RcSubscriptionStatus.fromJson(
              e as Map<String, dynamic>))
          .toList(),
    );
  }
}
