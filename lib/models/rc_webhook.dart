/// A webhook integration in a RevenueCat project. The authorization header
/// comes back masked, so it isn't read.
class RcWebhook {
  final String? id;
  final String? name;
  final String? url;
  final String? environment;
  final List<String>? eventTypes;

  const RcWebhook({
    this.id,
    this.name,
    this.url,
    this.environment,
    this.eventTypes,
  });

  factory RcWebhook.fromJson(Map<String, dynamic> json) => RcWebhook(
    id: json['id'] as String?,
    name: json['name'] as String?,
    url: json['url'] as String?,
    environment: json['environment'] as String?,
    eventTypes: (json['event_types'] as List<dynamic>?)
        ?.whereType<String>()
        .toList(),
  );

  /// The endpoint's host, when the URL parses. Never the query or headers.
  String? get host => Uri.tryParse(url ?? '')?.host;

  /// The endpoint's path, when the URL parses.
  String? get path => Uri.tryParse(url ?? '')?.path;
}

/// What a webhook is created or updated with.
class RcWebhookInput {
  final String name;
  final String url;
  final String authorizationHeader;

  /// `production`, `sandbox`, or null for both.
  final String? environment;

  /// Null sends every event type.
  final List<String>? eventTypes;

  const RcWebhookInput({
    required this.name,
    required this.url,
    required this.authorizationHeader,
    this.environment,
    this.eventTypes,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'authorization_header': authorizationHeader,
    'environment': environment,
    'event_types': eventTypes,
    'app_id': null,
  };
}

/// RevenueCat's test event, with the webhook endpoint's answer.
class RcWebhookTestResult {
  final bool successful;
  final int? responseCode;

  const RcWebhookTestResult({required this.successful, this.responseCode});

  factory RcWebhookTestResult.fromJson(Map<String, dynamic> json) =>
      RcWebhookTestResult(
        successful: json['successful_response'] == true,
        responseCode: json['response_code'] as int?,
      );
}
