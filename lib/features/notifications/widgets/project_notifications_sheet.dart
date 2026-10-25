import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/features/notifications/widgets/kind_list.dart';
import 'package:openrc/features/notifications/widgets/project_webhooks_sheet.dart';
import 'package:openrc/features/settings/widgets/settings_rows.dart';
import 'package:openrc/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:openrc/services/push/push_kinds.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/push/push_webhooks.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/app_segmented_control.dart';

/// One project: whether it notifies this device, and what it notifies about.
Future<void> showProjectNotificationsSheet(
  BuildContext context,
  String projectId,
) {
  return showAdaptiveSheet<void>(
    context: context,
    heightFactor: 0.9,
    builder: (_) => _ProjectNotificationsSheet(projectId: projectId),
  );
}

class _ProjectNotificationsSheet extends ConsumerStatefulWidget {
  const _ProjectNotificationsSheet({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_ProjectNotificationsSheet> createState() =>
      _ProjectNotificationsSheetState();
}

class _ProjectNotificationsSheetState
    extends ConsumerState<_ProjectNotificationsSheet> {
  /// The project's own choice being edited; null follows every project's.
  late Set<PushKind>? _custom = ref
      .read(pushSettingsProvider)
      .projectKinds[widget.projectId];
  bool _saving = false;
  bool _failed = false;

  bool get _changed {
    final saved = ref.read(pushSettingsProvider).projectKinds[widget.projectId];
    if (saved == null || _custom == null) return saved != _custom;
    return saved.length != _custom!.length || !saved.containsAll(_custom!);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    final ok = await ref
        .read(pushSettingsProvider.notifier)
        .setProjectKinds(widget.projectId, _custom);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _failed = !ok;
    });
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final settings = ref.watch(pushSettingsProvider);
    final project = ref
        .watch(pushProjectsProvider)
        .projects
        .where((p) => p.id == widget.projectId)
        .firstOrNull;
    if (project == null) return const SizedBox.shrink();
    final name = project.project.name ?? project.id;
    final custom = _custom;

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
                    imageUrl: project.project.iconUrl,
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
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                clipBehavior: Clip.antiAlias,
                child: SettingsRow(
                  icon: Icons.notifications_active_rounded,
                  title: 'notifications.projectSheet.notify'.tr(),
                  subtitle: project.error?.isNotEmpty == true
                      ? project.error
                      : null,
                  trailing: project.busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Switch(
                          value: project.connected,
                          onChanged: (on) {
                            UtilitiesService.hapticSelection();
                            ref
                                .read(pushProjectsProvider.notifier)
                                .toggle(project.id, on);
                          },
                        ),
                  showChevron: false,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                child: SettingsRow(
                  icon: Icons.webhook_rounded,
                  title: 'webhooks.title'.tr(),
                  subtitle: 'webhooks.rowHint'.tr(),
                  onTap: () =>
                      showProjectWebhooksSheet(context, widget.projectId),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'notifications.projectSheet.what'.tr(),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              AppSegmentedControl<bool>(
                values: const [false, true],
                labels: {
                  false: 'notifications.projectSheet.same'.tr(),
                  true: 'notifications.projectSheet.custom'.tr(),
                },
                groupValue: custom != null,
                onValueChanged: _saving
                    ? null
                    : (value) {
                        UtilitiesService.hapticSelection();
                        setState(() {
                          _custom = value == true
                              ? {...settings.kinds}
                              : null;
                        });
                      },
              ),
              const SizedBox(height: 8),
              Text(
                custom == null
                    ? 'notifications.projectSheet.sameHint'.plural(
                        settings.kinds.length,
                      )
                    : 'notifications.projectSheet.customHint'.tr(),
                style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (custom != null) ...[
                const SizedBox(height: 12),
                KindPresets(
                  selected: custom,
                  onSelected: _saving
                      ? null
                      : (kinds) => setState(() => _custom = kinds),
                ),
                KindList(
                  selected: custom,
                  onChanged: _saving
                      ? null
                      : (kind, on) => setState(() {
                          UtilitiesService.hapticSelection();
                          _custom = {...custom};
                          on ? _custom!.add(kind) : _custom!.remove(kind);
                        }),
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
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'notifications.projectSheet.saveFailed'.tr(),
                    textAlign: TextAlign.center,
                    style: tt.bodyMedium?.copyWith(
                      color: context.appColors.negative,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: _saving || !_changed ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('notifications.projectSheet.save'.tr()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
