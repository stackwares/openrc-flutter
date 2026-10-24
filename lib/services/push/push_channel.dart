import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Where a device's notifications come from: a random secret that RevenueCat
/// sends as the webhook's Authorization header, and the FCM topic named
/// after a hash of it. The notifier (`notifier/src/topic.ts`) derives the
/// same topic, so it needs no record of devices; keep the two in step.
abstract final class PushChannel {
  /// 32 random bytes, base64url without padding.
  static final _secret = RegExp(r'^[A-Za-z0-9_-]{43}$');

  static String newSecret([Random? random]) {
    final rng = random ?? Random.secure();
    return _base64Url(List<int>.generate(32, (_) => rng.nextInt(256)));
  }

  static String topicFor(String secret) =>
      'openrc-${_base64Url(sha256.convert(utf8.encode('openrc-topic:$secret')).bytes)}';

  /// The value to paste into RevenueCat's Authorization header field.
  static String authorizationHeader(String secret) => 'Bearer $secret';

  /// The secret in a stored value or an Authorization header, with or
  /// without "Bearer ", or null when it isn't one.
  static String? parse(String input) {
    final value = input.trim().replaceFirst(
      RegExp(r'^Bearer\s+', caseSensitive: false),
      '',
    );
    return _secret.hasMatch(value) ? value : null;
  }

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
