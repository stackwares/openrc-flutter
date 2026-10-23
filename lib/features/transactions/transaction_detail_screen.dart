import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:revenuecat/core/utils/api_error_message.dart';
import 'package:revenuecat/widgets/app_state_message.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/core/theme/store_brand_icon_colors.dart';
import 'package:revenuecat/core/utils/product_identifier_display.dart';
import 'package:revenuecat/core/utils/region_display_name.dart';
import 'package:revenuecat/core/utils/relative_time_format.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_type_badge.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/models/rc_transaction_detail.dart';
import 'package:revenuecat/models/rc_transaction_detail_activity.dart';
import 'package:revenuecat/services/app_icon_overrides_store.dart';
import 'package:revenuecat/services/auto_app_icons_store.dart';
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/theme/app_tokens.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';
import 'package:revenuecat/widgets/section_header.dart';
import 'package:revenuecat/widgets/status_label.dart';
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
      state = state.copyWith(isLoading: false, error: friendlyApiErrorMessage(e));
    }
  }
}

/// Disposed when its screen closes: keyed by the transaction object, a
/// kept-alive family would hold every opened customer's history for the
/// whole session.
final transactionDetailProvider =
    StateNotifierProvider.autoDispose.family<
      TransactionDetailNotifier,
      TransactionDetailState,
      RcTransaction
    >(
      (ref, transaction) => TransactionDetailNotifier(
        ref,
        TransactionDetailState(transaction: transaction),
      ),
    );

String _transactionDetailAppBarTitle(RcTransaction transaction) {
  final name = transaction.app?.name?.trim();
  if (name != null && name.isNotEmpty) return name;
  return productIdentifierDisplayTitle(
    transaction.productIdentifier,
    ifEmpty: 'Transaction',
  );
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('App icon'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                appName != null
                    ? 'Icons are fetched from the App Store or Google Play automatically. Enter an image URL to use a different icon for $appName.'
                    : 'Icons are fetched from the App Store or Google Play automatically. Enter an image URL to use a different icon.',
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              controller.clear();
              await ref
                  .read(appIconOverridesProvider.notifier)
                  .setOverride(appId, null);
              if (!context.mounted) return;
              Navigator.pop(dialogContext);
              context.showSnackBar('Using the store icon');
            },
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isNotEmpty && !isValidHttpIconUrl(text)) {
                context.showSnackBar('Enter a valid http or https URL');
                return;
              }
              await ref
                  .read(appIconOverridesProvider.notifier)
                  .setOverride(appId, text.isEmpty ? null : text);
              if (!context.mounted) return;
              Navigator.pop(dialogContext);
              context.showSnackBar(
                text.isEmpty ? 'Using the store icon' : 'App icon saved',
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
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
            tooltip: 'Refresh',
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
      title: 'Couldn\u2019t load customer details',
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
            title: 'History',
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
            _SectionHeader(title: 'Entitlements'),
            _buildEntitlements(
              context,
              detail.subscriptionStatuses!,
              tx,
            ).appCardEntrance(delay: nextSectionDelay()),
          ],
          _SectionHeader(title: 'Info'),
          _buildInfoSection(
            context,
            detail,
            tx,
          ).appCardEntrance(delay: nextSectionDelay()),
          _SectionHeader(title: 'Insights'),
          _buildInsights(
            context,
            detail,
            activity,
            tx,
          ).appCardEntrance(delay: nextSectionDelay()),
          if (detail.subscriberAttributes?.isNotEmpty == true) ...[
            _SectionHeader(title: 'Attributes'),
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
        message: 'Set app icon',
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
    final productTitle = productIdentifierDisplayTitle(tx.productIdentifier);
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
                DateFormat('EEE, MMM d, y · h:mm a').format(purchased),
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
                    tx.store!,
                    iconTint: storeBrandIconTint(tx.store),
                  ),
                if (tx.subscriberCountryCode != null)
                  _buildChip(
                    context,
                    null,
                    '${_countryFlag(tx.subscriberCountryCode!)} ${regionDisplayNameEnglish(tx.subscriberCountryCode)}',
                    maxLines: 2,
                  ),
                if (tx.isSandbox == true)
                  _buildChip(
                    context,
                    Icons.science_outlined,
                    'Sandbox',
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
            label: 'Subscriber ID',
            value: tx.subscriberId,
            copyable: true,
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.receipt_long_outlined,
            label: 'Store transaction ID',
            value: tx.storeTransactionIdentifier,
            copyable: true,
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.payments_outlined,
            label: 'Total spent',
            usdAmount: detail.dollarsSpent,
            applyBlendedCommission: true,
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.visibility_outlined,
            label: 'Last seen',
            value: _relativeTime(detail.lastSeen),
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Created',
            value: _relativeTime(detail.createdAt),
          ),
          if (detail.lastSeenCountry != null) ...[
            const _Divider(),
            _InfoRow(
              icon: Icons.flag_outlined,
              label: 'Country and locale',
              value:
                  '${regionDisplayNameEnglish(detail.lastSeenCountry)} ${detail.lastSeenLocale ?? ""}'
                      .trim(),
            ),
          ],
          if (detail.app?.name != null) ...[
            const _Divider(),
            _InfoRow(
              icon: Icons.apps_outlined,
              label: 'App',
              value:
                  '${detail.app!.name}${detail.lastSeenAppVersion != null ? " v${detail.lastSeenAppVersion}" : ""}',
            ),
          ],
          if (detail.lastSeenPlatform != null) ...[
            const _Divider(),
            _InfoRow(
              icon: Icons.devices_outlined,
              label: 'Platform',
              value:
                  '${detail.lastSeenPlatform}${detail.lastSeenPlatformVersion != null ? " v${detail.lastSeenPlatformVersion}" : ""}',
            ),
          ],
          if (detail.lastSeenSdkVersion != null) ...[
            const _Divider(),
            _InfoRow(
              icon: Icons.code_outlined,
              label: 'SDK version',
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
                        s.entitlementIdentifier ?? 'Unknown',
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    StatusLabel(
                      text: isActive ? 'Active' : 'Inactive',
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
                          'Expires ${_formatDateTime(s.expiresDate!)}',
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
            label: 'First purchase',
            value: '$days days ago',
          ),
        );
      }
    }

    if (detail.dollarsSpent != null && detail.dollarsSpent! > 0) {
      insights.add(
        _InsightItem(
          icon: Icons.attach_money,
          label: 'Total spent',
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
          label: 'Refunds',
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
          label: 'Transfers',
          value: '$transferCount',
        ),
      );
    }

    if (insights.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No insights available',
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
              label: attributes[i].key ?? 'Unknown',
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
          title: h.event ?? 'Event',
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
          title: e.type ?? 'Event',
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
          'No history available',
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
    if (dateStr == null) return 'N/A';
    return formatRelativeTimeShort(dateStr);
  }

  String _countryFlag(String code) {
    if (code.length != 2) return code;
    return String.fromCharCodes(
      code.toUpperCase().codeUnits.map((c) => c + 127397),
    );
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
          'Spent ',
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
                      _showAll ? 'Show less' : 'Show all ($remaining more)',
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
            value ?? 'N/A',
            style: valueStyle,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          );

    return InkWell(
      onTap: copyable && value != null
          ? () {
              Clipboard.setData(ClipboardData(text: value!));
              context.showSnackBar('Copied to clipboard');
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
        color: Color.lerp(scheme.surfaceContainerLow, accent, 0.18) ??
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
                            DateFormat(
                              'MMM d, yyyy · h:mm a',
                            ).format(item.date!.toLocal()),
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

  static String _formatEventType(String type) {
    final words = type.split('_');
    return words
        .map((w) {
          if (w.isEmpty) return w;
          return w[0].toUpperCase() + w.substring(1).toLowerCase();
        })
        .join(' ');
  }
}
