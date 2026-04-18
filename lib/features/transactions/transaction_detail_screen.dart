import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
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
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';
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
  }) =>
      TransactionDetailState(
        transaction: transaction,
        detail: detail ?? this.detail,
        activity: activity ?? this.activity,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class TransactionDetailNotifier
    extends StateNotifier<TransactionDetailState> {
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
        api.transactionDetail(
          projectId: projectId,
          subscriberId: subscriberId,
        ),
        api.transactionDetailActivity(
          projectId: projectId,
          subscriberId: subscriberId,
        ),
      ]);

      state = state.copyWith(
        detail: results[0] as RcTransactionDetailResponse,
        activity: results[1] as RcTransactionDetailActivityResponse,
        isLoading: false,
      );
    } on DioException catch (e) {
      final rcError = _ref.read(rcApiServiceProvider).parseError(e);
      if (rcError?.code == AppConstants.rcErrorInvalidAuthToken ||
          rcError?.code == AppConstants.rcErrorExpiredAuthToken) {
        _ref.read(rcAuthServiceProvider).signOut();
      }
      state = state.copyWith(
        isLoading: false,
        error: rcError?.message ?? 'Failed to load details',
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load details');
    }
  }
}

final transactionDetailProvider = StateNotifierProvider.family<
    TransactionDetailNotifier, TransactionDetailState, RcTransaction>(
  (ref, transaction) =>
      TransactionDetailNotifier(ref, TransactionDetailState(transaction: transaction)),
);

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
                    ? 'Optional image URL for $appName. Used in the transactions list for this app.'
                    : 'Optional HTTPS image URL. Used in the transactions list for this app.',
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
              await ref.read(appIconOverridesProvider.notifier).setOverride(appId, null);
              if (!context.mounted) return;
              Navigator.pop(dialogContext);
              context.showSnackBar('Using default icon');
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
              await ref.read(appIconOverridesProvider.notifier).setOverride(
                    appId,
                    text.isEmpty ? null : text,
                  );
              if (!context.mounted) return;
              Navigator.pop(dialogContext);
              context.showSnackBar(
                text.isEmpty ? 'Using default icon' : 'App icon saved',
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

  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transactionDetailProvider(transaction));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          productIdentifierDisplayTitle(
            transaction.productIdentifier,
            ifEmpty: 'Transaction',
          ),
          style: context.textTheme.titleMedium,
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
      body: state.isLoading
          ? _buildDetailSkeleton(context)
          : state.error != null
              ? _buildError(context, ref, state.error!)
              : _buildContent(context, ref, state),
    );
  }

  Widget _buildDetailSkeleton(BuildContext context) {
    return Skeletonizer(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone.square(
                    size: 48,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Bone.text(fontSize: 18),
                        const SizedBox(height: 8),
                        Bone.text(fontSize: 12, width: 200),
                      ],
                    ),
                  ),
                  Bone.text(fontSize: 22, width: 72),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Bone.text(fontSize: 13),
          ),
          ...List.generate(
            5,
            (_) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Bone.multiText(lines: 2, fontSize: 14),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: context.colorScheme.error),
          const SizedBox(height: 16),
          Text(error, style: context.textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => ref
                .read(transactionDetailProvider(transaction).notifier)
                .refresh(),
            child: const Text('Retry'),
          ),
        ],
      ),
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
    final customIconUrl =
        appId != null ? ref.watch(appIconOverridesProvider)[appId] : null;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildTransactionSummary(
          context,
          ref,
          tx,
          appId: appId,
          appName: tx.app?.name,
          customIconUrl: customIconUrl,
        ),
        if (detail != null) ...[
          _SectionHeader(title: 'Info'),
          _buildInfoSection(context, detail, tx),
          if (detail.subscriptionStatuses?.isNotEmpty == true) ...[
            _SectionHeader(title: 'Entitlements'),
            _buildEntitlements(context, detail.subscriptionStatuses!),
          ],
          _SectionHeader(title: 'Insights'),
          _buildInsights(context, detail, activity),
          if (detail.subscriberAttributes?.isNotEmpty == true) ...[
            _SectionHeader(title: 'Attributes'),
            _buildAttributes(context, detail.subscriberAttributes!),
          ],
        ],
        if (detail?.history?.isNotEmpty == true ||
            activity?.events?.isNotEmpty == true) ...[
          _SectionHeader(title: 'History'),
          _buildHistory(context, detail?.history, activity?.events),
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
    final color = transactionTypeAccentColor(type, context, transaction: tx);

    Widget avatar = TransactionLeadingAvatar(
      imageUrl: customIconUrl,
      size: 48,
      borderRadius: 12,
      tintColor: color,
      fallback: Icon(_typeIcon(type), color: color, size: 24),
    );
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
              currentUrl: customIconUrl,
            ),
            borderRadius: BorderRadius.circular(12),
            child: avatar,
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                avatar,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            productIdentifierDisplayTitle(tx.productIdentifier),
                            style: context.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TransactionTypeBadge(transaction: tx),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tx.productIdentifier ?? '',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (tx.revenue != null)
                  DualCurrencyExactText(
                    amount: tx.revenue!,
                    style: context.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.end,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
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
                  _buildChip(context, null, 'Sandbox',
                      color: context.colorScheme.tertiary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, IconData? icon, String label,
      {Color? color, int maxLines = 1, Color? iconTint}) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: TransactionPillStyle.padding,
        decoration: TransactionPillStyle.decoration(accent),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: iconTint ?? accent,
              ),
              const SizedBox(width: 6),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                label,
                style: TransactionPillStyle.textStyle(accent),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
            icon: Icons.payments_outlined,
            label: 'Total Spent',
            usdAmount: detail.dollarsSpent,
          ),
          const _Divider(),
          _InfoRow(
            icon: Icons.visibility_outlined,
            label: 'Last Seen',
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
              label: 'Country / Locale',
              value:
                  '${detail.lastSeenCountry ?? ""} ${detail.lastSeenLocale ?? ""}'.trim(),
            ),
          ],
          if (detail.app?.name != null) ...[
            const _Divider(),
            _InfoRow(
              icon: Icons.apps_outlined,
              label: 'App',
              value: '${detail.app!.name}${detail.lastSeenAppVersion != null ? " v${detail.lastSeenAppVersion}" : ""}',
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
              label: 'SDK Version',
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
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: statuses.map((s) {
          final isActive = s.isAutoRenewing == true;
          final color = isActive ? Colors.green : Colors.orange;
          final trialAccent =
              transactionTypeAccentColor(RcTransactionType.trial, context);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
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
                    Text(
                      isActive ? 'Active' : 'Inactive',
                      style: context.textTheme.labelSmall?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    if (s.isTrial == true)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: TransactionPillStyle.padding,
                          decoration:
                              TransactionPillStyle.decoration(trialAccent),
                          child: Text(
                            'TRIAL',
                            style: TransactionPillStyle.textStyle(trialAccent),
                          ),
                        ),
                      ),
                    if (s.expiresDate != null)
                      Text(
                        'Expires ${_formatDate(s.expiresDate!)}',
                        style: context.textTheme.labelSmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
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
  ) {
    final insights = <_InsightItem>[];

    if (detail.createdAt != null) {
      final created = DateTime.tryParse(detail.createdAt!);
      if (created != null) {
        final days = DateTime.now().difference(created).inDays;
        insights.add(_InsightItem(
          icon: Icons.schedule_outlined,
          label: 'First purchase',
          value: '$days days ago',
        ));
      }
    }

    if (detail.dollarsSpent != null && detail.dollarsSpent! > 0) {
      insights.add(_InsightItem(
        icon: Icons.attach_money,
        label: 'Total spent',
        usdAmount: detail.dollarsSpent!,
      ));
    }

    final refundCount = activity?.events
            ?.where((e) => e.type == 'REFUND' || e.type == 'CANCELLATION')
            .length ??
        0;
    if (refundCount > 0) {
      insights.add(_InsightItem(
        icon: Icons.undo,
        label: 'Refunds',
        value: '$refundCount',
        color: Colors.red,
      ));
    }

    final transferCount = activity?.events
            ?.where((e) =>
                e.transferredFrom?.isNotEmpty == true ||
                e.transferredTo?.isNotEmpty == true)
            .length ??
        0;
    if (transferCount > 0) {
      insights.add(_InsightItem(
        icon: Icons.swap_horiz,
        label: 'Transfers',
        value: '$transferCount',
      ));
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
    List<RcSubscriberHistory>? history,
    List<RcTransactionDetailEvent>? events,
  ) {
    final items = <_HistoryItem>[];

    for (final h in history ?? <RcSubscriberHistory>[]) {
      final dt = DateTime.tryParse(h.at ?? '');
      items.add(_HistoryItem(
        timestamp: dt?.millisecondsSinceEpoch ?? 0,
        title: h.event ?? 'Event',
        subtitle: h.product ?? '',
        priceUsd: h.priceInUsd,
        date: dt,
      ));
    }

    for (final e in events ?? <RcTransactionDetailEvent>[]) {
      final ms = e.eventTimestampMs ?? e.purchasedAtMs ?? 0;
      final dt = ms > 0
          ? DateTime.fromMillisecondsSinceEpoch(ms)
          : null;
      items.add(_HistoryItem(
        timestamp: ms,
        title: e.type ?? 'Event',
        subtitle: e.productId ?? e.newProductId ?? '',
        priceUsd: e.price,
        date: dt,
      ));
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const _Divider(),
            _HistoryRow(item: items[i]),
          ],
        ],
      ),
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

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.tryParse(dateStr);
      if (dt != null) return DateFormat('MMM d, yyyy').format(dt);
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
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: context.textTheme.labelMedium?.copyWith(
          color: context.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _InfoRow extends ConsumerWidget {
  final IconData icon;
  final String label;
  final String? value;
  final double? usdAmount;
  final bool copyable;
  final Color? color;

  const _InfoRow({
    required this.icon,
    required this.label,
    this.value,
    this.usdAmount,
    this.copyable = false,
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valueStyle = context.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w500,
      color: color,
    );
    final Widget valueWidget = usdAmount != null
        ? DualCurrencyExactText(
            amount: usdAmount!,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color ?? context.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(child: valueWidget),
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
    return Divider(
      height: 1,
      indent: 38,
      endIndent: 12,
      color: context.colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

class _InsightItem {
  final IconData icon;
  final String label;
  final String? value;
  final double? usdAmount;
  final Color? color;

  const _InsightItem({
    required this.icon,
    required this.label,
    this.value,
    this.usdAmount,
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

class _HistoryRow extends ConsumerWidget {
  final _HistoryItem item;

  const _HistoryRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatEventType(item.title),
                  style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (item.subtitle.isNotEmpty)
                  Text(
                    item.subtitle,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                  style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.end,
                ),
              if (item.date != null)
                Text(
                  DateFormat('MMM d, yyyy').format(item.date!),
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatEventType(String type) {
    final words = type.split('_');
    return words.map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }
}
