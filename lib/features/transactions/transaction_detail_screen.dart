import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:openrc/core/utils/api_error_message.dart';
import 'package:openrc/widgets/app_state_message.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/constants/app_constants.dart';
import 'package:openrc/core/theme/store_brand_icon_colors.dart';
import 'package:openrc/core/utils/plan_display.dart';
import 'package:openrc/core/utils/region_display_name.dart';
import 'package:openrc/core/utils/store_display_name.dart';
import 'package:openrc/core/utils/relative_time_format.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:openrc/features/transactions/widgets/transaction_type_badge.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/models/rc_transaction_detail.dart';
import 'package:openrc/models/rc_transaction_detail_activity.dart';
import 'package:openrc/services/app_icon_overrides_store.dart';
import 'package:openrc/services/auto_app_icons_store.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/dual_currency_text.dart';
import 'package:openrc/widgets/section_header.dart';
import 'package:openrc/widgets/status_label.dart';
import 'package:skeletonizer/skeletonizer.dart';

class TransactionDetailState {
  final RcTransaction transaction;
  final RcTransactionDetailResponse? detail;
  final RcTransactionDetailActivityResponse? activity;
  final bool isLoading;
  final String? error;

  const TransactionDetailState({
    required this.transaction,
    this.detail,
    this.activity,
    this.isLoading = true,
    this.error,
  });

  TransactionDetailState copyWith({
    RcTransactionDetailResponse? detail,
    RcTransactionDetailActivityResponse? activity,
    bool? isLoading,
    String? error,
  }) => TransactionDetailState(
    transaction: transaction,
    detail: detail ?? this.detail,
    activity: activity ?? this.activity,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}

class TransactionDetailNotifier extends StateNotifier<TransactionDetailState> {
  final Ref _ref;

  TransactionDetailNotifier(this._ref, TransactionDetailState initial)
    : super(initial) {
    _fetch();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    await _fetch();
  }

  Future<void> _fetch() async {
    try {
      final api = _ref.read(rcApiServiceProvider);
      final projectId = state.transaction.app?.id;
      final subscriberId = state.transaction.subscriberId;

      if (projectId == null || subscriberId == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final results = await Future.wait([
        api.transactionDetail(projectId: projectId, subscriberId: subscriberId),
        api.transactionDetailActivity(
          projectId: projectId,
          subscriberId: subscriberId,
        ),
      ]);
      // The screen may have closed (and disposed this) while loading.
      if (!mounted) return;

      state = state.copyWith(
        detail: results[0] as RcTransactionDetailResponse,
        activity: results[1] as RcTransactionDetailActivityResponse,
        isLoading: false,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final rcError = _ref.read(rcApiServiceProvider).parseError(e);
      if (rcError?.code == AppConstants.rcErrorInvalidAuthToken ||
          rcError?.code == AppConstants.rcErrorExpiredAuthToken) {
        _ref
            .read(rcAuthServiceProvider)
            .signOut(reason: SignOutReason.sessionExpired);
      }
      state = state.copyWith(
        isLoading: false,
        error: friendlyApiErrorMessage(e, serverMessage: rcError?.message),
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: friendlyApiErrorMessage(e),
      );
    }
  }
}

/// Disposed when its screen closes: keyed by the transaction object, a
/// kept-alive family would hold every opened customer's history for the
/// whole session.
final transactionDetailProvider = StateNotifierProvider.autoDispose
    .family<TransactionDetailNotifier, TransactionDetailState, RcTransaction>(
      (ref, transaction) => TransactionDetailNotifier(
        ref,
        TransactionDetailState(transaction: transaction),
      ),
    );

String _transactionDetailAppBarTitle(RcTransaction transaction) {
  final name = transaction.app?.name?.trim();
  if (name != null && name.isNotEmpty) return name;
  return planProductId(transaction, ifEmpty: 'detail.transaction'.tr());
}

/// `name v1.2.3` when [version] is known, otherwise just [base].
String _withVersion(String base, String? version) {
  if (version == null) return base;
  final v = 'detail.version'.tr(namedArgs: {'version': version});
  return '$base $v';
}

Future<void> _showAppIconUrlDialog(
  BuildContext context,
  WidgetRef ref, {
  required String appId,
  String? appName,
  String? currentUrl,
}) async {
  final controller = TextEditingController(text: currentUrl ?? '');
  try {
    await showAdaptiveForm<void>(
      context: context,
      title: 'detail.appIcon'.tr(),
      content: (dialogContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              appName != null
                  ? 'detail.iconHintForApp'.tr(namedArgs: {'appName': appName})
                  : 'detail.iconHint'.tr(),
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'https://…',
                isDense: true,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
          ],
        ),
      ),
      actions: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('detail.cancel'.tr()),
        ),
        TextButton(
          onPressed: () async {
            controller.clear();
            await ref
                .read(appIconOverridesProvider.notifier)
                .setOverride(appId, null);
            if (!context.mounted) return;
            Navigator.pop(dialogContext);
            context.showSnackBar('detail.usingStoreIcon'.tr());
          },
          child: Text('detail.clear'.tr()),
        ),
        FilledButton(
          onPressed: () async {
            final text = controller.text.trim();
            if (text.isNotEmpty && !isValidHttpIconUrl(text)) {
              context.showSnackBar('detail.invalidIconUrl'.tr());
              return;
            }
            await ref
                .read(appIconOverridesProvider.notifier)
                .setOverride(appId, text.isEmpty ? null : text);
            if (!context.mounted) return;
            Navigator.pop(dialogContext);
            context.showSnackBar(
              text.isEmpty
                  ? 'detail.usingStoreIcon'.tr()
                  : 'detail.iconSaved'.tr(),
            );
          },
          child: Text('detail.save'.tr()),
        ),
      ],
    );
  } finally {
    controller.dispose();
  }
}

class TransactionDetailScreen extends ConsumerWidget {
  final RcTransaction transaction;

  /// Matches the list row's icon [Hero] so the app icon flies into place.
  final Object? heroTag;

  const TransactionDetailScreen({
    super.key,
    required this.transaction,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transactionDetailProvider(transaction));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _transactionDetailAppBarTitle(transaction),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'detail.refresh'.tr(),
            onPressed: state.isLoading
                ? null
                : () => ref
                      .read(transactionDetailProvider(transaction).notifier)
                      .refresh(),
          ),
        ],
      ),
      // The header only needs the transaction, so it shows right away (and
      // receives the icon hero); the customer sections load below it.
      body: !state.isLoading && state.error != null
          ? _buildError(context, ref, state.error!)
          : _buildContent(context, ref, state),
    );
  }

  /// Placeholder for the customer sections while they load.
  Widget _buildSectionsSkeleton(BuildContext context) {
    return Skeletonizer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 16, 8),
            child: Bone.text(fontSize: 15, width: 90),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: List.generate(
                  4,
                  (i) => Padding(
                    padding: EdgeInsets.only(bottom: i < 3 ? 14 : 0),
                    child: const Bone.multiText(lines: 2, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, String error) {
    return AppStateMessage.error(
      title: 'detail.loadError'.tr(),
      message: error,
      onRetry: () =>
          ref.read(transactionDetailProvider(transaction).notifier).refresh(),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    TransactionDetailState state,
  ) {
    final detail = state.detail;
    final activity = state.activity;
    final tx = state.transaction;
    final appId = tx.app?.id;
    final customIconUrl = appId != null
        ? ref.watch(resolvedAppIconsProvider)[appId]
        : null;

    var sectionStep = 0;
    Duration nextSectionDelay() {
      final ms = sectionStep * 55;
      sectionStep++;
      return Duration(milliseconds: ms);
    }

    final summary = _buildTransactionSummary(
      context,
      ref,
      tx,
      appId: appId,
      appName: tx.app?.name,
      customIconUrl: customIconUrl,
    );
    final summaryDelay = nextSectionDelay();

    return ListView(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        // With a hero the icon already carries the eye; skip the card fade.
        heroTag != null
            ? summary
            : summary.appCardEntrance(delay: summaryDelay),
        if (state.isLoading) _buildSectionsSkeleton(context),
        if (!state.isLoading &&
            (detail?.history?.isNotEmpty == true ||
                activity?.events?.isNotEmpty == true)) ...[
          _SectionHeader(
            title: 'detail.history'.tr(),
            trailing: _buildHistoryHeaderTrailing(context, detail, activity),
          ),
          _buildHistory(
            context,
            tx,
            detail?.history,
            activity?.events,
          ).appCardEntrance(delay: nextSectionDelay()),
        ],
        if (!state.isLoading && detail != null) ...[
          if (detail.subscriptionStatuses?.isNotEmpty == true) ...[
            _SectionHeader(title: 'detail.entitlements'.tr()),
            _buildEntitlements(
              context,
              detail.subscriptionStatuses!,
              tx,
            ).appCardEntrance(delay: nextSectionDelay()),
          ],
          _SectionHeader(title: 'detail.info'.tr()),
          _buildInfoSection(
            context,
            detail,
            tx,
          ).appCardEntrance(delay: nextSectionDelay()),
          _SectionHeader(title: 'detail.insights'.tr()),
          _buildInsights(
            context,
            detail,
            activity,
            tx,
          ).appCardEntrance(delay: nextSectionDelay()),
          if (detail.subscriberAttributes?.isNotEmpty == true) ...[
            _SectionHeader(title: 'detail.attributes'.tr()),
            _buildAttributes(
              context,
              detail.subscriberAttributes!,
              tx,
            ).appCardEntrance(delay: nextSectionDelay()),
          ],
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildTransactionSummary(
    BuildContext context,
    WidgetRef ref,
    RcTransaction tx, {
    String? appId,
    String? appName,
    String? customIconUrl,
  }) {
    final type = tx.type;
    final baseHeaderRevenueStyle = AppText.amount(context, size: 32);
    final headerRevenueStyle = tx.tileShowRefundRevenueStrikethrough
        ? baseHeaderRevenueStyle.copyWith(
            decoration: TextDecoration.lineThrough,
            decorationColor: context.colorScheme.onSurfaceVariant,
          )
        : baseHeaderRevenueStyle;
    final color = transactionTypeAccentColor(type, context, transaction: tx);
    final hasCustomIcon =
        customIconUrl != null && customIconUrl.trim().isNotEmpty;

    Widget avatar = TransactionLeadingAvatar(
      imageUrl: customIconUrl,
      size: 56,
      borderRadius: 14,
      tintColor: color,
      fallback: Icon(
        hasCustomIcon ? _typeIcon(type) : Icons.edit_outlined,
        color: color,
        size: 24,
      ),
    );
    if (heroTag != null) avatar = Hero(tag: heroTag!, child: avatar);
    if (appId != null) {
      avatar = Tooltip(
        message: 'detail.setAppIcon'.tr(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showAppIconUrlDialog(
              context,
              ref,
              appId: appId,
              appName: appName,
              currentUrl: ref.read(appIconOverridesProvider)[appId],
            ),
            borderRadius: BorderRadius.circular(12),
            child: avatar,
          ),
        ),
      );
    }

    final scheme = context.colorScheme;
    final appTitle = appName?.trim();
    final productTitle = planDescription(tx);
    final purchased = DateTime.tryParse(tx.purchaseDate ?? '')?.toLocal();
    final muted = context.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                avatar,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appTitle != null && appTitle.isNotEmpty
                            ? appTitle
                            : productTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (appTitle != null && appTitle.isNotEmpty)
                            productTitle,
                          ?tx.productIdentifier,
                        ].join('  ·  '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: tx.tileDisplayRevenue != null
                      ? DualCurrencyExactText(
                          amount: tx.tileDisplayRevenue!,
                          commissionStore: tx.storeForCommission,
                          style: headerRevenueStyle,
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 12),
                TransactionTypeBadge(transaction: tx),
              ],
            ),
            if (purchased != null) ...[
              const SizedBox(height: 4),
              Text(
                '${DateFormat.yMMMEd().format(purchased)} · ${DateFormat.jm().format(purchased)}',
                style: muted,
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (tx.store != null)
                  _buildChip(
                    context,
                    _storeIcon(tx.store!),
                    revenueCatStoreDisplayName(tx.store!),
                    iconTint: storeBrandIconTint(tx.store),
                  ),
                if (tx.subscriberCountryCode != null)
                  _buildChip(
                    context,
                    null,
                    '${countryFlagEmoji(tx.subscriberCountryCode!)} ${regionDisplayNameEnglish(tx.subscriberCountryCode)}',
                    maxLines: 2,
                  ),
                if (tx.isSandbox == true)
                  _buildChip(
                    context,
                    Icons.science_outlined,
                    'detail.sandbox'.tr(),
                    color: context.appColors.warning,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(
    BuildContext context,
    IconData? icon,
    String label, {
    Color? color,
    int maxLines = 1,
    Color? iconTint,
  }) {
    final scheme = context.colorScheme;
    final fg = color ?? scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color != null
            ? color.withValues(alpha: 0.14)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconTint ?? fg),
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              style: context.textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(
    BuildContext context,
    RcTransactionDetailResponse detail,
    RcTransaction tx,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.fingerprint,
            label: 'detail.subscriberId'.tr(),
            value: tx.subscriberId,
            copyable: true,
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.receipt_long_outlined,
            label: 'detail.storeTransactionId'.tr(),
            value: tx.storeTransactionIdentifier,
            copyable: true,
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.payments_outlined,
            label: 'detail.totalSpent'.tr(),
            usdAmount: detail.dollarsSpent,
            applyBlendedCommission: true,
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.visibility_outlined,
            label: 'detail.lastSeen'.tr(),
            value: _relativeTime(detail.lastSeen),
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'detail.created'.tr(),
            value: _relativeTime(detail.createdAt),
          ),
          if (detail.lastSeenCountry != null) ...[
            const _Divider(),
            _InfoRow(
              icon: Icons.flag_outlined,
              label: 'detail.countryAndLocale'.tr(),
              value:
                  '${regionDisplayNameEnglish(detail.lastSeenCountry)} ${detail.lastSeenLocale ?? ""}'
                      .trim(),
            ),
          ],
          if (detail.app?.name != null) ...[
            const _Divider(),
            _InfoRow(
              icon: Icons.apps_outlined,
              label: 'detail.app'.tr(),
              value: _withVersion(
                '${detail.app!.name}',
                detail.lastSeenAppVersion,
              ),
            ),
          ],
          if (detail.lastSeenPlatform != null) ...[
            const _Divider(),
            _InfoRow(
              icon: Icons.devices_outlined,
              label: 'detail.platform'.tr(),
              value: _withVersion(
                '${detail.lastSeenPlatform}',
                detail.lastSeenPlatformVersion,
              ),
            ),
          ],
          if (detail.lastSeenSdkVersion != null) ...[
            const _Divider(),
            _InfoRow(
              icon: Icons.code_outlined,
              label: 'detail.sdkVersion'.tr(),
              value: detail.lastSeenSdkVersion,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEntitlements(
    BuildContext context,
    List<RcSubscriptionStatus> statuses,
    RcTransaction tx,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: statuses.map((s) {
          final isActive = s.isAutoRenewing == true;
          final color = isActive
              ? context.appColors.positive
              : context.appColors.warning;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.entitlementIdentifier ?? 'detail.unknown'.tr(),
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    StatusLabel(
                      text: isActive
                          ? 'detail.active'.tr()
                          : 'detail.inactive'.tr(),
                      color: color,
                      pill: true,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.productIdentifier ?? '',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (s.expiresDate != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 4, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'detail.expires'.tr(
                            namedArgs: {
                              'date': _formatDateTime(s.expiresDate!),
                            },
                          ),
                          style: context.textTheme.labelSmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatEntitlementExpiresInLabel(s.expiresDate!),
                        style: context.textTheme.labelSmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ),
                ),
              if (s != statuses.last) const _Divider(),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInsights(
    BuildContext context,
    RcTransactionDetailResponse detail,
    RcTransactionDetailActivityResponse? activity,
    RcTransaction tx,
  ) {
    final insights = <_InsightItem>[];

    if (detail.createdAt != null) {
      final created = DateTime.tryParse(detail.createdAt!);
      if (created != null) {
        final days = DateTime.now().difference(created).inDays;
        insights.add(
          _InsightItem(
            icon: Icons.schedule_outlined,
            label: 'detail.firstPurchase'.tr(),
            value: 'detail.daysAgo'.plural(days),
          ),
        );
      }
    }

    if (detail.dollarsSpent != null && detail.dollarsSpent! > 0) {
      insights.add(
        _InsightItem(
          icon: Icons.attach_money,
          label: 'detail.totalSpent'.tr(),
          usdAmount: detail.dollarsSpent!,
          applyBlendedCommission: true,
        ),
      );
    }

    final refundCount =
        activity?.events
            ?.where((e) => e.type == 'REFUND' || e.type == 'CANCELLATION')
            .length ??
        0;
    if (refundCount > 0) {
      insights.add(
        _InsightItem(
          icon: Icons.undo,
          label: 'detail.refunds'.tr(),
          value: '$refundCount',
          color: context.appColors.negative,
        ),
      );
    }

    final transferCount =
        activity?.events
            ?.where(
              (e) =>
                  e.transferredFrom?.isNotEmpty == true ||
                  e.transferredTo?.isNotEmpty == true,
            )
            .length ??
        0;
    if (transferCount > 0) {
      insights.add(
        _InsightItem(
          icon: Icons.swap_horiz,
          label: 'detail.transfers'.tr(),
          value: '$transferCount',
        ),
      );
    }

    if (insights.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'detail.noInsights'.tr(),
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < insights.length; i++) ...[
            if (i > 0) const _Divider(),
            _InfoRow(
              icon: insights[i].icon,
              label: insights[i].label,
              value: insights[i].value,
              usdAmount: insights[i].usdAmount,
              applyBlendedCommission: insights[i].applyBlendedCommission,
              color: insights[i].color,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAttributes(
    BuildContext context,
    List<RcSubscriberAttribute> attributes,
    RcTransaction tx,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < attributes.length; i++) ...[
            if (i > 0) const _Divider(),
            _InfoRow(
              icon: Icons.tag_outlined,
              label: attributes[i].key ?? 'detail.unknown'.tr(),
              value: attributes[i].value,
              copyable: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistory(
    BuildContext context,
    RcTransaction tx,
    List<RcSubscriberHistory>? history,
    List<RcTransactionDetailEvent>? events,
  ) {
    final items = <_HistoryItem>[];

    for (final h in history ?? <RcSubscriberHistory>[]) {
      final dt = DateTime.tryParse(h.at ?? '');
      items.add(
        _HistoryItem(
          timestamp: dt?.millisecondsSinceEpoch ?? 0,
          title: h.event ?? 'detail.eventTypes.event'.tr(),
          subtitle: h.product ?? '',
          priceUsd: h.priceInUsd,
          date: dt,
        ),
      );
    }

    for (final e in events ?? <RcTransactionDetailEvent>[]) {
      final ms = e.eventTimestampMs ?? e.purchasedAtMs ?? 0;
      final dt = ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
      items.add(
        _HistoryItem(
          timestamp: ms,
          title: e.type ?? 'detail.eventTypes.event'.tr(),
          subtitle: e.productId ?? e.newProductId ?? '',
          priceUsd: e.price,
          date: dt,
        ),
      );
    }

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'detail.noHistory'.tr(),
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return _ExpandableHistoryListCard(
      cardColor: Theme.of(context).colorScheme.surfaceContainerLow,
      transaction: tx,
      items: items,
    );
  }

  IconData _typeIcon(RcTransactionType type) {
    switch (type) {
      case RcTransactionType.newSubscription:
        return Icons.add_circle_outline;
      case RcTransactionType.oneTimePurchase:
        return Icons.shopping_bag_outlined;
      case RcTransactionType.renewal:
        return Icons.autorenew;
      case RcTransactionType.trial:
        return Icons.science_outlined;
      case RcTransactionType.conversion:
        return Icons.swap_horiz;
      case RcTransactionType.refund:
        return Icons.undo;
      case RcTransactionType.unknown:
        return Icons.help_outline;
    }
  }

  IconData? _storeIcon(String store) {
    switch (store) {
      case 'App Store':
        return Icons.apple;
      case 'Play Store':
        return Icons.android;
      case 'Stripe':
        return Icons.credit_card;
      default:
        return Icons.store;
    }
  }

  String _formatDateTime(String dateStr) {
    try {
      final dt = DateTime.tryParse(dateStr);
      if (dt != null) {
        return DateFormat.yMMMd().add_jm().format(dt);
      }
    } catch (_) {}
    return dateStr;
  }

  String _relativeTime(String? dateStr) {
    if (dateStr == null) return 'detail.notAvailable'.tr();
    return formatRelativeTimeShort(dateStr);
  }

  /// Right side of the History section header; shows total renewals + total spent.
  Widget _buildHistoryHeaderTrailing(
    BuildContext context,
    RcTransactionDetailResponse? detail,
    RcTransactionDetailActivityResponse? activity,
  ) {
    final renewalColor = transactionTypeAccentColor(
      RcTransactionType.renewal,
      context,
    );

    final historyRenewalCount =
        detail?.history?.where((h) {
          final e = h.event?.toUpperCase() ?? '';
          return e == 'RENEWAL' ||
              e == 'RENEWED' ||
              e == 'CONVERTED FROM A TRIAL';
        }).length ??
        0;

    final eventsRenewalCount =
        activity?.events?.where((e) {
          return e.type?.toUpperCase() == 'RENEWAL';
        }).length ??
        0;

    final totalRenewals = historyRenewalCount + eventsRenewalCount;

    final children = <Widget>[];

    if (totalRenewals > 0) {
      children.addAll([
        Icon(Icons.autorenew, size: 14, color: renewalColor),
        const SizedBox(width: 4),
        Text(
          '$totalRenewals',
          style: context.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: renewalColor,
          ),
        ),
      ]);
    }

    if (detail?.dollarsSpent != null) {
      if (totalRenewals > 0) {
        children.add(const SizedBox(width: 12));
      }
      children.addAll([
        Text(
          'detail.spent'.tr(),
          style: context.textTheme.labelSmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        DualCurrencyExactText(
          amount: detail!.dollarsSpent!,
          applyBlendedCommission: true,
          style: context.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.end,
        ),
      ]);
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: children,
    );
  }
}

const int _kHistoryInitialVisibleCount = 5;

class _ExpandableHistoryListCard extends StatefulWidget {
  final Color cardColor;
  final RcTransaction transaction;
  final List<_HistoryItem> items;

  const _ExpandableHistoryListCard({
    required this.cardColor,
    required this.transaction,
    required this.items,
  });

  @override
  State<_ExpandableHistoryListCard> createState() =>
      _ExpandableHistoryListCardState();
}

class _ExpandableHistoryListCardState
    extends State<_ExpandableHistoryListCard> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final total = items.length;
    final needsToggle = total > _kHistoryInitialVisibleCount;
    final visible = !_showAll && needsToggle
        ? items.sublist(0, _kHistoryInitialVisibleCount)
        : items;
    final remaining = total - _kHistoryInitialVisibleCount;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: widget.cardColor,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
        child: _GrowOpen(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < visible.length; i++)
                _HistoryTimelineEntry(
                  item: visible[i],
                  commissionStore: widget.transaction.storeForCommission,
                  isFirst: i == 0,
                  isLast: i == visible.length - 1,
                ),
              if (needsToggle)
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(
                      _showAll
                          ? 'detail.showLess'.tr()
                          : 'detail.showAll'.tr(
                              namedArgs: {'count': '$remaining'},
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Show all" grows the card open instead of jumping. AnimatedSize with a
/// zero duration throws during layout, so reduced motion skips it.
class _GrowOpen extends StatelessWidget {
  const _GrowOpen({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return SectionHeader(title: title, trailing: trailing);
  }
}

class _InfoRow extends ConsumerWidget {
  final IconData icon;
  final String label;
  final String? value;
  final double? usdAmount;
  final bool applyBlendedCommission;
  final bool copyable;
  final Color? color;

  const _InfoRow({
    required this.icon,
    required this.label,
    this.value,
    this.usdAmount,
    this.applyBlendedCommission = false,
    this.copyable = false,
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valueStyle = context.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: color,
      fontFeatures: AppText.tabular,
    );
    final Widget valueWidget = usdAmount != null
        ? DualCurrencyExactText(
            amount: usdAmount!,
            applyBlendedCommission: applyBlendedCommission,
            style: valueStyle,
            textAlign: TextAlign.end,
          )
        : Text(
            value ?? 'detail.notAvailable'.tr(),
            style: valueStyle,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          );

    return InkWell(
      onTap: copyable && value != null
          ? () {
              Clipboard.setData(ClipboardData(text: value!));
              context.showSnackBar('detail.copied'.tr());
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: color ?? context.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: valueWidget,
              ),
            ),
            if (copyable && value != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.copy,
                size: 14,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(indent: 46);
  }
}

class _InsightItem {
  final IconData icon;
  final String label;
  final String? value;
  final double? usdAmount;
  final bool applyBlendedCommission;
  final Color? color;

  const _InsightItem({
    required this.icon,
    required this.label,
    this.value,
    this.usdAmount,
    this.applyBlendedCommission = false,
    this.color,
  });
}

class _HistoryItem {
  final int timestamp;
  final String title;
  final String subtitle;
  final double? priceUsd;
  final DateTime? date;

  const _HistoryItem({
    required this.timestamp,
    required this.title,
    required this.subtitle,
    this.priceUsd,
    this.date,
  });
}

class _HistoryTimelineEntry extends ConsumerWidget {
  final _HistoryItem item;
  final String? commissionStore;
  final bool isFirst;
  final bool isLast;

  const _HistoryTimelineEntry({
    required this.item,
    required this.commissionStore,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final lineColor = scheme.outlineVariant.withValues(alpha: 0.75);
    const railW = 28.0;
    const dotSize = 12.0;
    const stubH = 10.0;

    final accent = transactionHistoryEventAccentColor(item.title, context);
    final dot = Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color:
            Color.lerp(scheme.surfaceContainerLow, accent, 0.18) ??
            scheme.surfaceContainerLow,
        border: Border.all(color: accent, width: 2),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: railW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!isFirst)
                    Container(width: 2, height: stubH, color: lineColor),
                  SizedBox(
                    height: 18,
                    width: railW,
                    child: Center(child: dot),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 13),
                        width: 2,
                        color: lineColor,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1, bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatEventType(item.title),
                            style: context.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                          if (item.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (item.priceUsd != null)
                          DualCurrencyExactText(
                            amount: item.priceUsd!,
                            commissionStore: commissionStore,
                            style: context.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: accent,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        if (item.date != null) ...[
                          if (item.priceUsd != null) const SizedBox(height: 2),
                          Text(
                            '${DateFormat.yMMMd().format(item.date!.toLocal())}'
                            ' · ${DateFormat.jm().format(item.date!.toLocal())}',
                            style: context.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Known RevenueCat event names get a translated label; anything else keeps
  /// the generic `SOME_EVENT` -> `Some Event` formatting.
  static const Map<String, String> _eventTypeKeys = {
    'INITIAL_PURCHASE': 'detail.eventTypes.initialPurchase',
    'RENEWAL': 'detail.eventTypes.renewal',
    'RENEWED': 'detail.eventTypes.renewed',
    'CANCELLATION': 'detail.eventTypes.cancellation',
    'UNCANCELLATION': 'detail.eventTypes.uncancellation',
    'NON_RENEWING_PURCHASE': 'detail.eventTypes.nonRenewingPurchase',
    'EXPIRATION': 'detail.eventTypes.expiration',
    'BILLING_ISSUE': 'detail.eventTypes.billingIssue',
    'PRODUCT_CHANGE': 'detail.eventTypes.productChange',
    'SUBSCRIPTION_PAUSED': 'detail.eventTypes.subscriptionPaused',
    'TRANSFER': 'detail.eventTypes.transfer',
    'REFUND': 'detail.eventTypes.refund',
    'TEMPORARY_ENTITLEMENT_GRANT':
        'detail.eventTypes.temporaryEntitlementGrant',
    'SUBSCRIBER_ALIAS': 'detail.eventTypes.subscriberAlias',
    'CONVERTED FROM A TRIAL': 'detail.eventTypes.convertedFromATrial',
    'EVENT': 'detail.eventTypes.event',
  };

  static String _formatEventType(String type) {
    final key = _eventTypeKeys[type.toUpperCase()];
    if (key != null) return key.tr();
    final words = type.split('_');
    return words
        .map((w) {
          if (w.isEmpty) return w;
          return w[0].toUpperCase() + w.substring(1).toLowerCase();
        })
        .join(' ');
  }
}
