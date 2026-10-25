import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/settings/widgets/agent_settings_section.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/theme/app_theme.dart';

class _FakeSettings extends AgentSettingsNotifier {
  _FakeSettings(this.settings);

  final AgentSettings settings;

  @override
  Future<AgentSettings> build() async => settings;
}

const _savedKeySettings = AgentSettings(
  providerId: AgentProviderId.openai,
  model: 'gpt-4o',
  customBaseUrl: 'https://api.openai.com/v1',
  customStyle: AgentApiStyle.openAi,
  useFasterModel: false,
  hasKey: true,
);

/// Opens the provider sheet the way Settings and Ask do.
Future<void> _openSheet(
  WidgetTester tester, {
  required AgentSettings settings,
}) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  late BuildContext opener;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentSettingsProvider.overrideWith(() => _FakeSettings(settings)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(
          FlexScheme.indigoM3,
        ).copyWith(splashFactory: InkRipple.splashFactory),
        home: Builder(
          builder: (context) {
            opener = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  showAgentSettingsSheet(opener);
  await tester.pumpAndSettle();
}

Finder _keyField() => find.byWidgetPredicate(
  (w) => w is TextField && w.keyboardType == TextInputType.visiblePassword,
);

TextField _field(WidgetTester tester) => tester.widget<TextField>(_keyField());

void main() {
  testWidgets('a saved key is described, not shown as fake dots and an eye', (
    tester,
  ) async {
    await _openSheet(tester, settings: _savedKeySettings);

    expect(_keyField(), findsOneWidget);
    expect(_field(tester).controller!.text, isEmpty);
    expect(
      _field(tester).decoration!.hintText,
      'Saved on this device',
      reason: 'the key is in secure storage and is never read back',
    );
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);

    // Nothing typed yet, so nothing to reveal: the eye appears with the text.
    await tester.enterText(_keyField(), 'sk-new-key');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('the eye reveals a typed key in the sheet and keeps it', (
    tester,
  ) async {
    await _openSheet(tester, settings: _savedKeySettings);

    await tester.tap(_keyField());
    await tester.pumpAndSettle();
    await tester.enterText(_keyField(), 'sk-test-123456');
    await tester.pumpAndSettle();
    expect(_field(tester).obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(_field(tester).obscureText, isFalse);
    expect(_field(tester).controller!.text, 'sk-test-123456');
    expect(_field(tester).focusNode!.hasFocus, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    expect(_field(tester).obscureText, isTrue);
    expect(_field(tester).controller!.text, 'sk-test-123456');
  });
}
