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
}
