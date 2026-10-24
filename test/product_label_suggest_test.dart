import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/core/utils/product_label_suggest.dart';

void main() {
  group('suggestProductPeriod', () {
    test('names only the period the id contains', () {
      expect(
        suggestProductPeriod('com.acme.pro.sub.annual.false'),
        ProductPeriodLabel.yearly,
      );
      expect(
        suggestProductPeriod('stein.premium_monthly'),
        ProductPeriodLabel.monthly,
      );
      expect(suggestProductPeriod('pro_weekly'), ProductPeriodLabel.weekly);
      expect(
        suggestProductPeriod('lifetime_unlock'),
        ProductPeriodLabel.lifetime,
      );
      expect(
        suggestProductPeriod('com.acme.one_time'),
        ProductPeriodLabel.lifetime,
      );
    });

    test('an explicit count wins over the plain period', () {
      expect(suggestProductPeriod('pro_1year'), ProductPeriodLabel.oneYear);
      expect(suggestProductPeriod('pro.1month'), ProductPeriodLabel.oneMonth);
      expect(suggestProductPeriod('pro_1w'), ProductPeriodLabel.oneWeek);
      expect(suggestProductPeriod('pro_1_year'), ProductPeriodLabel.oneYear);
      expect(suggestProductPeriod('pro_yearly'), ProductPeriodLabel.yearly);
    });

    test('lifetime wins over any period it is sold with', () {
      expect(
        suggestProductPeriod('lifetime_monthly'),
        ProductPeriodLabel.lifetime,
      );
    });

    test('whole words only', () {
      // "premium" is not a month, "early" is not a year, "promo" is not a mo.
      expect(suggestProductPeriod('premium_access'), isNull);
      expect(suggestProductPeriod('early_bird'), isNull);
      expect(suggestProductPeriod('promo_pack'), isNull);
    });

    test('names no period when the id names none', () {
      expect(suggestProductPeriod('com.acme.pro'), isNull);
      expect(suggestProductPeriod('1234'), isNull);
      expect(suggestProductPeriod('12month'), isNull);
      expect(suggestProductPeriod(''), isNull);
    });
  });

  group('parseProductLabelSuggestions', () {
    const ids = {'pro_monthly', 'pro_yearly'};

    test('reads a labels object, with or without a code fence', () {
      final parsed = parseProductLabelSuggestions(
        '```json\n{"labels":[{"id":"pro_monthly","name":"Pro",'
        '"plan":"Pro"}]}\n```',
        ids,
      );
      expect(parsed['pro_monthly']?.name, 'Pro');
      expect(parsed['pro_monthly']?.plan, 'Pro');
    });

    test('drops ids that were not asked about and blanks', () {
      final parsed = parseProductLabelSuggestions(
        '{"labels":[{"id":"other","name":"Nope"},'
        '{"id":"pro_monthly","name":"   "},'
        '{"id":"pro_yearly","name":"Pro"}]}',
        ids,
      );
      expect(parsed.keys, ['pro_yearly']);
    });

    test('cuts long names at a word boundary', () {
      final parsed = parseProductLabelSuggestions(
        '{"labels":[{"id":"pro_monthly","name":"'
        'Pro Monthly With Extra Words Beyond Limit"}]}',
        ids,
      );
      final name = parsed['pro_monthly']!.name!;
      expect(name.length, lessThanOrEqualTo(kProductLabelMaxChars));
      expect(name.endsWith(' '), isFalse);
    });

    test('throws on an answer that is not JSON', () {
      expect(
        () => parseProductLabelSuggestions('I cannot help with that.', ids),
        throwsFormatException,
      );
    });
  });

  test('clampProductLabel trims and cuts', () {
    expect(clampProductLabel('  Pro   Max  '), 'Pro Max');
    expect(clampProductLabel('a' * 40).length, kProductLabelMaxChars);
  });
}
