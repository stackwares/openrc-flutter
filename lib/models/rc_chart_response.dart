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

  const RcChartResponse({this.values, this.summary, this.lastComputedAt});

  factory RcChartResponse.fromJson(Map<String, dynamic> json) => RcChartResponse(
        values: (json['values'] as List<dynamic>?)
            ?.map((e) =>
                RcChartDataPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        summary: json['summary'] as Map<String, dynamic>?,
        lastComputedAt: json['last_computed_at'] as String?,
      );

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
