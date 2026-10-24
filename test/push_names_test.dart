import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/models/product_labels.dart';
import 'package:openrc/services/push/push_names.dart';

void main() {
  const pro = ProductLabel(name: 'Pro');
  const lite = ProductLabel(name: ' Lite ');

  test('takes every app\'s names, by product id', () {
    final labels = const ProductLabels.empty()
        .withApp('ios', const AppProductLabels(products: {'com.a.pro': pro}))
        .withApp(
          'android',
          const AppProductLabels(
            products: {'com.a.lite': lite, 'com.a.bare': ProductLabel()},
          ),
        );
    final names = PushNames.of(labels);
    expect(names.count, 2);
    expect(names.nameOf('com.a.pro'), 'Pro');
    expect(names.nameOf(' com.a.lite '), 'Lite');
    expect(names.nameOf('com.a.bare'), isNull);
    expect(names.nameOf(null), isNull);
    expect(PushNames.of(const ProductLabels.empty()).isEmpty, isTrue);
  });

  test('sends one entry per product, sorted, as the notifier reads them', () {
    final names = PushNames({
      'com.a.z': 'Zed',
      'com.a.a': 'Alpha Annual',
    });
    expect(
      names.encoded,
      'com.a.a%0AAlpha+Annual%09com.a.z%0AZed',
    );
    expect(names.query, {'names': names.encoded});
    expect(const PushNames.empty().query, isEmpty);
    expect(const PushNames.empty().encoded, isNull);
  });

  test('keeps a push to one line, without its own separators', () {
    final names = PushNames({
      'com.a.pro': ' Pro\tAnnual\n2024  ',
      'com.a.ctl': 'a\u0000b',
    });
    expect(names.nameOf('com.a.pro'), 'Pro Annual 2024');
    expect(names.nameOf('com.a.ctl'), 'a b');
    expect(names.encoded, isNot(contains('\t')));
    expect(names.encoded, isNot(contains('\n')));
  });

  test('cuts a name longer than a notification row', () {
    final names = PushNames({'com.a.pro': 'x' * 100});
    expect(names.nameOf('com.a.pro'), hasLength(60));
  });

  test('stops before the webhook URL gets long', () {
    final labels = const ProductLabels.empty().withApp(
      'ios',
      AppProductLabels(
        products: {
          for (var i = 0; i < 200; i++)
            'com.acme.subscription.product.number.$i': ProductLabel(
              name: 'Product $i',
            ),
        },
      ),
    );
    final names = PushNames.of(labels);
    final encoded = names.encoded!;
    expect(encoded.length, lessThanOrEqualTo(1800));
    // Whole entries only, and the first products by id, so the URL is stable.
    expect(encoded.split('%09').first, startsWith('com.acme.subscription'));
    expect(encoded, isNot(endsWith('%09')));
    for (final entry in encoded.split('%09')) {
      expect(entry, contains('%0A'));
    }
  });

  test('survives a restart', () {
    final names = PushNames({'com.a.pro': 'Pro'});
    final restored = PushNames.fromJson(names.toJson());
    expect(restored.sameAs(names), isTrue);
    expect(restored.nameOf('com.a.pro'), 'Pro');
    expect(
      PushNames.fromJson({'names': {'com.a.pro': ' Pro ', '': 'x'}}).count,
      1,
    );
    expect(PushNames.fromJson(null).isEmpty, isTrue);
    expect(PushNames.fromJson({'names': 'nope'}).isEmpty, isTrue);
  });

  test('two apps naming one product keep the first app\'s name', () {
    final labels = const ProductLabels.empty()
        .withApp(
          'com.acme.ios',
          const AppProductLabels(products: {'com.shared.pro': pro}),
        )
        .withApp(
          'com.acme.android',
          const AppProductLabels(
            products: {'com.shared.pro': ProductLabel(name: 'Other')},
          ),
        );
    // Apps are read in id order, so the Android app's name wins here.
    expect(PushNames.of(labels).nameOf('com.shared.pro'), 'Other');
  });
}
