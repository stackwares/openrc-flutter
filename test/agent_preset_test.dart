import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/models/agent_preset.dart';

void main() {
  test('known host URLs match their preset, trailing slash ignored', () {
    expect(
      presetMatchingBaseUrl('https://api.openai.com/v1')?.id,
      AgentProviderId.openai,
    );
    expect(
      presetMatchingBaseUrl('https://api.openai.com/v1/')?.id,
      AgentProviderId.openai,
    );
    expect(
      presetMatchingBaseUrl('https://openrouter.ai/api/v1')?.id,
      AgentProviderId.openrouter,
    );
    expect(
      presetMatchingBaseUrl('https://api.anthropic.com')?.id,
      AgentProviderId.anthropic,
    );
    expect(
      presetMatchingBaseUrl('https://api.deepseek.com')?.id,
      AgentProviderId.deepseek,
    );
  });

  test('unknown or empty URLs are custom', () {
    expect(presetMatchingBaseUrl(''), isNull);
    expect(presetMatchingBaseUrl('   '), isNull);
    expect(presetMatchingBaseUrl('https://localhost:11434/v1'), isNull);
    expect(presetMatchingBaseUrl('https://api.openai.com'), isNull);
  });
}
