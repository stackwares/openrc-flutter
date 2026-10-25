import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/app_segmented_control.dart';

/// Custom LLM connection. The provider dropdown only prefills the base URL
/// (and a suggested model / API style). Everything stays editable.
class AgentConnectionForm extends ConsumerStatefulWidget {
  const AgentConnectionForm({
    super.key,
    required this.initial,
    required this.onSaved,
    this.onCancel,
    this.requireConsent = false,
    this.allowRemoveKey = false,
  });

  final AgentSettings initial;
  final VoidCallback onSaved;
  final VoidCallback? onCancel;

  /// First setup: the user ticks that questions go to the provider.
  final bool requireConsent;
  final bool allowRemoveKey;

  @override
  ConsumerState<AgentConnectionForm> createState() =>
      _AgentConnectionFormState();
}

class _AgentConnectionFormState extends ConsumerState<AgentConnectionForm> {
  late AgentProviderId _provider = widget.initial.resolvedPreset.id;
  late AgentApiStyle _customStyle = widget.initial.effectiveStyle;
  late final _url = TextEditingController(
    text: widget.initial.effectiveBaseUrl,
  );
  late final _model = TextEditingController(
    text: widget.initial.effectiveModel,
  );
  final _key = TextEditingController();
  final _keyFocus = FocusNode();
  late var _hasSavedKey = widget.initial.hasKey;
  var _obscure = true;
  var _consent = false;
  var _saving = false;
  var _syncingFromDropdown = false;
  String? _keyError;

  @override
  void initState() {
    super.initState();
    for (final c in [_url, _model, _key]) {
      c.addListener(_onTextChanged);
    }
    _url.addListener(_syncProviderFromUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  /// Flips the key between dots and plain text.
  ///
  /// Native fields toggle in place: the element stays, so focus, the keyboard
  /// and the selection survive and the value is simply repainted. Flutter
  /// web's hidden input goes stale when `obscureText` changes in place and the
  /// field keeps showing dots (flutter/flutter#192102), so the web build swaps
  /// in a fresh field instead and puts the keyboard back on it.
  void _toggleKeyVisibility() {
    if (!kIsWeb) {
      setState(() => _obscure = !_obscure);
      return;
    }
    final focused = _keyFocus.hasFocus;
    setState(() => _obscure = !_obscure);
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyFocus.requestFocus();
    });
  }

  void _syncProviderFromUrl() {
    if (_syncingFromDropdown) return;
    final matched = presetMatchingBaseUrl(_url.text);
    final next = matched?.id ?? AgentProviderId.custom;
    if (next == _provider) return;
    setState(() {
      _provider = next;
      if (matched != null) _customStyle = matched.style;
    });
  }

  AgentPreset get _preset => presetFor(_provider);

  bool get _blockedOnWeb =>
      kIsWeb &&
      (presetMatchingBaseUrl(_url.text) ??
                  (_url.text.trim().isEmpty ? _preset : null))
              ?.relaySlug ==
          null;

  bool get _urlValid {
    final uri = Uri.tryParse(_url.text.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  bool get _canSave =>
      !_saving &&
      !_blockedOnWeb &&
      (_key.text.trim().isNotEmpty || _hasSavedKey) &&
      _urlValid &&
      _model.text.trim().isNotEmpty &&
      (!widget.requireConsent || _consent);

  void _applyPreset(AgentPreset next) {
    _syncingFromDropdown = true;
    final currentModel = _model.text.trim();
    final keepModel =
        currentModel.isNotEmpty && !_isKnownPresetModel(currentModel);
    setState(() {
      _provider = next.id;
      _keyError = null;
      if (next.id != AgentProviderId.custom) {
        _url.text = next.baseUrl;
        _customStyle = next.style;
        if (!keepModel) _model.text = next.recommendedModel;
      }
    });
    _syncingFromDropdown = false;
  }

  bool _isKnownPresetModel(String model) {
    return kAgentPresets.any(
      (p) => p.recommendedModel == model || p.fasterModel == model,
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    _key.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _keyError = null);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final key = _key.text.trim();
    final prefixPreset =
        presetMatchingBaseUrl(_url.text) ??
        (_provider == AgentProviderId.custom
            ? presetFor(AgentProviderId.custom)
            : _preset);
    if (key.isNotEmpty &&
        !AgentSettingsNotifier.keyPrefixMatches(prefixPreset, key)) {
      HapticFeedback.mediumImpact();
      setState(() => _keyError = 'settings.agent.invalidPrefix'.tr());
      return;
    }
    setState(() {
      _saving = true;
      _keyError = null;
    });
    try {
      await ref
          .read(agentSettingsProvider.notifier)
          .saveConnection(
            provider: _provider,
            useFasterModel: false,
            customBaseUrl: _url.text,
            customStyle: _customStyle,
            model: _model.text,
            apiKey: key,
          );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      widget.onSaved();
    } catch (_) {
      if (mounted) setState(() => _keyError = 'agent.errors.generic'.tr());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeKey() async {
    setState(() => _saving = true);
    try {
      await ref.read(agentSettingsProvider.notifier).clearApiKey(_provider);
      if (!mounted) return;
      setState(() => _hasSavedKey = false);
      widget.onSaved();
    } catch (_) {
      if (mounted) setState(() => _keyError = 'agent.errors.generic'.tr());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final disclosure = 'agent.setup.disclosure'.tr(
      namedArgs: {'provider': _preset.nameKey.tr()},
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<AgentProviderId>(
          key: ValueKey<AgentProviderId>(_provider),
          initialValue: _provider,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'settings.agent.provider'.tr(),
            prefixIcon: const Icon(Icons.dns_outlined, size: 20),
          ),
          items: [
            for (final preset in kAgentPresets)
              DropdownMenuItem(
                value: preset.id,
                child: Text(preset.nameKey.tr()),
              ),
          ],
          onChanged: _saving
              ? null
              : (id) {
                  if (id == null) return;
                  _applyPreset(presetFor(id));
                },
        ),
        const SizedBox(height: AppSpace.sm),
        TextField(
          key: const Key('agent-base-url'),
          controller: _url,
          enabled: !_saving,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'settings.agent.customUrl'.tr(),
            hintText: 'https://…',
            prefixIcon: const Icon(Icons.link_rounded, size: 20),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        TextField(
          key: const Key('agent-model'),
          controller: _model,
          enabled: !_saving,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'agent.setup.model'.tr(),
            hintText: _preset.recommendedModel.isEmpty
                ? null
                : _preset.recommendedModel,
            prefixIcon: const Icon(Icons.memory_rounded, size: 20),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        AppSegmentedControl<AgentApiStyle>(
          values: const [AgentApiStyle.openAi, AgentApiStyle.anthropic],
          labels: {
            AgentApiStyle.openAi: 'settings.agent.styleOpenAi'.tr(),
            AgentApiStyle.anthropic: 'settings.agent.styleAnthropic'.tr(),
          },
          groupValue: _customStyle,
          onValueChanged: _saving
              ? null
              : (next) {
                  if (next != null) setState(() => _customStyle = next);
                },
        ),
        if (_blockedOnWeb) ...[
          const SizedBox(height: AppSpace.sm),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.08),
              borderRadius: AppRadius.tileAll,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.public_off_rounded, size: 20, color: scheme.error),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Text(
                      'agent.setup.customWeb'.tr(),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        TextField(
          // Web only: a fresh field is the only way to drop the stale hidden
          // input; see [_toggleKeyVisibility].
          key: kIsWeb ? ValueKey<bool>(_obscure) : null,
          controller: _key,
          focusNode: _keyFocus,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          onChanged: (_) {
            if (_keyError != null) setState(() => _keyError = null);
          },
          decoration: InputDecoration(
            labelText: 'settings.agent.apiKey'.tr(),
            // A saved key is never read back into this field, so say so
            // instead of showing dots that look like a value the eye should
            // reveal.
            hintText: _hasSavedKey
                ? 'settings.agent.savedKey'.tr()
                : _preset.keyPrefix.isEmpty
                ? null
                : '${_preset.keyPrefix}…',
            floatingLabelBehavior: _hasSavedKey
                ? FloatingLabelBehavior.always
                : null,
            errorText: _keyError,
            errorMaxLines: 3,
            prefixIcon: const Icon(Icons.key_rounded, size: 20),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).pasteButtonLabel,
                  icon: const Icon(Icons.content_paste_rounded, size: 20),
                  onPressed: _saving ? null : _paste,
                ),
                // Only once there is something to reveal: with an empty field
                // the eye would flip an icon and show nothing, which reads as
                // a broken button.
                if (_key.text.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: _saving ? null : _toggleKeyVisibility,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        if (widget.requireConsent)
          CheckboxListTile(
            value: _consent,
            onChanged: _saving
                ? null
                : (v) => setState(() => _consent = v ?? false),
            title: Text(disclosure, style: theme.textTheme.bodyMedium),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text(disclosure, style: muted)),
            ],
          ),
        const SizedBox(height: AppSpace.lg),
        FilledButton(
          onPressed: _canSave ? _save : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          child: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('agent.setup.save'.tr()),
        ),
        if (widget.onCancel != null) ...[
          const SizedBox(height: AppSpace.xs),
          TextButton(
            onPressed: _saving ? null : widget.onCancel,
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: Text('settings.cancel'.tr()),
          ),
        ],
        if (widget.allowRemoveKey && _hasSavedKey) ...[
          const SizedBox(height: AppSpace.xs),
          TextButton(
            onPressed: _saving ? null : _removeKey,
            style: TextButton.styleFrom(
              foregroundColor: scheme.error,
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text('settings.agent.clearKey'.tr()),
          ),
        ],
      ],
    );
  }
}
