import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/product_label_suggest.dart';
import 'package:openrc/features/onboarding/onboarding_steps.dart';
import 'package:openrc/features/settings/product_inventory.dart';
import 'package:openrc/features/settings/widgets/agent_settings_section.dart';
import 'package:openrc/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:openrc/models/product_labels.dart';
import 'package:openrc/services/agent/agent_llm_client.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/services/agent/product_label_suggester.dart';
import 'package:openrc/services/auto_app_icons_store.dart';
import 'package:openrc/services/onboarding_prefs_store.dart';
import 'package:openrc/services/product_labels_store.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/app_state_message.dart';
import 'package:openrc/widgets/search_field_decoration.dart';
import 'package:openrc/services/telemetry.dart';

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

/// Entries in the Product Names menu.
enum _NamesMenuAction { clearAll }

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
  void initState() {
    super.initState();
    Telemetry.screen('Product names');
  }

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
    final icons = ref.watch(resolvedAppIconsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('products.title'.tr()),
        actions: [
          // Per-app clearing lives on each app's header; this one spans every
          // app, so it is a menu item rather than another icon.
          if (!labels.isEmpty)
            PopupMenuButton<_NamesMenuAction>(
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (action) => switch (action) {
                _NamesMenuAction.clearAll => _clearAll(),
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _NamesMenuAction.clearAll,
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_sweep_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Text(
                        'products.clearAll'.tr(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: inventory.isEmpty
          ? AppStateMessage(
              icon: Icons.sell_outlined,
              title: 'products.emptyTitle'.tr(),
              message: 'products.emptyBody'.tr(),
            )
          : _ProductNamesBody(
              inventory: inventory,
              labels: labels,
              icons: icons,
              query: _query,
              suggestions: _suggestions,
              searchController: _search,
              onQueryChanged: (value) => setState(() => _query = value),
              onEdit: _editProduct,
              onAccept: _applySuggestion,
              onDismissSuggestion: (usage) =>
                  setState(() => _suggestions.remove(usage.key)),
              onClearApp: _clearApp,
            ),
      bottomNavigationBar: inventory.isEmpty
          ? null
          : _bottomBar(inventory, labels),
    );
  }

  /// How many products a suggestion run would name.
  int _unnamedCount(ProductInventory inventory, ProductLabels labels) =>
      inventory.products
          .where((p) => labels.displayName(p.appKey, p.productId) == null)
          .length;

  /// The screen's action area: ask for suggestions, follow a run, or apply
  /// what it found.
  ///
  /// It sits at the bottom, next to the list it acts on and within thumb
  /// reach, instead of behind a bare sparkle icon in the app bar.
  Widget? _bottomBar(ProductInventory inventory, ProductLabels labels) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_running) {
      return _ActionBar(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'products.aiProgress'.tr(
                      namedArgs: {'done': '$_done', 'total': '$_total'},
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _total == 0 ? null : _done / _total,
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            TextButton(
              onPressed: () => _cancel?.cancel(),
              child: Text('products.stop'.tr()),
            ),
          ],
        ),
      );
    }
    if (_suggestions.isNotEmpty) {
      return _ActionBar(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 20),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    'products.suggestionsReady'.plural(_suggestions.length),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(_suggestions.clear),
                  child: Text('products.dismiss'.tr()),
                ),
                const SizedBox(width: AppSpace.xs),
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
    if (_unnamedCount(inventory, labels) == 0) return null;
    return _ActionBar(
      child: FilledButton.icon(
        onPressed: () => _openSuggestions(inventory),
        icon: const Icon(Icons.auto_awesome_rounded, size: 20),
        label: Text('products.aiTitle'.tr()),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      ),
    );
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
    Telemetry.productNamed(source: 'ai');
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
    Telemetry.productNamed(source: 'ai');
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

  /// Forgets every name for every app, with one level of undo.
  Future<void> _clearAll() async {
    final confirmed = await showAdaptiveForm<bool>(
      context: context,
      title: 'products.clearAllTitle'.tr(),
      content: (_) => Text('products.clearAllBody'.tr()),
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
    if (confirmed != true || !mounted) return;
    await ref.read(productLabelsProvider.notifier).clearAll();
    if (!mounted) return;
    UtilitiesService.hapticLight();
    context.showSnackBar(
      'products.clearAllDone'.tr(),
      actionLabel: 'products.undo'.tr(),
      onAction: () => ref.read(productLabelsProvider.notifier).undo(),
      // Clearing right after a naming run must not queue behind its message.
      replace: true,
    );
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
    // Products the loaded rows say never renew read as their term ("1 Year")
    // instead of a cadence ("Yearly").
    final nonRenewing = {
      for (final usage in targets)
        if (!usage.renews) usage.productId,
    };
    final usageById = {for (final usage in targets) usage.productId: usage};
    setState(() {
      _running = true;
      _done = 0;
      _total = targets.length;
      _cancel = CancelToken();
      // Each batch replaces its product's suggestion as it lands, so start
      // from a clean slate rather than mixing in a previous run's names.
      _suggestions.clear();
    });

    /// Shows a batch of names on the rows and in the action bar right away.
    void show(Iterable<ProductLabelSuggestion> batch) {
      if (!mounted) return;
      final next = <String, ProductLabelSuggestion>{};
      for (final suggestion in batch) {
        final usage = usageById[suggestion.productId];
        if (usage == null) continue;
        if (suggestion.name == null && suggestion.plan == null) continue;
        next[usage.key] = suggestion;
      }
      if (next.isEmpty) return;
      setState(() => _suggestions.addAll(next));
    }

    try {
      if (mode == _SuggestMode.ai) {
        await ref
            .read(productLabelSuggesterProvider)
            .suggest(
              productIds: ids,
              nonRenewingIds: nonRenewing,
              cancelToken: _cancel!,
              // The built-in names arrive in one go; the model's land chunk
              // by chunk, so the list fills in while it is still thinking.
              onSuggestions: show,
              onProgress: (done, total) {
                if (!mounted) return;
                setState(() {
                  _done = done;
                  _total = total;
                });
              },
            );
      } else {
        show(ProductLabelSuggester.local(ids, nonRenewingIds: nonRenewing));
      }
      if (!mounted) return;
      if (_suggestions.isEmpty) {
        context.showSnackBar('products.aiNothing'.tr());
      }
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
      child: Icon(Icons.auto_awesome_rounded, size: 21, color: scheme.primary),
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
                    color:
                        accent?.withValues(alpha: 0.14) ??
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

/// One app in the tab bar: its rows, icon and naming progress.
class _AppTab {
  const _AppTab({
    required this.appKey,
    required this.label,
    required this.appId,
    required this.rows,
    required this.total,
    required this.named,
    required this.unnamed,
  });

  final String appKey;
  final String label;
  final String? appId;

  /// Rows after the search query, in display order.
  final List<ProductUsage> rows;

  /// Every loaded product in the app, before the search query.
  final int total;

  /// Loaded products that already have a name.
  final int named;

  /// Visible rows that still need a name.
  final int unnamed;
}

/// The tabbed screen body: search, status cards, app tabs, one list per app.
///
/// One app means no tabs, just its list with the app's icon and name on top.
class _ProductNamesBody extends StatelessWidget {
  const _ProductNamesBody({
    required this.inventory,
    required this.labels,
    required this.icons,
    required this.query,
    required this.suggestions,
    required this.searchController,
    required this.onQueryChanged,
    required this.onEdit,
    required this.onAccept,
    required this.onDismissSuggestion,
    required this.onClearApp,
  });

  final ProductInventory inventory;
  final ProductLabels labels;
  final Map<String, String> icons;
  final String query;

  /// Suggestions not applied yet, keyed by [ProductUsage.key]; the action
  /// bar owns applying and dismissing them.
  final Map<String, ProductLabelSuggestion> suggestions;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<ProductUsage> onEdit;
  final ValueChanged<ProductUsage> onAccept;
  final ValueChanged<ProductUsage> onDismissSuggestion;
  final void Function(String appKey, String appLabel) onClearApp;

  /// Apps in display order, each with its query-filtered rows.
  List<_AppTab> _tabs() {
    final q = query.trim().toLowerCase();
    final rowsByApp = <String, List<ProductUsage>>{};
    for (final usage in inventory.products) {
      if (q.isNotEmpty && !_matches(usage, q)) continue;
      rowsByApp.putIfAbsent(usage.appKey, () => []).add(usage);
    }
    final order = <String>[];
    for (final usage in inventory.products) {
      if (!order.contains(usage.appKey)) order.add(usage.appKey);
    }
    final tabs = <_AppTab>[];
    for (final appKey in order) {
      final rows = rowsByApp[appKey] ?? const <ProductUsage>[];
      var named = 0;
      var unnamed = 0;
      for (final p in inventory.forApp(appKey)) {
        if (labels.displayName(p.appKey, p.productId) != null) {
          named++;
        }
      }
      for (final r in rows) {
        if (labels.displayName(r.appKey, r.productId) == null) unnamed++;
      }
      tabs.add(
        _AppTab(
          appKey: appKey,
          label: inventory.appLabels[appKey] ?? appKey,
          appId: inventory.appIds[appKey],
          rows: rows,
          total: inventory.forApp(appKey).length,
          named: named,
          unnamed: unnamed,
        ),
      );
    }
    return tabs;
  }

  bool _matches(ProductUsage usage, String q) {
    final name = labels.displayName(usage.appKey, usage.productId) ?? '';
    return usage.productId.toLowerCase().contains(q) ||
        name.toLowerCase().contains(q) ||
        usage.appLabel.toLowerCase().contains(q) ||
        (suggestions[usage.key]?.name?.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final multi = tabs.length > 1;
    return DefaultTabController(
      length: tabs.length,
      // A new app set (e.g. more history loaded) starts back on the first tab.
      key: ValueKey(tabs.map((t) => t.appKey).join('|')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.xs,
              AppSpace.gutter,
              0,
            ),
            child: TextField(
              controller: searchController,
              onChanged: onQueryChanged,
              decoration: searchFieldDecoration(
                context.colorScheme,
                'products.search'.tr(),
              ),
            ),
          ),
          if (multi) ...[
            const SizedBox(height: AppSpace.xs),
            _AppTabBar(tabs: tabs, icons: icons),
          ],
          Expanded(
            child: TabBarView(
              children: [
                for (final tab in tabs)
                  _AppTabList(
                    tab: tab,
                    iconUrl: icons[tab.appId],
                    showAppIdentity: !multi,
                    labels: labels,
                    suggestions: suggestions,
                    onEdit: onEdit,
                    onAccept: onAccept,
                    onDismissSuggestion: onDismissSuggestion,
                    onClearApp: onClearApp,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom action area: the list's own width, a hairline above it, the
/// device's safe area below.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Settings reads at 640: the bar follows the same measure as the pages
    // that open it.
    final inset = AppBreakpoints.centeringInset(
      MediaQuery.sizeOf(context).width,
      maxWidth: 640,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.appColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16 + inset, 10, 16 + inset, 12),
          child: child,
        ),
      ),
    );
  }
}

/// Scrollable app tabs: icon, name, and how many products still need a name.
class _AppTabBar extends StatelessWidget {
  const _AppTabBar({required this.tabs, required this.icons});

  final List<_AppTab> tabs;
  final Map<String, String> icons;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
      labelPadding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
      tabs: [
        for (final tab in tabs)
          Tab(
            height: 48,
            child: _AppTabLabel(
              label: tab.label,
              iconUrl: icons[tab.appId],
              unnamed: tab.unnamed,
            ),
          ),
      ],
    );
  }
}

/// One tab's content: icon and name, with the unnamed count as a pill.
///
/// The pill duplicates the list header below, so screen readers skip it and
/// hear the full sentence instead of a bare number.
class _AppTabLabel extends StatelessWidget {
  const _AppTabLabel({
    required this.label,
    required this.iconUrl,
    required this.unnamed,
  });

  final String label;
  final String? iconUrl;
  final int unnamed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: TransactionLeadingAvatar(
            imageUrl: iconUrl,
            size: 26,
            borderRadius: 7,
            tintColor: scheme.primary,
            fallback: Icon(Icons.apps_rounded, color: scheme.primary, size: 14),
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (unnamed > 0) ...[
          const SizedBox(width: AppSpace.xs),
          ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$unnamed',
                style: context.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: AppText.tabular,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One app's products: naming progress, then a card per product.
class _AppTabList extends StatelessWidget {
  const _AppTabList({
    required this.tab,
    required this.iconUrl,
    required this.showAppIdentity,
    required this.labels,
    required this.suggestions,
    required this.onEdit,
    required this.onAccept,
    required this.onDismissSuggestion,
    required this.onClearApp,
  });

  final _AppTab tab;
  final String? iconUrl;
  final bool showAppIdentity;
  final ProductLabels labels;
  final Map<String, ProductLabelSuggestion> suggestions;
  final ValueChanged<ProductUsage> onEdit;
  final ValueChanged<ProductUsage> onAccept;
  final ValueChanged<ProductUsage> onDismissSuggestion;
  final void Function(String appKey, String appLabel) onClearApp;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final app = labels.forApp(tab.appKey);
    final total = tab.total;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, AppSpace.xs, 0, AppSpace.xs),
          child: Row(
            children: [
              if (showAppIdentity) ...[
                TransactionLeadingAvatar(
                  imageUrl: iconUrl,
                  size: 36,
                  borderRadius: 10,
                  tintColor: scheme.primary,
                  fallback: Icon(
                    Icons.apps_rounded,
                    color: scheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showAppIdentity)
                      Text(
                        tab.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      'products.namedOf'.tr(
                        namedArgs: {'named': '${tab.named}', 'total': '$total'},
                      ),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : tab.named / total,
                        minHeight: 4,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
              if (!app.isEmpty)
                IconButton(
                  tooltip: 'products.clear'.tr(),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: () => onClearApp(tab.appKey, tab.label),
                ),
            ],
          ),
        ),
        if (tab.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
            child: Text(
              'products.noMatches'.tr(),
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < tab.rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  _ProductRow(
                    usage: tab.rows[i],
                    label: app,
                    suggestion: suggestions[tab.rows[i].key],
                    onTap: () => onEdit(tab.rows[i]),
                    onAccept: () => onAccept(tab.rows[i]),
                    onDismiss: () => onDismissSuggestion(tab.rows[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
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
