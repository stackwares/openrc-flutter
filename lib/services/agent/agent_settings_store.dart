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

  /// Named-provider leftovers fall back to that preset until URL/model
  /// are saved as a custom connection.
  String get effectiveBaseUrl {
    final url = customBaseUrl.trim();
    if (url.isNotEmpty) return url;
    if (providerId != AgentProviderId.custom) return preset.baseUrl;
    return '';
  }

  String get effectiveModel {
    final value = model.trim();
    if (value.isNotEmpty) return value;
    if (providerId != AgentProviderId.custom) {
      return useFasterModel ? preset.fasterModel : preset.recommendedModel;
    }
    return '';
  }

  AgentApiStyle get effectiveStyle {
    if (customBaseUrl.trim().isNotEmpty) return customStyle;
    if (providerId != AgentProviderId.custom) return preset.style;
    return customStyle;
  }

  /// Preset whose base URL matches, else the stored dropdown id.
  AgentPreset get resolvedPreset =>
      presetMatchingBaseUrl(effectiveBaseUrl) ?? preset;

  /// `OpenRouter · openai/gpt-4o`, or just the provider when no model is set.
  String get displayName {
    final name = resolvedPreset.nameKey.tr();
    final model = effectiveModel;
    return model.isEmpty ? name : '$name · $model';
  }
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
    final useFasterModel = prefs.getBool(_prefUseFasterModel) ?? false;
    var model = prefs.getString(_prefModel) ?? '';
    var customBaseUrl = prefs.getString(_prefCustomUrl) ?? '';
    var styleName = prefs.getString(_prefCustomStyle);
    if (providerId != AgentProviderId.custom) {
      final preset = presetFor(providerId);
      var migrated = false;
      if (customBaseUrl.trim().isEmpty) {
        customBaseUrl = preset.baseUrl;
        migrated = true;
      }
      if (model.trim().isEmpty) {
        model = useFasterModel ? preset.fasterModel : preset.recommendedModel;
        migrated = true;
      }
      styleName ??= preset.style.name;
      if (migrated) {
        await prefs.setString(_prefCustomUrl, customBaseUrl);
        await prefs.setString(_prefModel, model);
        await prefs.setString(_prefCustomStyle, styleName);
      }
    }
    final customStyle = AgentApiStyle.values.firstWhere(
      (s) => s.name == (styleName ?? AgentApiStyle.openAi.name),
      orElse: () => AgentApiStyle.openAi,
    );
    final hasKey = await _hasStoredKey(providerId);
    return AgentSettings(
      providerId: providerId,
      model: model,
      customBaseUrl: customBaseUrl,
      customStyle: customStyle,
      useFasterModel: useFasterModel,
      hasKey: hasKey,
    );
  }

  Future<bool> _hasStoredKey(AgentProviderId providerId) async {
    for (final id in {AgentProviderId.custom, providerId}) {
      try {
        final key = await _storage.read(key: presetFor(id).secureStorageKey);
        if (key != null && key.trim().isNotEmpty) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Removes the key for [providerId], the custom slot, and the current
  /// resolved host so leftover named-provider keys cannot come back.
  Future<void> clearApiKey([AgentProviderId? providerId]) async {
    final settings = await future;
    final ids = {
      AgentProviderId.custom,
      settings.providerId,
      settings.resolvedPreset.id,
      ?providerId,
    };
    for (final id in ids) {
      await _storage.delete(key: presetFor(id).secureStorageKey);
    }
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
    await prefs.setString(_prefProvider, provider.name);
    await prefs.setBool(_prefUseFasterModel, useFasterModel);
    await prefs.setString(_prefModel, model.trim());
    await prefs.setString(_prefCustomUrl, customBaseUrl.trim());
    await prefs.setString(_prefCustomStyle, customStyle.name);
    final key = apiKey?.trim() ?? '';
    if (key.isNotEmpty) {
      await _storage.write(
        key: presetFor(AgentProviderId.custom).secureStorageKey,
        value: key,
      );
      if (provider != AgentProviderId.custom) {
        await _storage.write(key: presetFor(provider).secureStorageKey, value: key);
      }
    }
    ref.invalidateSelf();
    await future;
  }

  Future<String?> readApiKey(AgentProviderId providerId) async {
    for (final id in {AgentProviderId.custom, providerId}) {
      try {
        final key = await _storage.read(key: presetFor(id).secureStorageKey);
        if (key != null && key.trim().isNotEmpty) return key;
      } catch (_) {}
    }
    return null;
  }

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

  /// Web only forwards known hosts through the relay. Unknown URLs stay native-only.
  static bool webLlmAvailable(AgentSettings settings, {required bool relayHasLlm}) {
    if (!kIsWeb) return true;
    return relayHasLlm && settings.resolvedPreset.relaySlug != null;
  }
}
