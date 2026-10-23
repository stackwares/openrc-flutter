import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/services/telemetry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a build without a PostHog token never talks to PostHog', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('posthog_flutter'), (
          call,
        ) async {
          calls.add(call);
          return null;
        });

    expect(Telemetry.isAvailable, isFalse);
    await Telemetry.start();
    Telemetry.screen('Transactions');
    Telemetry.event('signed_in', {'two_factor': false});
    await Telemetry.setEnabled(false);

    expect(calls, isEmpty);
    expect(Telemetry.enabled, isFalse);
  });
}
