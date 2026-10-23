import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/services/exchange_rate_provider.dart';

void main() {
  test('a failed rate download is retried until it succeeds', () async {
    var calls = 0;
    final container = ProviderContainer(
      retry: (count, error) =>
          count < 5 ? const Duration(milliseconds: 1) : null,
      overrides: [
        usdExchangeRatesFetcherProvider.overrideWithValue(() async {
          calls++;
          return calls < 3 ? <String, double>{} : {'eur': 0.92};
        }),
      ],
    );
    addTearDown(container.dispose);

    final sub = container.listen(usdExchangeRatesProvider, (_, _) {});
    for (var i = 0; i < 50 && !sub.read().hasValue; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(sub.read().value, {'eur': 0.92});
    expect(calls, 3);
  });

  test('when every source fails the rates are an error, not empty', () async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        usdExchangeRatesFetcherProvider.overrideWithValue(
          () async => <String, double>{},
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(usdExchangeRatesProvider.future),
      throwsA(isA<ExchangeRatesUnavailable>()),
    );
  });
}
