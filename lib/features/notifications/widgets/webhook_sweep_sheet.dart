import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/features/settings/widgets/settings_rows.dart';
import 'package:openrc/services/push/push_webhooks.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/grouped_list.dart';

/// Deletes every webhook in the account's projects that this device didn't
/// make, which is what clears a project RevenueCat refuses to add another to.
/// This device's own webhooks stay, so notifications keep arriving.
Future<void> showWebhookSweepSheet(BuildContext context) {
  return showAdaptiveSheet<void>(
    context: context,
    heightFactor: 0.9,
    builder: (_) => const _WebhookSweepSheet(),
  );
}

class _WebhookSweepSheet extends ConsumerStatefulWidget {
  const _WebhookSweepSheet();

  @override
  ConsumerState<_WebhookSweepSheet> createState() => _WebhookSweepSheetState();
}

class _WebhookSweepSheetState extends ConsumerState<_WebhookSweepSheet> {
  Future<void> _confirmAndSweep(int others) async {
    final confirmed = await showAdaptiveForm<bool>(
      context: context,
      title: 'webhooks.sweepConfirmTitle'.tr(),
      content: (_) => Text('webhooks.sweepConfirmBody'.plural(others)),
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
          child: Text('webhooks.sweepAction'.plural(others)),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    await ref.read(webhookSweepProvider.notifier).sweep();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final state = ref.watch(webhookSweepProvider);
    final others = state.others;
    final result = state.result;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              Text(
                'webhooks.sweepTitle'.tr(),
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'webhooks.sweepBody'.tr(),
                style: tt.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              if (state.loading && state.projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.failed && state.projects.isEmpty)
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.error?.isNotEmpty == true
                            ? state.error!
                            : 'webhooks.loadFailed'.tr(),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () =>
                            ref.read(webhookSweepProvider.notifier).load(),
                        child: Text('common.tryAgain'.tr()),
                      ),
                    ],
                  ),
                )
              else if (state.projects.isEmpty)
                Text(
                  'webhooks.noProjects'.tr(),
                  style: tt.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else ...[
                Text(
                  'webhooks.sweepSummary'.tr(
                    namedArgs: {
                      'mine': '${state.mine}',
                      'other': '$others',
                    },
                  ),
                  style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                GroupedCard(
                  margin: EdgeInsets.zero,
                  dividerIndent: kSettingsDividerIndent,
                  children: [
                    for (final project in state.projects)
                      SettingsRow(
                        icon: Icons.webhook_rounded,
                        title: project.name,
                        subtitle: 'webhooks.sweepProject'.tr(
                          namedArgs: {
                            'mine': '${project.mine}',
                            'other': '${project.others}',
                          },
                        ),
                        showChevron: false,
                        destructive: project.others > project.mine,
                        trailing: project.others == 0
                            ? Icon(
                                Icons.check_rounded,
                                size: 20,
                                color: context.appColors.positive,
                              )
                            : null,
                      ),
                  ],
                ),
                if (!state.running && result != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      result.ok
                          ? 'webhooks.sweepDone'.plural(result.deleted)
                          : 'webhooks.sweepFailed'.tr(),
                      style: tt.bodyMedium?.copyWith(
                        color: result.ok
                            ? context.appColors.positive
                            : context.appColors.negative,
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
          child: FilledButton(
            onPressed: state.running || others == 0
                ? null
                : () => _confirmAndSweep(others),
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.negative,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: state.running
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'webhooks.sweeping'.tr(
                          namedArgs: {'count': '${state.progress}'},
                        ),
                      ),
                    ],
                  )
                : Text(
                    others == 0
                        ? 'webhooks.sweepNothing'.tr()
                        : 'webhooks.sweepAction'.plural(others),
                  ),
          ),
        ),
      ],
    );
  }
}
