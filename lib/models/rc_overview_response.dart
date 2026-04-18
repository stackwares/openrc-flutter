class RcOverviewResponse {
  final double? mrr;
  final int? subscriptions;
  final int? trials;
  final double? revenue;
  final int? users;
  final int? newUsers;

  const RcOverviewResponse({
    this.mrr,
    this.subscriptions,
    this.trials,
    this.revenue,
    this.users,
    this.newUsers,
  });

  /// Parses `charts_v2/overview` payload (`metrics` array, Kedi `RCOverviewResponse`) or legacy flat keys.
  factory RcOverviewResponse.fromJson(Map<String, dynamic> json) {
    final metrics = json['metrics'] as List<dynamic>?;
    if (metrics != null && metrics.isNotEmpty) {
      double? mrr;
      int? subscriptions;
      int? trials;
      double? revenue;
      int? users;
      int? newUsers;

      for (final raw in metrics) {
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['id'] as String?;
        final value = raw['value'];
        if (id == null || value == null) continue;
        final n = value is num ? value : num.tryParse(value.toString());
        if (n == null) continue;

        switch (id) {
          case 'mrr':
            mrr = n.toDouble();
          case 'active_subscriptions':
            subscriptions = n.toInt();
          case 'active_trials':
            trials = n.toInt();
          case 'revenue':
            revenue = n.toDouble();
          case 'active_users':
            users = n.toInt();
          case 'new_customers':
            newUsers = n.toInt();
        }
      }

      return RcOverviewResponse(
        mrr: mrr,
        subscriptions: subscriptions,
        trials: trials,
        revenue: revenue,
        users: users,
        newUsers: newUsers,
      );
    }

    return RcOverviewResponse(
      mrr: (json['mrr'] as num?)?.toDouble(),
      subscriptions: json['subscriptions'] as int?,
      trials: json['trials'] as int?,
      revenue: (json['revenue'] as num?)?.toDouble(),
      users: json['users'] as int?,
      newUsers: json['new_users'] as int?,
    );
  }
}
