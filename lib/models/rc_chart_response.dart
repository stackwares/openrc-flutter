class RcChartDataPoint {
  final int? cohort;
  final int? measure;
  final double? value;

  const RcChartDataPoint({this.cohort, this.measure, this.value});

  factory RcChartDataPoint.fromJson(Map<String, dynamic> json) =>
      RcChartDataPoint(
        cohort: json['cohort'] as int?,
        measure: json['measure'] as int?,
        value: (json['value'] as num?)?.toDouble(),
      );
}

class RcChartResponse {
  final List<RcChartDataPoint>? values;
  final Map<String, dynamic>? summary;
  final String? lastComputedAt;

  /// Query parameters the API ignored, by kind, e.g. `{filters: [store]}`.
  final Map<String, dynamic>? unsupportedParams;

  const RcChartResponse({
    this.values,
    this.summary,
    this.lastComputedAt,
    this.unsupportedParams,
  });

  factory RcChartResponse.fromJson(Map<String, dynamic> json) => RcChartResponse(
        values: (json['values'] as List<dynamic>?)
            ?.map((e) =>
                RcChartDataPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        summary: json['summary'] as Map<String, dynamic>?,
        lastComputedAt: json['last_computed_at'] as String?,
        unsupportedParams: json['unsupported_params'] as Map<String, dynamic>?,
      );

  /// Names of the query parameters the API ignored.
  List<String> get ignoredParams => [
        for (final v in unsupportedParams?.values ?? const [])
          if (v is List) ...v.whereType<String>(),
      ];

  double? getSummaryValue(String category, String key) {
    final cat = summary?[category];
    if (cat is Map<String, dynamic>) {
      final v = cat[key];
      return (v as num?)?.toDouble();
    }
    return null;
  }

  int? getSummaryInt(String category, String key) {
    final cat = summary?[category];
    if (cat is Map<String, dynamic>) {
      final v = cat[key];
      return (v as num?)?.toInt();
    }
    return null;
  }
}
