import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/theme/app_tokens.dart';

/// Provider, model and API key for Ask: the first-run setup in the Ask tab
/// and the sheet in Settings. Nothing is saved until the user taps Save.
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
  late AgentProviderId _provider = widget.initial.providerId;
  late bool _useFaster = widget.initial.useFasterModel;
  late AgentApiStyle _customStyle = widget.initial.customStyle;
  late final _url = TextEditingController(text: widget.initial.customBaseUrl);
  late final _model = TextEditingController(
    text: widget.initial.providerId == AgentProviderId.custom
        ? widget.initial.model
        : '',
  );
  final _key = TextEditingController();
  late var _withKeys = {
    if (widget.initial.hasKey) widget.initial.providerId,
  };
  var _obscure = true;
  var _consent = false;
  var _saving = false;
  String? _keyError;

  @override
  void initState() {
    super.initState();
    for (final c in [_url, _model, _key]) {
      c.addListener(_onTextChanged);
    }
    _loadSavedKeys();
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _loadSavedKeys() async {
    final ids = await ref.read(agentSettingsProvider.notifier).providersWithKeys();
    if (mounted) setState(() => _withKeys = {..._withKeys, ...ids});
  }

  void _onTextChanged() => setState(() {});

  bool get _custom => _provider == AgentProviderId.custom;
  bool get _blockedOnWeb => kIsWeb && _custom;
  bool get _hasSavedKey => _withKeys.contains(_provider);

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
      (!_custom || (_urlValid && _model.text.trim().isNotEmpty)) &&
      (!widget.requireConsent || _consent);

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
    if (key.isNotEmpty &&
        !AgentSettingsNotifier.keyPrefixMatches(presetFor(_provider), key)) {
      HapticFeedback.mediumImpact();
      setState(() => _keyError = 'settings.agent.invalidPrefix'.tr());
      return;
    }
    setState(() {
      _saving = true;
      _keyError = null;
    });
    try {
      await ref.read(agentSettingsProvider.notifier).saveConnection(
            provider: _provider,
            useFasterModel: _useFaster,
            customBaseUrl: _url.text,
            customStyle: _customStyle,
            model: _model.text,
            apiKey: key,
          );
      // The Ask tab swaps this form for the thread once a key exists.
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
      setState(() => _withKeys = {..._withKeys}..remove(_provider));
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
    final preset = presetFor(_provider);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final disclosure = 'agent.setup.disclosure'.tr(
      namedArgs: {'provider': preset.nameKey.tr()},
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionLabel('agent.setup.chooseProvider'.tr()),
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            for (final p in kAgentPresets)
              ChoiceChip(
                label: Text(p.nameKey.tr()),
                // Providers with a saved key switch without retyping it.
                avatar: _withKeys.contains(p.id) && _provider != p.id
                    ? const Icon(Icons.key_rounded, size: 16)
                    : null,
                selected: _provider == p.id,
                onSelected: _saving
                    ? null
                    : (_) => setState(() {
                          _provider = p.id;
                          _keyError = null;
                        }),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        if (_custom)
          ..._customFields(theme)
        else ...[
          _SectionLabel('agent.setup.model'.tr()),
          if (preset.recommendedModel != preset.fasterModel) ...[
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text('settings.agent.recommended'.tr()),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('settings.agent.faster'.tr()),
                ),
              ],
              selected: {_useFaster},
              onSelectionChanged: _saving
                  ? null
                  : (next) => setState(() => _useFaster = next.first),
            ),
            const SizedBox(height: AppSpace.xs),
          ],
          Text(
            _useFaster ? preset.fasterModel : preset.recommendedModel,
            style: muted,
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        TextField(
          controller: _key,
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
            hintText: _hasSavedKey
                ? '••••••••••••'
                : preset.keyPrefix.isEmpty
                ? null
                : '${preset.keyPrefix}…',
            floatingLabelBehavior:
                _hasSavedKey ? FloatingLabelBehavior.always : null,
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
                IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
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

  List<Widget> _customFields(ThemeData theme) {
    if (_blockedOnWeb) {
      return [
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.error.withValues(alpha: 0.08),
            borderRadius: AppRadius.tileAll,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.public_off_rounded,
                  size: 20,
                  color: theme.colorScheme.error,
                ),
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
      ];
    }
    return [
      TextField(
        controller: _url,
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
        controller: _model,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: 'agent.setup.model'.tr(),
          prefixIcon: const Icon(Icons.memory_rounded, size: 20),
        ),
      ),
      const SizedBox(height: AppSpace.sm),
      SegmentedButton<AgentApiStyle>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: AgentApiStyle.openAi,
            label: Text('settings.agent.styleOpenAi'.tr()),
          ),
          ButtonSegment(
            value: AgentApiStyle.anthropic,
            label: Text('settings.agent.styleAnthropic'.tr()),
          ),
        ],
        selected: {_customStyle},
        onSelectionChanged: _saving
            ? null
            : (next) => setState(() => _customStyle = next.first),
      ),
    ];
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
