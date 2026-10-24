import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/features/notifications/widgets/kind_list.dart';
import 'package:openrc/features/notifications/widgets/notification_preview.dart';
import 'package:openrc/features/notifications/widgets/project_notifications_sheet.dart';
import 'package:openrc/features/settings/widgets/push_setup_sheet.dart';
import 'package:openrc/features/settings/widgets/settings_rows.dart';
import 'package:openrc/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:openrc/services/push/push_kinds.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/push/push_webhooks.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where turning on stands: choosing projects, then the all-set step.
enum _Flow { none, choose, done }

enum _Save { idle, pending, saving, saved, failed }

/// How the last test notification went.
sealed class _Test {
  const _Test();
}

class _TestIdle extends _Test {
  const _TestIdle();
}

class _TestSending extends _Test {
  const _TestSending();
}

class _TestSent extends _Test {
  const _TestSent();
}

class _TestFailed extends _Test {
  const _TestFailed(this.code);
  final int? code;
}

/// Push notifications: what they are, turning them on (choose projects, then
/// a test), and once on, which projects notify this device.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _Flow _flow = _Flow.none;

  /// Turning on or off, which waits on prompts and RevenueCat.
  bool _busy = false;

  /// Projects ticked while choosing; null until they've loaded.
  Set<String>? _selected;
  int _failures = 0;
  _Test _test = const _TestIdle();

  /// What notifies in every project, while it waits to be saved: changes
  /// are saved a moment after the last tap rather than one by one.
  Set<PushKind>? _pendingKinds;
  Timer? _kindsTimer;
  PushSettingsNotifier? _kindsNotifier;
  _Save _kindsSave = _Save.idle;

  @override
  void dispose() {
    _kindsTimer?.cancel();
    final pending = _pendingKinds;
    if (pending != null) _kindsNotifier?.setKinds(pending);
    super.dispose();
  }

  void _changeKinds(Set<PushKind> kinds) {
    UtilitiesService.hapticSelection();
    _kindsNotifier = ref.read(pushSettingsProvider.notifier);
    setState(() {
      _pendingKinds = kinds;
      _kindsSave = _Save.pending;
    });
    _kindsTimer?.cancel();
    _kindsTimer = Timer(const Duration(milliseconds: 900), _saveKinds);
  }

  Future<void> _saveKinds() async {
    final kinds = _pendingKinds;
    if (kinds == null) return;
    setState(() => _kindsSave = _Save.saving);
    final ok = await ref.read(pushSettingsProvider.notifier).setKinds(kinds);
    if (!mounted) return;
    setState(() {
      if (identical(_pendingKinds, kinds)) _pendingKinds = null;
      _kindsSave = ok ? _Save.saved : _Save.failed;
    });
  }

  Future<void> _turnOn() async {
    if (_busy) return;
    UtilitiesService.hapticSelection();
    setState(() => _busy = true);
    final result = await ref.read(pushSettingsProvider.notifier).enable();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result == PushEnableResult.enabled) {
        _flow = _Flow.choose;
        _selected = null;
        _failures = 0;
      }
    });
    if (result == PushEnableResult.failed) {
      context.showSnackBar('notifications.turnOnFailed'.tr(), isError: true);
    }
  }

  Future<void> _turnOff() async {
    final confirmed = await showAdaptiveForm<bool>(
      context: context,
      title: 'notifications.turnOffTitle'.tr(),
      content: (_) => Text('notifications.turnOffBody'.tr()),
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
          child: Text('notifications.turnOff'.tr()),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await ref.read(pushSettingsProvider.notifier).disable();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _flow = _Flow.none;
      _test = const _TestIdle();
    });
  }

  Future<void> _applyChoice() async {
    final selected = _selected;
    if (selected == null || _busy) return;
    UtilitiesService.hapticSelection();
    setState(() {
      _busy = true;
      _failures = 0;
    });
    final failures = await ref
        .read(pushProjectsProvider.notifier)
        .apply(selected);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failures = failures;
      if (failures == 0) _flow = _Flow.done;
    });
    if (failures == 0) await _sendTest();
  }

  Future<void> _sendTest() async {
    if (_test is _TestSending) return;
    setState(() => _test = const _TestSending());
    _Test outcome;
    try {
      final result = await ref.read(pushProjectsProvider.notifier).sendTest();
      outcome = result == null || result.successful
          ? const _TestSent()
          : _TestFailed(result.responseCode);
    } catch (_) {
      outcome = const _TestFailed(null);
    }
    if (mounted) setState(() => _test = outcome);
  }

  Future<void> _setSandbox(bool sandbox) async {
    UtilitiesService.hapticSelection();
    final ok = await ref
        .read(pushSettingsProvider.notifier)
        .setSandbox(sandbox);
    if (!ok && mounted) {
      context.showSnackBar('notifications.sandboxFailed'.tr(), isError: true);
    }
  }

  Future<void> _toggleProject(String id, bool on) async {
    UtilitiesService.hapticSelection();
    await ref.read(pushProjectsProvider.notifier).toggle(id, on);
  }

  @override
  Widget build(BuildContext context) {
    final push = ref.watch(pushSettingsProvider);
    final inset = AppBreakpoints.centeringInset(
      MediaQuery.sizeOf(context).width,
      maxWidth: 640,
    );
    final padding = EdgeInsets.fromLTRB(16 + inset, 8, 16 + inset, 32);

    Widget body;
    Widget? bottom;
    if (!push.enabled) {
      body = _OffView(
        padding: padding,
        blocked: push.blocked,
        unsupported: !PushNotifications.isSupported,
        busy: _busy,
        onTurnOn: _turnOn,
      );
    } else {
      ref.listen<PushProjectsState>(pushProjectsProvider, (_, next) {
        if (_selected == null && !next.loading) {
          final known = ref.read(pushSettingsProvider).knownProjects;
          setState(() {
            _selected = {
              for (final p in next.projects)
                if (p.connected || known.isEmpty || known.contains(p.id)) p.id,
            };
          });
        }
      });
      final projects = ref.watch(pushProjectsProvider);
      final choosing =
          _flow == _Flow.choose ||
          (_flow == _Flow.none &&
              !projects.loading &&
              !projects.failed &&
              projects.projects.isNotEmpty &&
              projects.connectedCount == 0);
      if (_flow == _Flow.done) {
        body = _DoneView(
          padding: padding,
          connected: projects.connectedCount,
          test: _test,
          onTest: _sendTest,
        );
        bottom = _BottomButton(
          label: 'notifications.done'.tr(),
          onPressed: () => setState(() => _flow = _Flow.none),
        );
      } else if (choosing) {
        final selected = _selected ?? const <String>{};
        body = _ChooseView(
          padding: padding,
          state: projects,
          selected: _selected,
          known: push.knownProjects,
          busy: _busy,
          failures: _failures,
          onToggle: (id, on) => setState(() {
            UtilitiesService.hapticSelection();
            on ? _selected!.add(id) : _selected!.remove(id);
          }),
          onSelectAll: (all) => setState(() {
            UtilitiesService.hapticSelection();
            _selected = all
                ? {for (final p in projects.projects) p.id}
                : <String>{};
          }),
        );
        bottom = _BottomButton(
          label: 'notifications.turnOnFor'.plural(selected.length),
          busy: _busy,
          onPressed: _selected == null || selected.isEmpty || _busy
              ? null
              : _applyChoice,
        );
      } else {
        body = _OnView(
          padding: padding,
          settings: push,
          state: projects,
          busy: _busy,
          test: _test,
          onToggle: _toggleProject,
          onSandbox: _setSandbox,
          onTest: _sendTest,
          onRetry: () => ref.read(pushProjectsProvider.notifier).load(),
          onTurnOff: _turnOff,
          kinds: _pendingKinds ?? push.kinds,
          kindsSave: _kindsSave,
          onKinds: _changeKinds,
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text('notifications.title'.tr())),
      body: AnimatedSwitcher(
        duration: AppMotion.of(context, const Duration(milliseconds: 220)),
        child: KeyedSubtree(key: ValueKey(body.runtimeType), child: body),
      ),
      bottomNavigationBar: bottom,
    );
  }
}

class _OffView extends StatelessWidget {
  const _OffView({
    required this.padding,
    required this.blocked,
    required this.unsupported,
    required this.busy,
    required this.onTurnOn,
  });

  final EdgeInsets padding;
  final bool blocked;

  /// This browser can't receive pushes at all.
  final bool unsupported;
  final bool busy;
  final VoidCallback onTurnOn;

  static Future<void> _openSystemSettings() =>
      launchUrl(Uri.parse('app-settings:'));

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return ListView(
      padding: padding,
      children: [
        const SizedBox(height: 12),
        const NotificationPreview().appCardEntrance(),
        const SizedBox(height: 28),
        Text(
          'notifications.headline'.tr(),
          textAlign: TextAlign.center,
          style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'notifications.subhead'.tr(),
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        _Benefit(
          icon: Icons.bolt_rounded,
          title: 'notifications.benefitInstantTitle'.tr(),
          body: 'notifications.benefitInstantBody'.tr(),
        ),
        _Benefit(
          icon: Icons.auto_awesome_rounded,
          title: 'notifications.benefitSetupTitle'.tr(),
          body: 'notifications.benefitSetupBody'.tr(),
        ),
        _Benefit(
          icon: Icons.lock_outline_rounded,
          title: 'notifications.benefitPrivateTitle'.tr(),
          body: 'notifications.benefitPrivateBody'.tr(),
        ),
        const SizedBox(height: 8),
        if (blocked || unsupported)
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notifications_off_rounded,
                  color: context.appColors.negative,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        unsupported
                            ? 'notifications.unsupported'.tr()
                            : kIsWeb
                            ? 'notifications.blockedWeb'.tr()
                            : 'notifications.blocked'.tr(),
                        style: tt.bodyMedium?.copyWith(height: 1.4),
                      ),
                      if (!kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.iOS) ...[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _openSystemSettings,
                          child: Text('notifications.openSettings'.tr()),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        if (!unsupported)
          FilledButton(
            onPressed: busy ? null : onTurnOn,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('notifications.turnOn'.tr()),
          ),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.icon),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 19, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: tt.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
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

class _ChooseView extends StatelessWidget {
  const _ChooseView({
    required this.padding,
    required this.state,
    required this.selected,
    required this.known,
    required this.busy,
    required this.failures,
    required this.onToggle,
    required this.onSelectAll,
  });

  final EdgeInsets padding;
  final PushProjectsState state;
  final Set<String>? selected;
  final Set<String> known;
  final bool busy;
  final int failures;
  final void Function(String id, bool on) onToggle;
  final ValueChanged<bool> onSelectAll;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final ready = selected != null;
    final allSelected = ready && selected!.length == state.projects.length;
    return ListView(
      padding: padding,
      children: [
        Text(
          'notifications.chooseTitle'.tr(),
          style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'notifications.chooseBody'.tr(),
          style: tt.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        if (failures > 0) ...[
          const SizedBox(height: 12),
          Text(
            'notifications.someFailed'.plural(failures),
            style: tt.bodyMedium?.copyWith(color: context.appColors.negative),
          ),
        ],
        SettingsGroupLabel(
          ready
              ? 'notifications.selectedCount'.tr(
                  namedArgs: {
                    'selected': '${selected!.length}',
                    'total': '${state.projects.length}',
                  },
                )
              : 'notifications.projects'.tr(),
        ),
        _ProjectsCard(
          state: state,
          known: known,
          trailingFor: (p) => p.busy
              ? const _RowSpinner()
              : p.connected && busy
              ? Icon(
                  Icons.check_circle_rounded,
                  color: context.appColors.positive,
                )
              : Checkbox(
                  value: selected?.contains(p.id) ?? true,
                  onChanged: !ready || busy
                      ? null
                      : (v) => onToggle(p.id, v ?? false),
                ),
          onTap: (p) => !ready || busy || p.busy
              ? null
              : () => onToggle(p.id, !selected!.contains(p.id)),
        ),
        if (ready && state.projects.length > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: busy ? null : () => onSelectAll(!allSelected),
              child: Text(
                allSelected
                    ? 'notifications.selectNone'.tr()
                    : 'notifications.selectAll'.tr(),
              ),
            ),
          ),
      ],
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({
    required this.padding,
    required this.connected,
    required this.test,
    required this.onTest,
  });

  final EdgeInsets padding;
  final int connected;
  final _Test test;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return ListView(
      padding: padding,
      children: [
        const SizedBox(height: 32),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: context.appColors.positive.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 40,
              color: context.appColors.positive,
            ),
          ),
        ).appCardEntrance(),
        const SizedBox(height: 20),
        Text(
          'notifications.doneTitle'.tr(),
          textAlign: TextAlign.center,
          style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'notifications.doneBody'.plural(connected),
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        _TestCard(test: test, onTest: onTest),
      ],
    );
  }
}

class _OnView extends StatelessWidget {
  const _OnView({
    required this.padding,
    required this.settings,
    required this.state,
    required this.busy,
    required this.test,
    required this.onToggle,
    required this.onSandbox,
    required this.onTest,
    required this.onRetry,
    required this.onTurnOff,
    required this.kinds,
    required this.kindsSave,
    required this.onKinds,
  });

  final Set<PushKind> kinds;
  final _Save kindsSave;
  final ValueChanged<Set<PushKind>> onKinds;
  final EdgeInsets padding;
  final PushSettings settings;
  final PushProjectsState state;
  final bool busy;
  final _Test test;
  final void Function(String id, bool on) onToggle;
  final ValueChanged<bool> onSandbox;
  final VoidCallback onTest;
  final VoidCallback onRetry;
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return ListView(
      padding: padding,
      children: [
        AppCard(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.appColors.positive.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.tile),
                ),
                child: Icon(
                  Icons.notifications_active_rounded,
                  color: context.appColors.positive,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'notifications.onTitle'.tr(),
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.loading
                          ? 'notifications.checking'.tr()
                          : 'notifications.onBody'.tr(
                              namedArgs: {
                                'connected': '${state.connectedCount}',
                                'total': '${state.projects.length}',
                              },
                            ),
                      style: tt.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ).appCardEntrance(),
        SettingsGroupLabel('notifications.projects'.tr()),
        if (state.failed)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('notifications.loadFailed'.tr()),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: onRetry,
                  child: Text('common.tryAgain'.tr()),
                ),
              ],
            ),
          )
        else
          _ProjectsCard(
            state: state,
            known: settings.knownProjects,
            custom: settings.projectKinds,
            trailingFor: (p) => p.busy
                ? const _RowSpinner()
                : Switch(
                    value: p.connected,
                    onChanged: busy ? null : (v) => onToggle(p.id, v),
                  ),
            onTap: (p) => p.busy
                ? null
                : () => showProjectNotificationsSheet(context, p.id),
          ).appCardEntrance(delay: const Duration(milliseconds: 40)),
        SettingsGroupLabel('notifications.options'.tr()),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsRow(
                icon: Icons.science_rounded,
                title: 'notifications.sandbox'.tr(),
                subtitle: 'notifications.sandboxHint'.tr(),
                trailing: Switch(
                  value: settings.sandbox,
                  onChanged: busy ? null : onSandbox,
                ),
                showChevron: false,
                onTap: busy ? null : () => onSandbox(!settings.sandbox),
              ),
              const Divider(indent: kSettingsDividerIndent),
              SettingsRow(
                icon: Icons.send_rounded,
                title: 'notifications.sendTest'.tr(),
                subtitle: _testText(test),
                trailing: test is _TestSending ? const _RowSpinner() : null,
                showChevron: false,
                onTap: state.connectedCount == 0 || test is _TestSending
                    ? null
                    : onTest,
              ),
            ],
          ),
        ).appCardEntrance(delay: const Duration(milliseconds: 80)),
        SettingsGroupLabel('notifications.notifyAbout'.tr()),
        Text(
          'notifications.notifyAboutHint'.tr(),
          style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        KindPresets(selected: kinds, onSelected: onKinds),
        KindList(
          selected: kinds,
          onChanged: (kind, on) =>
              onKinds(on ? {...kinds, kind} : ({...kinds}..remove(kind))),
        ),
        if (_saveText(kindsSave) case final text?)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              text,
              style: tt.bodySmall?.copyWith(
                color: kindsSave == _Save.failed
                    ? context.appColors.negative
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 16),
        GroupedRows(
          children: [
            SettingsRow(
              icon: Icons.integration_instructions_rounded,
              title: 'notifications.manual'.tr(),
              subtitle: 'notifications.manualHint'.tr(),
              onTap: () => showPushSetupSheet(context),
            ),
            SettingsRow(
              icon: Icons.notifications_off_rounded,
              title: 'notifications.turnOff'.tr(),
              destructive: true,
              showChevron: false,
              onTap: busy ? null : onTurnOff,
            ),
          ],
        ),
      ],
    );
  }
}

/// Two rows in one card with a divider between them.
class GroupedRows extends StatelessWidget {
  const GroupedRows({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: kSettingsDividerIndent),
            children[i],
          ],
        ],
      ),
    );
  }
}

String? _saveText(_Save save) => switch (save) {
  _Save.idle => null,
  _Save.pending || _Save.saving => 'notifications.saving'.tr(),
  _Save.saved => 'notifications.saved'.tr(),
  _Save.failed => 'notifications.saveFailed'.tr(),
};

String? _testText(_Test test) => switch (test) {
  _TestIdle() => 'notifications.sendTestHint'.tr(),
  _TestSending() => 'notifications.testSending'.tr(),
  _TestSent() => 'notifications.testSent'.tr(),
  _TestFailed(:final code) =>
    code == null
        ? 'notifications.testUnreachable'.tr()
        : 'notifications.testFailed'.tr(namedArgs: {'code': '$code'}),
};

class _TestCard extends StatelessWidget {
  const _TestCard({required this.test, required this.onTest});

  final _Test test;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final failed = test is _TestFailed;
    final sent = test is _TestSent;
    final color = failed
        ? context.appColors.negative
        : sent
        ? context.appColors.positive
        : context.colorScheme.onSurfaceVariant;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (test is _TestSending)
                const _RowSpinner()
              else
                Icon(
                  failed
                      ? Icons.error_outline_rounded
                      : sent
                      ? Icons.mark_email_read_rounded
                      : Icons.send_rounded,
                  color: color,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _testText(test) ?? '',
                  style: context.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
          if (test is! _TestSending) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onTest,
              child: Text(
                test is _TestIdle
                    ? 'notifications.sendTest'.tr()
                    : 'notifications.sendAgain'.tr(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The projects with their app icons; [trailingFor] puts a switch,
/// checkbox or progress on each row.
class _ProjectsCard extends StatelessWidget {
  const _ProjectsCard({
    required this.state,
    required this.known,
    required this.trailingFor,
    required this.onTap,
    this.custom = const {},
  });

  final PushProjectsState state;
  final Set<String> known;

  /// Projects with their own choice of kinds.
  final Map<String, Set<PushKind>> custom;
  final Widget Function(PushProject project) trailingFor;
  final VoidCallback? Function(PushProject project) onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.textTheme;
    if (state.projects.isEmpty) {
      return AppCard(
        child: state.loading
            ? const Center(child: _RowSpinner())
            : Text(
                'notifications.noProjects'.tr(),
                style: tt.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
      );
    }
    return GroupedRows(
      children: [
        for (final p in state.projects)
          _ProjectRow(
            project: p,
            isNew: known.isNotEmpty && !known.contains(p.id),
            customKinds: custom[p.id]?.length,
            trailing: trailingFor(p),
            onTap: onTap(p),
          ),
      ],
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    required this.isNew,
    required this.trailing,
    required this.onTap,
    this.customKinds,
  });

  final PushProject project;
  final bool isNew;

  /// How many kinds the project's own choice has, when it has one.
  final int? customKinds;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final name = project.project.name ?? project.id;
    final error = project.error;
    final status = error != null
        ? (error.isEmpty ? 'notifications.projectFailed'.tr() : error)
        : project.busy
        ? 'notifications.projectWorking'.tr()
        : project.connected && customKinds != null
        ? 'notifications.projectCustom'.plural(customKinds!)
        : project.connected
        ? 'notifications.projectOn'.tr()
        : 'notifications.projectOff'.tr();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            TransactionLeadingAvatar(
              imageUrl: project.project.iconUrl,
              size: 34,
              borderRadius: 9,
              tintColor: scheme.primary,
              fallback: Center(
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: tt.titleSmall?.copyWith(
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isNew) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            'notifications.new'.tr(),
                            style: tt.labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status,
                    style: tt.bodySmall?.copyWith(
                      color: error != null
                          ? context.appColors.negative
                          : project.connected
                          ? context.appColors.positive
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _RowSpinner extends StatelessWidget {
  const _RowSpinner();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(12),
    child: SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

class _BottomButton extends StatelessWidget {
  const _BottomButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final inset = AppBreakpoints.centeringInset(
      MediaQuery.sizeOf(context).width,
      maxWidth: 640,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16 + inset, 8, 16 + inset, 12),
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(label),
        ),
      ),
    );
  }
}
