import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefProvider = 'agent_provider_id';
const _prefModel = 'agent_model';
const _prefCustomUrl = 'agent_custom_base_url';
const _prefCustomStyle = 'agent_custom_api_style';
const _prefUseFasterModel = 'agent_use_faster_model';

final agentSettingsProvider =
    AsyncNotifierProvider<AgentSettingsNotifier, AgentSettings>(
  AgentSettingsNotifier.new,
);

class AgentSettings {
  const AgentSettings({
    required this.providerId,
    required this.model,
    required this.customBaseUrl,
    required this.customStyle,
    required this.useFasterModel,
    required this.hasKey,
  });

  final AgentProviderId providerId;
  final String model;
  final String customBaseUrl;
  final AgentApiStyle customStyle;
  final bool useFasterModel;
  final bool hasKey;

  AgentPreset get preset => presetFor(providerId);

  String get effectiveBaseUrl =>
      providerId == AgentProviderId.custom ? customBaseUrl.trim() : preset.baseUrl;

  /// Custom hosts name their own model; presets pick one of theirs, so a
  /// custom model name never follows the user to another provider.
  String get effectiveModel {
    if (providerId == AgentProviderId.custom) return model.trim();
    final p = preset;
    return useFasterModel ? p.fasterModel : p.recommendedModel;
  }

  /// `OpenRouter · openai/gpt-4o`, or just the provider when no model is set.
  String get displayName {
    final name = preset.nameKey.tr();
    final model = effectiveModel;
    return model.isEmpty ? name : '$name · $model';
  }

  AgentApiStyle get effectiveStyle =>
      providerId == AgentProviderId.custom ? customStyle : preset.style;
}

class AgentSettingsNotifier extends AsyncNotifier<AgentSettings> {
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<AgentSettings> build() => _load();

  Future<AgentSettings> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final providerName = prefs.getString(_prefProvider) ?? AgentProviderId.openrouter.name;
    final providerId = AgentProviderId.values.firstWhere(
      (id) => id.name == providerName,
      orElse: () => AgentProviderId.openrouter,
    );
    final preset = presetFor(providerId);
    final key = await _storage.read(key: preset.secureStorageKey);
    return AgentSettings(
      providerId: providerId,
      model: prefs.getString(_prefModel) ?? '',
      customBaseUrl: prefs.getString(_prefCustomUrl) ?? '',
      customStyle: AgentApiStyle.values.firstWhere(
        (s) => s.name == (prefs.getString(_prefCustomStyle) ?? AgentApiStyle.openAi.name),
        orElse: () => AgentApiStyle.openAi,
      ),
      useFasterModel: prefs.getBool(_prefUseFasterModel) ?? false,
      hasKey: key != null && key.trim().isNotEmpty,
    );
  }

  /// Removes the key for [providerId], or for the selected provider.
  Future<void> clearApiKey([AgentProviderId? providerId]) async {
    final id = providerId ?? (await future).providerId;
    await _storage.delete(key: presetFor(id).secureStorageKey);
    ref.invalidateSelf();
    await future;
  }

  /// Saves the whole connection at once, so listeners rebuild one time.
  /// A null or empty [apiKey] keeps the key already saved for [provider].
  Future<void> saveConnection({
    required AgentProviderId provider,
    required bool useFasterModel,
    String customBaseUrl = '',
    AgentApiStyle customStyle = AgentApiStyle.openAi,
    String model = '',
    String? apiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final custom = provider == AgentProviderId.custom;
    await prefs.setString(_prefProvider, provider.name);
    await prefs.setBool(_prefUseFasterModel, useFasterModel);
    await prefs.setString(_prefModel, custom ? model.trim() : '');
    if (custom) {
      await prefs.setString(_prefCustomUrl, customBaseUrl.trim());
      await prefs.setString(_prefCustomStyle, customStyle.name);
    }
    final key = apiKey?.trim() ?? '';
    if (key.isNotEmpty) {
      await _storage.write(key: presetFor(provider).secureStorageKey, value: key);
    }
    ref.invalidateSelf();
    await future;
  }

  Future<String?> readApiKey(AgentProviderId providerId) =>
      _storage.read(key: presetFor(providerId).secureStorageKey);

  /// Providers that already have a key on this device.
  Future<Set<AgentProviderId>> providersWithKeys() async {
    final out = <AgentProviderId>{};
    for (final id in AgentProviderId.values) {
      try {
        final key = await readApiKey(id);
        if (key != null && key.trim().isNotEmpty) out.add(id);
      } catch (_) {}
    }
    return out;
  }

  /// Soft prefix check; custom allows any non-empty key.
  /// `sk-` presets reject OpenRouter / Anthropic prefixes.
  static bool keyPrefixMatches(AgentPreset preset, String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return false;
    if (preset.id == AgentProviderId.custom || preset.keyPrefix.isEmpty) {
      return true;
    }
    if (preset.keyPrefix == 'sk-') {
      return trimmed.startsWith('sk-') &&
          !trimmed.startsWith('sk-or-') &&
          !trimmed.startsWith('sk-ant-');
    }
    return trimmed.startsWith(preset.keyPrefix);
  }

  /// Web custom providers need a self-hosted relay; hosted worker is allowlisted only.
  static bool webLlmAvailable(AgentSettings settings, {required bool relayHasLlm}) {
    if (!kIsWeb) return true;
    if (settings.providerId == AgentProviderId.custom) return false;
    return relayHasLlm && settings.preset.relaySlug != null;
  }
}
