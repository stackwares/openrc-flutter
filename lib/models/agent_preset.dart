enum AgentApiStyle { openAi, anthropic }

enum AgentProviderId { openrouter, openai, anthropic, deepseek, custom }

/// URL / model / style prefill for the custom connection form.
class AgentPreset {
  const AgentPreset({
    required this.id,
    required this.nameKey,
    required this.baseUrl,
    required this.style,
    required this.recommendedModel,
    required this.fasterModel,
    required this.keyPrefix,
    this.relaySlug,
  });

  final AgentProviderId id;
  final String nameKey;
  final String baseUrl;
  final AgentApiStyle style;
  final String recommendedModel;
  final String fasterModel;

  /// Expected key prefix for soft validation (empty = any).
  final String keyPrefix;

  /// Hosted relay segment; null for custom-only native.
  final String? relaySlug;

  String get secureStorageKey => 'agent_key_${id.name}';
}

const kAgentPresets = <AgentPreset>[
  AgentPreset(
    id: AgentProviderId.openrouter,
    nameKey: 'settings.agent.providers.openrouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    style: AgentApiStyle.openAi,
    recommendedModel: 'deepseek/deepseek-v4.1-flash',
    fasterModel: 'openai/gpt-4o-mini',
    keyPrefix: 'sk-or-',
    relaySlug: 'openrouter',
  ),
  AgentPreset(
    id: AgentProviderId.openai,
    nameKey: 'settings.agent.providers.openai',
    baseUrl: 'https://api.openai.com/v1',
    style: AgentApiStyle.openAi,
    recommendedModel: 'gpt-4o',
    fasterModel: 'gpt-4o-mini',
    keyPrefix: 'sk-',
    relaySlug: 'openai',
  ),
  AgentPreset(
    id: AgentProviderId.anthropic,
    nameKey: 'settings.agent.providers.anthropic',
    baseUrl: 'https://api.anthropic.com',
    style: AgentApiStyle.anthropic,
    recommendedModel: 'claude-sonnet-4-5',
    fasterModel: 'claude-haiku-4-5',
    keyPrefix: 'sk-ant-',
    relaySlug: 'anthropic',
  ),
  AgentPreset(
    id: AgentProviderId.deepseek,
    nameKey: 'settings.agent.providers.deepseek',
    baseUrl: 'https://api.deepseek.com',
    style: AgentApiStyle.openAi,
    recommendedModel: 'deepseek-chat',
    fasterModel: 'deepseek-chat',
    keyPrefix: 'sk-',
    relaySlug: 'deepseek',
  ),
  AgentPreset(
    id: AgentProviderId.custom,
    nameKey: 'settings.agent.providers.custom',
    baseUrl: '',
    style: AgentApiStyle.openAi,
    recommendedModel: '',
    fasterModel: '',
    keyPrefix: '',
    relaySlug: null,
  ),
];

AgentPreset presetFor(AgentProviderId id) =>
    kAgentPresets.firstWhere((p) => p.id == id);

/// Known hosts only — the dropdown's Custom row is not a URL match.
Iterable<AgentPreset> get kKnownAgentPresets =>
    kAgentPresets.where((p) => p.id != AgentProviderId.custom);

String normalizeAgentBaseUrl(String url) {
  var value = url.trim();
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value.toLowerCase();
}

/// Exact host match after trim / trailing slash. Unknown URLs are custom.
AgentPreset? presetMatchingBaseUrl(String url) {
  final normalized = normalizeAgentBaseUrl(url);
  if (normalized.isEmpty) return null;
  for (final preset in kKnownAgentPresets) {
    if (normalizeAgentBaseUrl(preset.baseUrl) == normalized) return preset;
  }
  return null;
}
