import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/services/push/push_channel.dart';

void main() {
  // The notifier's tests use the same vectors (notifier/test/notifier.test.ts).
  test('topics match the notifier', () {
    expect(
      PushChannel.topicFor('A' * 43),
      'openrc-OWRekNBZkzKbFFTQk_uwY8KokTiMuahzVgMI9gff0J8',
    );
    expect(
      PushChannel.topicFor('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO_-'),
      'openrc-fBymwA0lTBXElb4ISJn8PeJFiPK6IDd3IUlboxL2K70',
    );
  });

  test('new secrets are 32 random bytes the notifier accepts', () {
    final a = PushChannel.newSecret();
    final b = PushChannel.newSecret();
    expect(a, hasLength(43));
    expect(a, isNot(b));
    expect(PushChannel.parse(a), a);
    expect(PushChannel.newSecret(Random(1)), PushChannel.newSecret(Random(1)));
  });

  test('reads pasted headers with or without Bearer', () {
    final secret = 'A' * 43;
    expect(PushChannel.authorizationHeader(secret), 'Bearer $secret');
    expect(PushChannel.parse('Bearer $secret'), secret);
    expect(PushChannel.parse('  bearer   $secret \n'), secret);
    expect(PushChannel.parse(secret), secret);
    expect(PushChannel.parse('Bearer ${'A' * 42}'), isNull);
    expect(PushChannel.parse('${'A' * 42}+'), isNull);
    expect(PushChannel.parse(''), isNull);
  });
}
