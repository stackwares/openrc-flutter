/// How notifications read, following Settings: the app's language, the
/// display currency, and store fees when they're subtracted. The notifier reads it from the
/// webhook URL (`notifier/src/display.ts`); keep the two in step.
class PushDisplay {
  const PushDisplay({
    this.currency = 'USD',
    this.appleFee,
    this.googleFee,
    this.rate,
    this.language = 'en',
  });

  final String currency;

  /// App Store and Google Play fees in percent, when they're subtracted.
  final double? appleFee;
  final double? googleFee;

  /// The last saved rate (one US dollar in [currency]), for the notifier to
  /// use when it can't get a fresh one.
  final double? rate;

  /// The app's language as a translation file stem (`de`, `pt-BR`).
  final String language;

  /// Changes that need the webhooks updated. A newer [rate] alone doesn't:
  /// the notifier gets fresh rates itself, and this one is only a fallback.
  bool sameAs(PushDisplay other) =>
      language == other.language &&
      currency == other.currency &&
      appleFee == other.appleFee &&
      googleFee == other.googleFee;

  /// The webhook URL's query parameters; empty for English in US dollars
  /// before fees.
  Map<String, String> get query => {
    if (language != 'en') 'lang': language,
    if (currency != 'USD') 'currency': currency,
    if (currency != 'USD' && rate != null) 'rate': _number(rate!),
    if (appleFee != null && googleFee != null)
      'fees': '${_number(appleFee!)},${_number(googleFee!)}',
  };

  static String _number(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  Map<String, Object?> toJson() => {
    'currency': currency,
    'appleFee': appleFee,
    'googleFee': googleFee,
    'rate': rate,
    'language': language,
  };

  factory PushDisplay.fromJson(Map<String, dynamic> json) => PushDisplay(
    currency: json['currency'] as String? ?? 'USD',
    appleFee: (json['appleFee'] as num?)?.toDouble(),
    googleFee: (json['googleFee'] as num?)?.toDouble(),
    rate: (json['rate'] as num?)?.toDouble(),
    language: json['language'] as String? ?? 'en',
  );
}
