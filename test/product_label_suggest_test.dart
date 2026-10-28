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

  group('periodLabelForRenewal', () {
    test('a product that does not renew reads as its term', () {
      expect(
        periodLabelForRenewal(ProductPeriodLabel.yearly, renews: false),
        ProductPeriodLabel.oneYear,
      );
      expect(
        periodLabelForRenewal(ProductPeriodLabel.monthly, renews: false),
        ProductPeriodLabel.oneMonth,
      );
      expect(
        periodLabelForRenewal(ProductPeriodLabel.weekly, renews: false),
        ProductPeriodLabel.oneWeek,
      );
    });

    test('a renewing product keeps the cadence', () {
      expect(
        periodLabelForRenewal(ProductPeriodLabel.yearly, renews: true),
        ProductPeriodLabel.yearly,
      );
      expect(
        periodLabelForRenewal(ProductPeriodLabel.monthly, renews: true),
        ProductPeriodLabel.monthly,
      );
    });

    test('terms already counted and lifetime unlocks are unchanged', () {
      for (final period in [
        ProductPeriodLabel.oneYear,
        ProductPeriodLabel.oneMonth,
        ProductPeriodLabel.oneWeek,
        ProductPeriodLabel.lifetime,
      ]) {
        expect(periodLabelForRenewal(period, renews: false), period);
        expect(periodLabelForRenewal(period, renews: true), period);
      }
    });
  });

  group('period tokens', () {
    test('the token the model is given reads back as the same period', () {
      for (final period in ProductPeriodLabel.values) {
        expect(
          productPeriodLabelFromToken(productPeriodToken(period)),
          period,
          reason: productPeriodToken(period),
        );
      }
    });

    test('a model answer must be one of our tokens', () {
      expect(productPeriodLabelFromToken('1 Year'), ProductPeriodLabel.oneYear);
      expect(
        productPeriodLabelFromToken('  Monthly '),
        ProductPeriodLabel.monthly,
      );
      // Spans this app has no label for are ignored, not rounded to one.
      expect(productPeriodLabelFromToken('quarterly'), isNull);
      expect(productPeriodLabelFromToken('3 months'), isNull);
      expect(productPeriodLabelFromToken('annual'), isNull);
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

    test('reads a corrected period, and a period-only answer', () {
      final parsed = parseProductLabelSuggestions(
        '{"labels":[{"id":"pro_yearly","period":"1 year"},'
        '{"id":"pro_monthly","period":"monthly"}]}',
        ids,
      );
      expect(parsed['pro_yearly']?.period, ProductPeriodLabel.oneYear);
      expect(parsed['pro_yearly']?.name, isNull);
      expect(parsed['pro_monthly']?.period, ProductPeriodLabel.monthly);
    });

    test('drops a period this app has no word for', () {
      final parsed = parseProductLabelSuggestions(
        '{"labels":[{"id":"pro_yearly","period":"quarterly"},'
        '{"id":"pro_monthly","period":"monthly"}]}',
        ids,
      );
      expect(parsed.keys, ['pro_monthly']);
      expect(parsed['pro_monthly']?.period, ProductPeriodLabel.monthly);
    });

    test('keeps the period even when the name is unusable', () {
      final parsed = parseProductLabelSuggestions(
        '{"labels":[{"id":"pro_yearly","name":"  ","plan":"",'
        '"period":"1 year"}]}',
        ids,
      );
      expect(parsed['pro_yearly']?.name, isNull);
      expect(parsed['pro_yearly']?.period, ProductPeriodLabel.oneYear);
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
