import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';

void main() {
  test('key prefix matches per preset', () {
    expect(
      AgentSettingsNotifier.keyPrefixMatches(
        presetFor(AgentProviderId.openrouter),
        'sk-or-test',
      ),
      isTrue,
    );
    expect(
      AgentSettingsNotifier.keyPrefixMatches(
        presetFor(AgentProviderId.openai),
        'not-a-valid-key',
      ),
      isFalse,
    );
    expect(
      AgentSettingsNotifier.keyPrefixMatches(
        presetFor(AgentProviderId.openai),
        'sk-or-should-not-count-as-openai',
      ),
      isFalse,
    );
    expect(
      AgentSettingsNotifier.keyPrefixMatches(
        presetFor(AgentProviderId.openai),
        'sk-proj-openai',
      ),
      isTrue,
    );
    expect(
      AgentSettingsNotifier.keyPrefixMatches(
        presetFor(AgentProviderId.custom),
        'anything',
      ),
      isTrue,
    );
  });

  test('saved custom URL and model win over a named provider', () {
    const settings = AgentSettings(
      providerId: AgentProviderId.openai,
      model: 'gpt-oss',
      customBaseUrl: 'https://api.openai.com/v1',
      customStyle: AgentApiStyle.openAi,
      useFasterModel: true,
      hasKey: true,
    );
    expect(settings.effectiveBaseUrl, 'https://api.openai.com/v1');
    expect(settings.effectiveModel, 'gpt-oss');
    expect(settings.resolvedPreset.id, AgentProviderId.openai);
  });

  test('empty custom fields fall back to the named preset', () {
    const settings = AgentSettings(
      providerId: AgentProviderId.anthropic,
      model: '',
      customBaseUrl: '',
      customStyle: AgentApiStyle.openAi,
      useFasterModel: true,
      hasKey: false,
    );
    expect(settings.effectiveBaseUrl, 'https://api.anthropic.com');
    expect(settings.effectiveModel, 'claude-haiku-4-5');
    expect(settings.effectiveStyle, AgentApiStyle.anthropic);
    expect(settings.resolvedPreset.id, AgentProviderId.anthropic);
  });

  test('unknown host stays custom and is not relayed on web', () {
    const settings = AgentSettings(
      providerId: AgentProviderId.custom,
      model: 'llama3',
      customBaseUrl: 'https://localhost:11434/v1',
      customStyle: AgentApiStyle.openAi,
      useFasterModel: false,
      hasKey: true,
    );
    expect(settings.resolvedPreset.id, AgentProviderId.custom);
    expect(settings.effectiveModel, 'llama3');
    expect(
      AgentSettingsNotifier.webLlmAvailable(settings, relayHasLlm: true),
      isTrue, // native host; kIsWeb is false in this VM
    );
  });
}
