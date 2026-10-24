import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/product_label_suggest.dart';
import 'package:openrc/features/onboarding/onboarding_steps.dart';
import 'package:openrc/features/settings/product_inventory.dart';
import 'package:openrc/features/settings/widgets/agent_settings_section.dart';
import 'package:openrc/models/product_labels.dart';
import 'package:openrc/services/agent/agent_llm_client.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/services/agent/product_label_suggester.dart';
import 'package:openrc/services/onboarding_prefs_store.dart';
import 'package:openrc/services/product_labels_store.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/app_state_message.dart';
import 'package:openrc/widgets/search_field_decoration.dart';
import 'package:openrc/widgets/section_header.dart';

/// Names the store product ids seen in the loaded transactions, per app.
///
/// Names are labels only: revenue, counts, filters and notifications keep
/// using the raw id. Everything here stays on the device.
class ProductNamesScreen extends ConsumerStatefulWidget {
  const ProductNamesScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ProductNamesScreen());

  @override
  ConsumerState<ProductNamesScreen> createState() => _ProductNamesScreenState();
}

enum _SuggestMode { ai, local, connect }

class _ProductNamesScreenState extends ConsumerState<ProductNamesScreen> {
  final _search = TextEditingController();

  /// Suggestions not applied yet, keyed by [ProductUsage.key].
  final _suggestions = <String, ProductLabelSuggestion>{};

  String _query = '';
  bool _running = false;
  int _done = 0;
  int _total = 0;
  CancelToken? _cancel;

  @override
  void dispose() {
    _cancel?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(productInventoryProvider);
    final labels = ref.watch(productLabelsProvider);
    final visible = _filtered(inventory, labels);

    return Scaffold(
      appBar: AppBar(
        title: Text('products.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'products.aiTitle'.tr(),
            icon: const Icon(Icons.auto_awesome_rounded),
            onPressed: inventory.isEmpty || _running
                ? null
                : () => _openSuggestions(inventory),
          ),
        ],
      ),
      body: inventory.isEmpty
          ? AppStateMessage(
              icon: Icons.sell_outlined,
              title: 'products.emptyTitle'.tr(),
              message: 'products.emptyBody'.tr(),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.xs,
                AppSpace.gutter,
                AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                _intro(context),
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: searchFieldDecoration(
                    context.colorScheme,
                    'products.search'.tr(),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                if (_running) _progressCard(context),
                if (_suggestions.isNotEmpty) _applyAllCard(context, inventory),
                for (final entry in visible.entries) ...[
                  SectionHeader(
                    title: entry.value.first.appLabel,
                    count: 'products.count'.plural(entry.value.length),
                    trailing: labels.forApp(entry.key).isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'products.clear'.tr(),
                            icon: const Icon(Icons.delete_sweep_outlined),
                            onPressed: () => _clearApp(
                              entry.key,
                              entry.value.first.appLabel,
                            ),
                          ),
                  ),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < entry.value.length; i++) ...[
                          if (i > 0) const Divider(height: 1, indent: 56),
                          _ProductRow(
                            usage: entry.value[i],
                            label: labels.forApp(entry.key),
                            suggestion: _suggestions[entry.value[i].key],
                            onTap: () => _editProduct(entry.value[i]),
                            onAccept: () => _applySuggestion(entry.value[i]),
                            onDismiss: () => setState(
                              () => _suggestions.remove(entry.value[i].key),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _intro(BuildContext context) {
    final scheme = context.colorScheme;
    return Text(
      'products.intro'.tr(),
      style: context.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.35,
      ),
    );
  }

  Widget _progressCard(BuildContext context) {
    final scheme = context.colorScheme;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'products.aiProgress'.tr(
              namedArgs: {'done': '$_done', 'total': '$_total'},
            ),
            style: context.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpace.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _total == 0 ? null : _done / _total,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _cancel?.cancel(),
              child: Text('products.stop'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _applyAllCard(BuildContext context, ProductInventory inventory) {
    final count = _suggestions.length;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 20),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  'products.suggestionsReady'.plural(count),
                  style: context.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpace.xs,
            children: [
              TextButton(
                onPressed: () => setState(_suggestions.clear),
                child: Text('products.dismiss'.tr()),
              ),
              FilledButton(
                onPressed: () => _applyAll(inventory),
                child: Text('products.applyAll'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Map<String, List<ProductUsage>> _filtered(
    ProductInventory inventory,
    ProductLabels labels,
  ) {
    final query = _query.trim().toLowerCase();
    final out = <String, List<ProductUsage>>{};
    for (final usage in inventory.products) {
      final name = labels.displayName(usage.appKey, usage.productId) ?? '';
      final matches =
          query.isEmpty ||
          usage.productId.toLowerCase().contains(query) ||
          name.toLowerCase().contains(query) ||
          usage.appLabel.toLowerCase().contains(query) ||
          (_suggestions[usage.key]?.name?.toLowerCase().contains(query) ??
              false);
      if (!matches) continue;
      out.putIfAbsent(usage.appKey, () => []).add(usage);
    }
    return out;
  }

  Future<void> _editProduct(ProductUsage usage) async {
    UtilitiesService.hapticSelection();
    await showAdaptiveSheet<void>(
      context: context,
      builder: (_) =>
          _ProductEditSheet(usage: usage, suggestion: _suggestions[usage.key]),
    );
    if (!mounted) return;
    // A saved name makes its suggestion moot; just closing keeps it.
    final named = ref
        .read(productLabelsProvider)
        .displayName(usage.appKey, usage.productId);
    if (named != null && _suggestions.containsKey(usage.key)) {
      setState(() => _suggestions.remove(usage.key));
    }
  }

  Future<void> _applySuggestion(ProductUsage usage) async {
    final suggestion = _suggestions[usage.key];
    if (suggestion == null) return;
    await ref.read(productLabelsProvider.notifier).applyUpdates(usage.appKey, {
      usage.productId: ProductLabelUpdate(
        name: suggestion.name,
        planName: suggestion.plan,
      ),
    });
    if (!mounted) return;
    setState(() => _suggestions.remove(usage.key));
    _snackApplied(1);
  }

  Future<void> _applyAll(ProductInventory inventory) async {
    final byApp = <String, Map<String, ProductLabelUpdate>>{};
    for (final usage in inventory.products) {
      final suggestion = _suggestions[usage.key];
      if (suggestion == null) continue;
      byApp.putIfAbsent(usage.appKey, () => {})[usage.productId] =
          ProductLabelUpdate(name: suggestion.name, planName: suggestion.plan);
    }
    if (byApp.isEmpty) return;
    final count = _suggestions.length;
    await ref.read(productLabelsProvider.notifier).applyAll(byApp);
    if (!mounted) return;
    setState(_suggestions.clear);
    _snackApplied(count);
  }

  void _snackApplied(int count) {
    UtilitiesService.hapticLight();
    context.showSnackBar(
      'products.applied'.plural(count),
      actionLabel: 'products.undo'.tr(),
      onAction: () => ref.read(productLabelsProvider.notifier).undo(),
    );
  }

  Future<void> _clearApp(String appKey, String appLabel) async {
    final confirmed = await showAdaptiveForm<bool>(
      context: context,
      title: 'products.clearTitle'.tr(namedArgs: {'app': appLabel}),
      content: (_) => Text('products.clearBody'.tr()),
      actions: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text('products.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text('products.clear'.tr()),
        ),
      ],
    );
    if (confirmed != true) return;
    await ref.read(productLabelsProvider.notifier).clearApp(appKey);
  }

  Future<void> _openSuggestions(ProductInventory inventory) async {
    final settings = await ref.read(agentSettingsProvider.future);
    if (!mounted) return;
    final consentOk =
        !isAppleAiConsentPlatform ||
        ref.read(onboardingPrefsProvider).aiConsentGranted;
    final hasKey = settings.hasKey;
    final labels = ref.read(productLabelsProvider);
    final count = inventory.products
        .where((p) => labels.displayName(p.appKey, p.productId) == null)
        .take(kProductLabelSuggestionMax)
        .length;
    if (count == 0) {
      context.showSnackBar('products.allNamed'.tr());
      return;
    }

    final choice = await showAdaptiveSheet<_SuggestMode>(
      context: context,
      builder: (_) => _SuggestSheet(
        settings: settings,
        hasKey: hasKey,
        consentOk: consentOk,
        count: count,
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _SuggestMode.connect) {
      await showAgentSettingsSheet(context);
      return;
    }
    await _runSuggestions(inventory, mode: choice);
  }

  Future<void> _runSuggestions(
    ProductInventory inventory, {
    required _SuggestMode mode,
  }) async {
    final labels = ref.read(productLabelsProvider);
    final targets = [
      for (final usage in inventory.products)
        if (labels.displayName(usage.appKey, usage.productId) == null) usage,
    ].take(kProductLabelSuggestionMax).toList();
    if (targets.isEmpty) return;

    final ids = targets.map((t) => t.productId);
    setState(() {
      _running = true;
      _done = 0;
      _total = targets.length;
      _cancel = CancelToken();
    });
    try {
      final suggestions = mode == _SuggestMode.ai
          ? await ref
                .read(productLabelSuggesterProvider)
                .suggest(
                  productIds: ids,
                  cancelToken: _cancel!,
                  onProgress: (done, total) {
                    if (!mounted) return;
                    setState(() {
                      _done = done;
                      _total = total;
                    });
                  },
                )
          : ProductLabelSuggester.local(ids);
      if (!mounted) return;
      final byId = {for (final s in suggestions) s.productId: s};
      final next = <String, ProductLabelSuggestion>{};
      for (final usage in targets) {
        final suggestion = byId[usage.productId];
        if (suggestion == null) continue;
        if (suggestion.name == null && suggestion.plan == null) continue;
        next[usage.key] = suggestion;
      }
      setState(() {
        _suggestions
          ..clear()
          ..addAll(next);
      });
      if (next.isEmpty) context.showSnackBar('products.aiNothing'.tr());
    } on AgentLlmException catch (e) {
      if (!mounted) return;
      if (e.messageKey != 'agent.errors.stopped') {
        context.showSnackBar(e.messageKey.tr(), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _cancel = null;
        });
      }
    }
  }
}


/// How to name the products: with the connected model, with the parser, or
/// by connecting a model first.
class _SuggestSheet extends StatelessWidget {
  const _SuggestSheet({
    required this.settings,
    required this.hasKey,
    required this.consentOk,
    required this.count,
  });

  final AgentSettings settings;
  final bool hasKey;
  final bool consentOk;
  final int count;

  bool get _aiReady => hasKey && consentOk;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xxs,
        AppSpace.lg,
        AppSpace.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetBadge(),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'products.suggestTitle'.tr(),
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'products.suggestSubtitle'.plural(count),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          if (_aiReady)
            _OptionCard(
              icon: Icons.auto_awesome_rounded,
              title: 'products.suggestAi'.tr(),
              body: settings.displayName,
              footnote: 'products.aiPrivacyBody'.tr(),
              highlighted: true,
              onTap: () => Navigator.pop(context, _SuggestMode.ai),
            )
          else if (!hasKey)
            _OptionCard(
              icon: Icons.key_rounded,
              title: 'products.connectModel'.tr(),
              body: 'products.aiNoKeyBody'.tr(),
              highlighted: true,
              onTap: () => Navigator.pop(context, _SuggestMode.connect),
            )
          else
            _UnavailableCard(text: 'products.aiConsentBody'.tr()),
          const SizedBox(height: AppSpace.sm),
          _OptionCard(
            icon: Icons.text_fields_rounded,
            title: 'products.useParser'.tr(),
            body: 'products.parserNote'.tr(),
            pill: 'products.offlineBadge'.tr(),
            onTap: () => Navigator.pop(context, _SuggestMode.local),
          ),
          const SizedBox(height: AppSpace.md),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('products.cancel'.tr()),
          ),
        ],
      ),
    );
  }
}

/// Sparkle tile beside the sheet title.
class _SheetBadge extends StatelessWidget {
  const _SheetBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.auto_awesome_rounded,
        size: 21,
        color: scheme.primary,
      ),
    );
  }
}

/// One way to name the products: the whole card is the button.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    this.body,
    this.footnote,
    this.pill,
    this.highlighted = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? body;

  /// Fine print under a hairline, e.g. what leaves the device.
  final String? footnote;
  final String? pill;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final text = context.textTheme;
    final accent = highlighted ? scheme.primary : null;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
      side: BorderSide(
        color: accent?.withValues(alpha: 0.45) ?? context.appColors.hairline,
        width: highlighted ? 1.5 : 1,
      ),
    );

    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: accent?.withValues(alpha: 0.06) ?? scheme.surfaceContainerLow,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent?.withValues(alpha: 0.14) ??
                        scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 18,
                    color: accent ?? scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (pill != null) ...[
                            const SizedBox(width: AppSpace.xs),
                            _Pill(pill!),
                          ],
                        ],
                      ),
                      if (body != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          body!,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                      if (footnote != null) ...[
                        const SizedBox(height: AppSpace.xs),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.lock_outline_rounded,
                                size: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                footnote!,
                                style: text.bodySmall?.copyWith(
                                  fontSize: 11.5,
                                  color: scheme.onSurfaceVariant,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 6, start: 2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: accent ?? scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The model is connected but AI is off for this app: say why, no button.
class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: context.appColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'products.suggestAi'.tr(),
                  style: context.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small rounded label on an option, e.g. `Offline`.
class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: context.textTheme.labelSmall?.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.usage,
    required this.label,
    required this.suggestion,
    required this.onTap,
    required this.onAccept,
    required this.onDismiss,
  });

  final ProductUsage usage;
  final AppProductLabels label;
  final ProductLabelSuggestion? suggestion;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final text = context.textTheme;
    final suggestion = this.suggestion;
    final name = label.nameOf(usage.productId);
    final shown = suggestion?.name ?? name ?? usage.productId;
    final planned = label.planName(label.planIdOf(usage.productId));
    final planName = suggestion?.plan ?? planned;
    // A plan named after the product itself would just repeat the title.
    final showPlan = planName != null && planName != shown;

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 62),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Icon(
                suggestion != null
                    ? Icons.auto_awesome_rounded
                    : Icons.sell_outlined,
                size: 18,
                color: suggestion != null
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      shown,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: suggestion != null && name == null
                            ? scheme.primary
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        usage.productId,
                        'products.sales'.plural(usage.sales),
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: AppText.tabular,
                      ),
                    ),
                  ],
                ),
              ),
              if (suggestion != null) ...[
                IconButton(
                  tooltip: 'products.accept'.tr(),
                  icon: const Icon(Icons.check_rounded),
                  onPressed: onAccept,
                ),
                IconButton(
                  tooltip: 'products.dismiss'.tr(),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onDismiss,
                ),
              ] else ...[
                if (showPlan)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Chip(
                        label: Text(
                          planName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                  ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Name and plan for one product, plus plan management for the app.
class _ProductEditSheet extends ConsumerStatefulWidget {
  const _ProductEditSheet({required this.usage, this.suggestion});

  final ProductUsage usage;
  final ProductLabelSuggestion? suggestion;

  @override
  ConsumerState<_ProductEditSheet> createState() => _ProductEditSheetState();
}

class _ProductEditSheetState extends ConsumerState<_ProductEditSheet> {
  late final TextEditingController _name;
  final _planName = TextEditingController();

  String? _planId;
  bool _newPlan = false;

  @override
  void initState() {
    super.initState();
    final app = ref.read(productLabelsProvider).forApp(widget.usage.appKey);
    final suggestion = widget.suggestion;
    _name = TextEditingController(
      text: app.nameOf(widget.usage.productId) ?? suggestion?.name ?? '',
    );
    _planId = app.planIdOf(widget.usage.productId);
    final suggestedPlan = suggestion?.plan;
    if (suggestedPlan != null && _planId == null) {
      final existing = app.planIdForName(suggestedPlan);
      if (existing == null) {
        _newPlan = true;
        _planName.text = suggestedPlan;
      } else {
        _planId = existing;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _planName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(
      productLabelsProvider.select((l) => l.forApp(widget.usage.appKey)),
    );
    final scheme = context.colorScheme;
    final selectedPlan = _newPlan || _planId == null
        ? null
        : app.plans[_planId];

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xxs,
        AppSpace.lg,
        AppSpace.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'products.editTitle'.tr(),
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.usage.productId,
            style: context.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: AppText.tabular,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: kProductLabelMaxChars,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'products.nameLabel'.tr(),
              hintText: 'products.nameHint'.tr(),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'products.planLabel'.tr(),
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              ChoiceChip(
                label: Text('products.planNone'.tr()),
                selected: _planId == null && !_newPlan,
                onSelected: (_) => setState(() {
                  _planId = null;
                  _newPlan = false;
                }),
              ),
              for (final plan in app.plans.values)
                ChoiceChip(
                  label: Text(plan.name),
                  selected: _planId == plan.id && !_newPlan,
                  onSelected: (_) => setState(() {
                    _planId = plan.id;
                    _newPlan = false;
                  }),
                ),
              ChoiceChip(
                label: Text('products.planNew'.tr()),
                selected: _newPlan,
                onSelected: (_) => setState(() => _newPlan = true),
              ),
            ],
          ),
          if (selectedPlan != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                children: [
                  TextButton(
                    onPressed: () =>
                        _editPlan(selectedPlan.id, selectedPlan.name),
                    child: Text('products.renamePlanTitle'.tr()),
                  ),
                  TextButton(
                    onPressed: () => _deletePlan(selectedPlan.id),
                    child: Text('products.deletePlan'.tr()),
                  ),
                ],
              ),
            ),
          if (_newPlan) ...[
            const SizedBox(height: AppSpace.xs),
            TextField(
              controller: _planName,
              maxLength: kProductLabelMaxChars,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'products.planLabel'.tr(),
                hintText: 'products.planNameHint'.tr(),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              TextButton(onPressed: _reset, child: Text('products.reset'.tr())),
              const Spacer(),
              FilledButton(onPressed: _save, child: Text('products.save'.tr())),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final planName = _newPlan
        ? _planName.text.trim()
        : _planId == null
        ? ''
        : _planNameFor(_planId!);
    await ref
        .read(productLabelsProvider.notifier)
        .applyUpdates(widget.usage.appKey, {
          widget.usage.productId: ProductLabelUpdate(
            name: _name.text,
            planName: planName,
          ),
        });
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reset() async {
    await ref.read(productLabelsProvider.notifier).applyUpdates(
      widget.usage.appKey,
      {
        widget.usage.productId: const ProductLabelUpdate(
          name: '',
          planName: '',
        ),
      },
    );
    if (mounted) Navigator.pop(context);
  }

  String _planNameFor(String planId) {
    final app = ref.read(productLabelsProvider).forApp(widget.usage.appKey);
    return app.plans[planId]?.name ?? '';
  }

  Future<void> _editPlan(String planId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    try {
      final result = await showAdaptiveForm<String>(
        context: context,
        title: 'products.renamePlanTitle'.tr(),
        content: (_) => TextField(
          controller: controller,
          autofocus: true,
          maxLength: kProductLabelMaxChars,
          decoration: InputDecoration(labelText: 'products.planLabel'.tr()),
        ),
        actions: (dialogContext) => [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('products.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text('products.save'.tr()),
          ),
        ],
      );
      if (!mounted || result == null || result.isEmpty) return;
      await ref
          .read(productLabelsProvider.notifier)
          .renamePlan(widget.usage.appKey, planId, result);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deletePlan(String planId) async {
    await ref
        .read(productLabelsProvider.notifier)
        .deletePlan(widget.usage.appKey, planId);
    if (mounted) {
      setState(() {
        _planId = null;
        _newPlan = false;
      });
    }
  }
}
