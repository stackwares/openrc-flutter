class RcWebhook {
  final String? id;
  final String? projectId;
  final String? name;
  final String? url;
  final String? authorizationHeader;
  final String? environment;
  final String? appId;
  final List<String>? eventTypes;
  final String? createdAt;
  final String? updatedAt;

  const RcWebhook({
    this.id,
    this.projectId,
    this.name,
    this.url,
    this.authorizationHeader,
    this.environment,
    this.appId,
    this.eventTypes,
    this.createdAt,
    this.updatedAt,
  });

  factory RcWebhook.fromJson(Map<String, dynamic> json) => RcWebhook(
        id: json['id'] as String?,
        projectId: json['project_id'] as String?,
        name: json['name'] as String?,
        url: json['url'] as String?,
        authorizationHeader: json['authorization_header'] as String?,
        environment: json['environment'] as String?,
        appId: json['app_id'] as String?,
        eventTypes: (json['event_types'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );
}

class RcCreateWebhookRequest {
  final String? name;
  final String? url;
  final String? authorizationHeader;
  final String? environment;
  final String? appId;
  final List<String>? eventTypes;

  const RcCreateWebhookRequest({
    this.name,
    this.url,
    this.authorizationHeader,
    this.environment,
    this.appId,
    this.eventTypes,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (name != null) 'name': name,
        if (url != null) 'url': url,
        if (authorizationHeader != null)
          'authorization_header': authorizationHeader,
        if (environment != null) 'environment': environment,
        if (appId != null) 'app_id': appId,
        if (eventTypes != null) 'event_types': eventTypes,
      };
}

class RcUpdateWebhookRequest {
  final String? name;
  final String? url;
  final String? authorizationHeader;
  final String? environment;
  final String? appId;
  final List<String>? eventTypes;

  const RcUpdateWebhookRequest({
    this.name,
    this.url,
    this.authorizationHeader,
    this.environment,
    this.appId,
    this.eventTypes,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (name != null) 'name': name,
        if (url != null) 'url': url,
        if (authorizationHeader != null)
          'authorization_header': authorizationHeader,
        if (environment != null) 'environment': environment,
        if (appId != null) 'app_id': appId,
        if (eventTypes != null) 'event_types': eventTypes,
      };
}
