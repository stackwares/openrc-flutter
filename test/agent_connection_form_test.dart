import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/ask/widgets/agent_connection_form.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/theme/app_theme.dart';

class _SilentSettings extends AgentSettingsNotifier {
  @override
  Future<AgentSettings> build() async => const AgentSettings(
    providerId: AgentProviderId.custom,
    model: '',
    customBaseUrl: '',
    customStyle: AgentApiStyle.openAi,
    useFasterModel: false,
    hasKey: false,
  );
}

void main() {
  Future<void> pumpForm(WidgetTester tester, {required AgentSettings initial}) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentSettingsProvider.overrideWith(_SilentSettings.new),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(
            FlexScheme.indigoM3,
          ).copyWith(splashFactory: InkRipple.splashFactory),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgentConnectionForm(
                initial: initial,
                onSaved: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TextEditingController controllerOf(Key key, WidgetTester tester) {
    return tester.widget<TextField>(find.byKey(key)).controller!;
  }

  testWidgets('choosing a provider prefills its base URL and model', (
    tester,
  ) async {
    await pumpForm(
      tester,
      initial: const AgentSettings(
        providerId: AgentProviderId.custom,
        model: '',
        customBaseUrl: '',
        customStyle: AgentApiStyle.openAi,
        useFasterModel: false,
        hasKey: false,
      ),
    );

    expect(controllerOf(const Key('agent-base-url'), tester).text, isEmpty);
    expect(controllerOf(const Key('agent-model'), tester).text, isEmpty);

    await tester.tap(find.byType(DropdownButtonFormField<AgentProviderId>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI').last);
    await tester.pumpAndSettle();

    expect(
      controllerOf(const Key('agent-base-url'), tester).text,
      'https://api.openai.com/v1',
    );
    expect(controllerOf(const Key('agent-model'), tester).text, 'gpt-4o');
    expect(find.text('OpenAI style'), findsOneWidget);
  });

  testWidgets('a typed custom model is kept when switching providers', (
    tester,
  ) async {
    await pumpForm(
      tester,
      initial: const AgentSettings(
        providerId: AgentProviderId.openai,
        model: 'my-local-llama',
        customBaseUrl: 'https://api.openai.com/v1',
        customStyle: AgentApiStyle.openAi,
        useFasterModel: false,
        hasKey: false,
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<AgentProviderId>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anthropic').last);
    await tester.pumpAndSettle();

    expect(
      controllerOf(const Key('agent-base-url'), tester).text,
      'https://api.anthropic.com',
    );
    expect(
      controllerOf(const Key('agent-model'), tester).text,
      'my-local-llama',
    );
  });

  testWidgets('editing the URL to a known host updates the dropdown', (
    tester,
  ) async {
    await pumpForm(
      tester,
      initial: const AgentSettings(
        providerId: AgentProviderId.custom,
        model: 'deepseek-chat',
        customBaseUrl: '',
        customStyle: AgentApiStyle.openAi,
        useFasterModel: false,
        hasKey: false,
      ),
    );

    await tester.enterText(
      find.byKey(const Key('agent-base-url')),
      'https://api.deepseek.com',
    );
    await tester.pumpAndSettle();

    expect(find.text('DeepSeek'), findsOneWidget);
  });
}
