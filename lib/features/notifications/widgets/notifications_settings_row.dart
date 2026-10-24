import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/features/notifications/notifications_screen.dart';
import 'package:openrc/features/settings/widgets/settings_rows.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';

/// Settings' way into [NotificationsScreen], with where things stand. Reads
/// only local state, so opening Settings doesn't ask RevenueCat anything.
class NotificationsSettingsRow extends ConsumerWidget {
  const NotificationsSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final push = ref.watch(pushSettingsProvider);
    final projects = ref.watch(rcAccountProjectsProvider).value ?? const [];
    final newProjects = push.knownProjects.isEmpty
        ? 0
        : projects
              .where((p) => p.id != null && !push.knownProjects.contains(p.id))
              .length;
    final status = !PushNotifications.isSupported
        ? 'notifications.statusUnsupported'.tr()
        : !push.enabled
        ? (push.blocked
              ? 'notifications.statusBlocked'.tr()
              : 'notifications.statusOff'.tr())
        : newProjects > 0
        ? 'notifications.statusNew'.plural(newProjects)
        : 'notifications.statusOn'.tr();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SettingsRow(
        icon: push.enabled
            ? Icons.notifications_active_rounded
            : Icons.notifications_none_rounded,
        title: 'notifications.rowTitle'.tr(),
        subtitle: status,
        onTap: () => NotificationsScreen.open(context),
      ),
    );
  }
}
