/// What the built-in parser can say about a product id, and the parser for a
/// model's answer. Pure: no network, no localisation.
library;

import 'dart:convert';

/// Longest name the app shows for a product.
const kProductLabelMaxChars = 24;

/// The billing periods the built-in parser recognises. Built-in names never
/// go beyond these seven labels: the fallback only says how often a product
/// bills, and leaves real names to the developer or the model.
enum ProductPeriodLabel {
  yearly,
  monthly,
  weekly,
  lifetime,
  oneYear,
  oneMonth,
  oneWeek,
}

/// The period a product id names, or null when it names none.
///
/// Explicit counts win over plain periods (`pro_1year` is [oneYear], not
/// [yearly]) and lifetime wins over everything. Only whole words count, so
/// `premium` is not a month and `early` is not a year.
ProductPeriodLabel? suggestProductPeriod(String productId) {
  final text = productId
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  if (text.isEmpty) return null;
  if (_lifetime.hasMatch(text)) return ProductPeriodLabel.lifetime;
  if (_oneYear.hasMatch(text)) return ProductPeriodLabel.oneYear;
  if (_oneMonth.hasMatch(text)) return ProductPeriodLabel.oneMonth;
  if (_oneWeek.hasMatch(text)) return ProductPeriodLabel.oneWeek;
  if (_yearly.hasMatch(text)) return ProductPeriodLabel.yearly;
  if (_monthly.hasMatch(text)) return ProductPeriodLabel.monthly;
  if (_weekly.hasMatch(text)) return ProductPeriodLabel.weekly;
  return null;
}

/// Trims [value] and cuts it to [max] characters on a word boundary.
String clampProductLabel(String value, {int max = kProductLabelMaxChars}) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.length <= max) return trimmed;
  final cut = trimmed.substring(0, max);
  final space = cut.lastIndexOf(' ');
  return (space > 0 ? cut.substring(0, space) : cut).trim();
}

/// Reads a model's JSON answer into per-product suggestions.
///
/// Accepts `{"labels":[{"id":…,"name":…,"plan":…}]}` (or a bare list), in a
/// code fence or not. Ids the model was not asked about, and entries with
/// nothing usable, are dropped. Throws [FormatException] when the answer
/// isn't JSON at all, so the caller can fall back to the parser.
Map<String, ProductLabelSuggestionDraft> parseProductLabelSuggestions(
  String raw,
  Set<String> allowedIds,
) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const FormatException('no JSON object in answer');
  }
  final decoded = jsonDecode(raw.substring(start, end + 1));
  final items = switch (decoded) {
    {'labels': final List<dynamic> labels} => labels,
    final List<dynamic> labels => labels,
    _ => const <dynamic>[],
  };

  final out = <String, ProductLabelSuggestionDraft>{};
  for (final item in items) {
    if (item is! Map) continue;
    final id = item['id'];
    if (id is! String) continue;
    final productId = id.trim();
    if (!allowedIds.contains(productId)) continue;
    final name = clampProductLabel(
      item['name'] is String ? item['name'] as String : '',
    );
    final plan = clampProductLabel(
      item['plan'] is String ? item['plan'] as String : '',
    );
    if (name.isEmpty && plan.isEmpty) continue;
    out[productId] = ProductLabelSuggestionDraft(
      productId: productId,
      name: name.isEmpty ? null : name,
      plan: plan.isEmpty ? null : plan,
    );
  }
  return out;
}

/// One product's name from either the parser or the model.
class ProductLabelSuggestionDraft {
  const ProductLabelSuggestionDraft({
    required this.productId,
    this.name,
    this.plan,
  });

  final String productId;
  final String? name;

  /// Plan family name shared by variants (monthly + annual).
  final String? plan;
}

// Whole words only: `premium` is not a month, `early` is not a year.
const _wordStart = r'(?<![a-z0-9])';
const _wordEnd = r'(?![a-z0-9])';

final _lifetime = RegExp(
  '$_wordStart(lifetime|one ?time|onetime|forever|once)$_wordEnd',
);
final _oneYear = RegExp(
  '$_wordStart(1|one) ?(y|yr|yrs|year|years)$_wordEnd',
);
final _oneMonth = RegExp(
  '$_wordStart(1|one) ?(m|mo|mon|month|months)$_wordEnd',
);
final _oneWeek = RegExp(
  '$_wordStart(1|one) ?(w|wk|week|weeks)$_wordEnd',
);
final _yearly = RegExp(
  '$_wordStart(annual|annually|yearly|year|years|yr|yrs)$_wordEnd',
);
final _monthly = RegExp(
  '$_wordStart(monthly|month|months|mo)$_wordEnd',
);
final _weekly = RegExp(
  '$_wordStart(weekly|week|weeks|wk)$_wordEnd',
);
