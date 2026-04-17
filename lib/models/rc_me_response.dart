class RcMeApp {
  final String? id;
  final String? name;

  const RcMeApp({this.id, this.name});

  factory RcMeApp.fromJson(Map<String, dynamic> json) =>
      RcMeApp(id: json['id'] as String?, name: json['name'] as String?);
}

class RcMeBillingInfo {
  final int? currentMtr;
  final int? trailing30DayMtr;

  const RcMeBillingInfo({this.currentMtr, this.trailing30DayMtr});

  factory RcMeBillingInfo.fromJson(Map<String, dynamic> json) =>
      RcMeBillingInfo(
        currentMtr: json['current_mtr'] as int?,
        trailing30DayMtr: json['trailing_30day_mtr'] as int?,
      );
}

class RcMeResponse {
  final String? distinctId;
  final String? email;
  final String? name;
  final String? firstTransactionAt;
  final String? currentPlan;
  final RcMeBillingInfo? billingInfo;
  final List<RcMeApp>? apps;

  const RcMeResponse({
    this.distinctId,
    this.email,
    this.name,
    this.firstTransactionAt,
    this.currentPlan,
    this.billingInfo,
    this.apps,
  });

  factory RcMeResponse.fromJson(Map<String, dynamic> json) => RcMeResponse(
    distinctId: json['distinct_id'] as String?,
    email: json['email'] as String?,
    name: json['name'] as String?,
    firstTransactionAt: json['first_transaction_at'] as String?,
    currentPlan: json['current_plan'] as String?,
    billingInfo: json['billing_info'] != null
        ? RcMeBillingInfo.fromJson(json['billing_info'] as Map<String, dynamic>)
        : null,
    apps: (json['apps'] as List<dynamic>?)
        ?.map((e) => RcMeApp.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
