import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/features/settings/widgets/settings_rows.dart';
import 'package:openrc/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:openrc/models/rc_webhook.dart';
import 'package:openrc/services/push/push_webhooks.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/grouped_list.dart';

/// Every webhook in one project, so one RevenueCat refuses to add another to
/// can be cleared. Deleting this device's own webhook is allowed, but named as
/// such: it stops notifications for the project.
Future<void> showProjectWebhooksSheet(
  BuildContext context,
  String projectId,
) {
  return showAdaptiveSheet<void>(
    context: context,
    heightFactor: 0.9,
    builder: (_) => _ProjectWebhooksSheet(projectId: projectId),
  );
}

class _ProjectWebhooksSheet extends ConsumerStatefulWidget {
  const _ProjectWebhooksSheet({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_ProjectWebhooksSheet> createState() =>
      _ProjectWebhooksSheetState();
}

class _ProjectWebhooksSheetState
    extends ConsumerState<_ProjectWebhooksSheet> {
  Future<void> _delete(ProjectWebhook webhook) async {
    final confirmed = await _confirm(
      title: 'webhooks.deleteTitle'.tr(namedArgs: {'name': webhook.title}),
      body: webhook.owner == WebhookOwner.thisDevice
          ? 'webhooks.deleteOwnBody'.tr()
          : 'webhooks.deleteBody'.tr(),
      action: 'webhooks.delete'.tr(),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(projectWebhooksProvider(widget.projectId).notifier)
        .delete(webhook.id);
  }

  Future<void> _deleteOwnedBy(WebhookOwner owner) async {
    final count = ref
        .read(projectWebhooksProvider(widget.projectId))
        .ownedBy(owner)
        .length;
    final confirmed = await _confirm(
      title: 'webhooks.deleteAllOpenRc'.tr(),
      body: 'webhooks.deleteAllOpenRcBody'.plural(count),
      action: 'webhooks.deleteCount'.plural(count),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(projectWebhooksProvider(widget.projectId).notifier)
        .deleteOwnedBy(owner);
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) => showAdaptiveForm<bool>(
    context: context,
    title: title,
    content: (_) => Text(body),
    actions: (dialogContext) => [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(false),
        child: Text('settings.cancel'.tr()),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: dialogContext.appColors.negative,
          foregroundColor: Colors.white,
        ),
        onPressed: () => Navigator.of(dialogContext).pop(true),
        child: Text(action),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final state = ref.watch(projectWebhooksProvider(widget.projectId));
    final project = ref
        .watch(pushProjectsProvider)
        .projects
        .where((p) => p.id == widget.projectId)
        .firstOrNull;
    final name = project?.project.name ?? widget.projectId;
    final count = state.webhooks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              Row(
                children: [
                  TransactionLeadingAvatar(
                    imageUrl: project?.project.iconUrl,
                    size: 44,
                    borderRadius: 11,
                    tintColor: scheme.primary,
                    fallback: Center(
                      child: Text(
                        name.isEmpty
                            ? '?'
                            : name.characters.first.toUpperCase(),
                        style: tt.titleMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'webhooks.count'.plural(count),
                          style: tt.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (state.loading && count == 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.failed && count == 0)
                _FailedRow(
                  message: state.error,
                  onRetry: () => ref
                      .read(projectWebhooksProvider(widget.projectId).notifier)
                      .load(),
                )
              else if (count == 0)
                Text(
                  'webhooks.none'.tr(),
                  style: tt.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else ...[
                for (final owner in WebhookOwner.values)
                  ..._section(context, owner, state),
                if (state.deleteFailed)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'webhooks.deleteFailed'.tr(),
                      style: tt.bodyMedium?.copyWith(
                        color: context.appColors.negative,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.ownedBy(WebhookOwner.openRcOther).isNotEmpty)
                OutlinedButton(
                  onPressed: state.deleting.isEmpty
                      ? () => _deleteOwnedBy(WebhookOwner.openRcOther)
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('webhooks.deleteAllOpenRc'.tr()),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// One owner's webhooks under its own heading, or nothing when it has none.
  List<Widget> _section(
    BuildContext context,
    WebhookOwner owner,
    ProjectWebhooksState state,
  ) {
    final hooks = state.ownedBy(owner);
    if (hooks.isEmpty) return const [];
    return [
      SettingsGroupLabel(switch (owner) {
        WebhookOwner.thisDevice => 'webhooks.sectionDevice'.tr(),
        WebhookOwner.openRcOther => 'webhooks.sectionOtherOpenRc'.tr(),
        WebhookOwner.foreign => 'webhooks.sectionOther'.tr(),
      }),
      GroupedCard(
        margin: EdgeInsets.zero,
        dividerIndent: kSettingsDividerIndent,
        children: [
          for (final hook in hooks)
            SettingsRow(
              icon: Icons.webhook_rounded,
              title: hook.title,
              subtitle: _subtitle(hook),
              showChevron: false,
              trailing: state.deleting.contains(hook.id)
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      onPressed: state.deleting.isEmpty
                          ? () => _delete(hook)
                          : null,
                      tooltip: 'webhooks.delete'.tr(),
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: context.appColors.negative,
                      ),
                    ),
            ),
        ],
      ),
    ];
  }

  /// Where the webhook points, and roughly how much it sends.
  String _subtitle(ProjectWebhook hook) {
    final parts = [
      hook.webhook.host,
      _environment(hook.webhook),
      if (hook.eventTypeCount > 0) 'webhooks.events'.plural(hook.eventTypeCount),
    ].whereType<String>().where((p) => p.isNotEmpty);
    return parts.join(' · ');
  }

  String? _environment(RcWebhook webhook) => switch (webhook.environment) {
    null => null,
    'production' => 'webhooks.environmentProduction'.tr(),
    'sandbox' => 'webhooks.environmentSandbox'.tr(),
    final other => other,
  };
}

class _FailedRow extends StatelessWidget {
  const _FailedRow({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message?.isNotEmpty == true
                ? message!
                : 'webhooks.loadFailed'.tr(),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onRetry,
            child: Text('common.tryAgain'.tr()),
          ),
        ],
      ),
    );
  }
}
