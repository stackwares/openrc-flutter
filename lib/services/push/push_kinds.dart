/// The kinds of notification someone can choose. The notifier knows them by
/// [id] (`notifier/src/copy.ts`, `KINDS`) and sorts each event into one;
/// keep the two in step. [eventTypes] are the RevenueCat events a kind comes
/// from: some kinds share one (a trial and a new subscription are both
/// `INITIAL_PURCHASE`), so RevenueCat's own filter can't tell them apart and
/// the notifier filters by kind instead.
enum PushKind {
  newSubscription('new', '🔵', ['INITIAL_PURCHASE']),
  trial('trial', '🟠', ['INITIAL_PURCHASE']),
  conversion('conversion', '🔵', ['RENEWAL']),
  renewal('renewal', '🟢', ['RENEWAL']),
  purchase('purchase', '🟣', ['NON_RENEWING_PURCHASE']),
  resubscribe('resubscribe', '🟢', ['UNCANCELLATION']),
  cancel('cancel', '🟡', ['CANCELLATION']),
  refund('refund', '🔴', ['CANCELLATION', 'REFUND_REVERSED']),
  billing('billing', '🔴', ['BILLING_ISSUE']),
  expire('expire', '🔴', ['EXPIRATION']),
  change('change', '⚪', [
    'PRODUCT_CHANGE',
    'SUBSCRIPTION_PAUSED',
    'SUBSCRIPTION_EXTENDED',
  ]);

  const PushKind(this.id, this.emoji, this.eventTypes);

  final String id;
  final String emoji;
  final List<String> eventTypes;

  static final Set<PushKind> all = Set.unmodifiable(values);

  /// Money coming in.
  static const sales = {
    newSubscription,
    trial,
    conversion,
    renewal,
    purchase,
    resubscribe,
  };

  /// Someone new paying or about to.
  static const newCustomers = {newSubscription, trial, conversion, purchase};

  /// Customers leaving or at risk.
  static const churn = {cancel, refund, billing, expire};

  /// The RevenueCat events [kinds] need, in a stable order.
  static List<String> eventTypesFor(Set<PushKind> kinds) => [
    for (final type in {for (final k in values) ...k.eventTypes})
      if (kinds.any((k) => k.eventTypes.contains(type))) type,
  ];

  /// The `notify` value for a webhook URL, or null when [kinds] is all.
  static String? queryFor(Set<PushKind> kinds) => kinds.containsAll(values)
      ? null
      : [
          for (final k in values)
            if (kinds.contains(k)) k.id,
        ].join(',');

  /// Kinds from saved ids; unknown ids are dropped.
  static Set<PushKind> fromIds(Iterable<String> ids) => {
    for (final k in values)
      if (ids.contains(k.id)) k,
  };
}
